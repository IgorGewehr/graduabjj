'use strict';

// QA — CORE pilar (gamificação): executable specification of the (FIXED)
// query-before-create race in upsertAutoAchievement.
//
// ANCHOR: functions/server_functions.js:1185-1225 (upsertAutoAchievement)
//   const docId = `${studentId}_${autoKey}`;
//   await docRef.create({ ... });   // atomic: throws ALREADY_EXISTS (code 6)
//   catch err.code === 6 -> return false (no-op)
//
// Historico: a versao auditada fazia READ-then-WRITE (query where studentId +
// autoKey, depois ref.add() com auto-id) sem transacao. Sob concorrencia exata
// (cron diaria 07:30 sobrepondo o callable recomputeStudentMilestones, ou dois
// cliques rapidos) duas execucoes observavam existing.empty === true e AMBAS
// faziam add(), duplicando o milestone do mesmo (studentId, autoKey). O fix
// (commit 7952bc0) adotou id deterministico + .create() atomico.
//
// upsertAutoAchievement is module-internal (not exported) and captures
// `db = admin.firestore()` at require-time, so we cannot inject a mock into the
// real function without the emulator. Instead we model the EXACT control flow of
// both the LEGACY (pre-fix) strategy and the CURRENT production strategy against
// a tiny Firestore-shaped fake with a deterministic interleave scheduler, proving:
//   (a) the legacy query-then-add shape DUPLICATES under interleaving (why the
//       fix was needed), and
//   (b) the production deterministic-doc-id + create() shape does NOT.
// A SOURCE CANARY then asserts production still uses shape (b) — it flips if
// anyone regresses to query-before-create.

const test = require('node:test');
const assert = require('node:assert/strict');

// ---------------------------------------------------------------------------
// Minimal in-memory Firestore collection fake.
//   - get() resolves AFTER a caller-controlled gate (so we can interleave).
//   - add() appends an auto-id doc.
//   - doc(id).create() throws ALREADY_EXISTS if id is present (atomic create).
// ---------------------------------------------------------------------------
function makeCollection() {
  const store = new Map(); // docId -> data
  let auto = 0;
  return {
    store,
    // Query that matches the legacy filter: studentId + autoKey.
    queryMatching(studentId, autoKey, gate) {
      return {
        async get() {
          if (gate) await gate; // allow the test to interleave before the read result is used
          const matches = [...store.values()].filter(
            (d) => d.studentId === studentId && d.autoKey === autoKey
          );
          return { empty: matches.length === 0, size: matches.length };
        },
      };
    },
    async add(data) {
      const id = `auto_${auto++}`;
      store.set(id, { ...data });
      return { id };
    },
    docCreate(id, data) {
      // Models Firestore .doc(id).create(): atomic, throws if exists.
      if (store.has(id)) {
        const err = new Error('ALREADY_EXISTS');
        err.code = 6; // Firestore ALREADY_EXISTS gRPC code
        throw err;
      }
      store.set(id, { ...data });
    },
  };
}

// LEGACY (pre-7952bc0) strategy: query-before-create, auto-id, no txn.
// Kept as the executable proof of WHY the fix exists.
async function upsertLegacy(col, studentId, autoKey, gate) {
  const existing = await col.queryMatching(studentId, autoKey, gate).get();
  if (!existing.empty) return false;
  await col.add({ studentId, autoKey });
  return true;
}

// CURRENT production strategy (server_functions.js:1192-1224): deterministic
// doc-id + create() (atomic; ALREADY_EXISTS => no-op).
async function upsertProduction(col, studentId, autoKey) {
  const id = `${studentId}_${autoKey}`;
  try {
    col.docCreate(id, { studentId, autoKey });
    return true;
  } catch (e) {
    if (e.code === 6) return false; // ALREADY_EXISTS — concurrent peer won the race
    throw e;
  }
}

test('SEQUENTIAL: legacy strategy was correctly idempotent (no dup)', async () => {
  const col = makeCollection();
  const a = await upsertLegacy(col, 's1', 'streak_7');
  const b = await upsertLegacy(col, 's1', 'streak_7');
  assert.equal(a, true, 'first creates');
  assert.equal(b, false, 'second is a no-op');
  assert.equal(col.store.size, 1, 'exactly one milestone after sequential calls');
});

test('CONCURRENT: legacy strategy DUPLICATES under exact interleave (the historical bug)', async () => {
  const col = makeCollection();

  // Two executions for the SAME (studentId, autoKey): cron worker vs on-demand
  // recompute callable hitting the same student at the same instant. We gate both
  // reads so they BOTH resolve before either add() runs — the worst-case but
  // entirely possible interleave on Firestore (no txn => no read isolation).
  let releaseReads;
  const readGate = new Promise((r) => { releaseReads = r; });

  const exec1 = upsertLegacy(col, 's1', 'streak_7', readGate);
  const exec2 = upsertLegacy(col, 's1', 'streak_7', readGate);

  // Both reads observe an empty collection, THEN both proceed to add().
  releaseReads();
  const [r1, r2] = await Promise.all([exec1, exec2]);

  assert.equal(r1, true, 'exec1 thinks it created');
  assert.equal(r2, true, 'exec2 ALSO thinks it created');
  assert.equal(
    col.store.size,
    2,
    'legacy bug: two duplicate milestones for the same (studentId, autoKey)'
  );
});

test('CONCURRENT: production strategy (deterministic id + create) is dup-free', async () => {
  const col = makeCollection();

  // Same interleave intent, but create() on a deterministic id is atomic: the
  // second create() throws ALREADY_EXISTS and the upsert no-ops.
  const [r1, r2] = await Promise.all([
    upsertProduction(col, 's1', 'streak_7'),
    upsertProduction(col, 's1', 'streak_7'),
  ]);

  // Exactly one wins, the other no-ops; never two docs.
  assert.equal(r1 !== r2, true, 'exactly one create succeeds, the other no-ops');
  assert.equal(col.store.size, 1, 'single milestone even under concurrency');
  assert.ok(col.store.has('s1_streak_7'), 'doc id is deterministic ${studentId}_${autoKey}');
});

// Guard: the production source uses the ATOMIC shape (deterministic doc id +
// .create() with ALREADY_EXISTS treated as no-op). If a future refactor regresses
// to query-before-create / auto-id add(), this test flips — it is the canary
// that keeps the race closed.
test('SOURCE CANARY: production upsertAutoAchievement is atomic (id deterministico + create)', () => {
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  // Isolate the function body (ends at the first column-0 closing brace).
  const start = src.indexOf('async function upsertAutoAchievement');
  assert.ok(start > 0, 'upsertAutoAchievement present');
  const end = src.indexOf('\n}', start);
  assert.ok(end > start, 'function body delimited');
  const body = src.slice(start, end);

  // The fix contract (proven dup-free above) is in place:
  assert.match(body, /const docId = `\$\{studentId\}_\$\{autoKey\}`/,
    'deterministic doc id `${studentId}_${autoKey}`');
  assert.match(body, /await docRef\.create\(/, 'atomic .create() (not add/set)');
  assert.match(body, /err\.code === 6/, 'ALREADY_EXISTS (code 6) treated as no-op');

  // And the legacy racy shape is gone:
  assert.doesNotMatch(body, /\.where\(/, 'REGRESSION: query-before-create is back');
  assert.doesNotMatch(body, /\.add\(/, 'REGRESSION: auto-id add() is back');
});
