'use strict';

// QA — CORE pilar (gamificação): adversarial proof of the non-atomic
// query-before-create race in upsertAutoAchievement.
//
// ANCHOR: functions/server_functions.js:1177-1211 (upsertAutoAchievement)
//   const existing = await ref.where('studentId','==',sid)
//                              .where('autoKey','==',key).limit(1).get();
//   if (!existing.empty) return false;
//   await ref.add({ ... });        // <-- auto-id, no txn, no .create()
//
// The idempotency guard is a READ-then-WRITE with no transaction and no
// deterministic doc-id. Under exact concurrency (daily cron 07:30 overlapping
// the on-demand recomputeStudentMilestones callable, or two rapid clicks) two
// executions can both observe existing.empty === true and BOTH add(), minting a
// duplicate milestone for the same (studentId, autoKey).
//
// upsertAutoAchievement is module-internal (not exported) and captures
// `db = admin.firestore()` at require-time, so we cannot inject a mock into the
// real function without the emulator. Instead we model the EXACT control flow of
// both the current (buggy) strategy and the proposed fix against a tiny
// Firestore-shaped fake with a deterministic interleave scheduler, proving:
//   (a) the current query-then-add shape DUPLICATES under interleaving, and
//   (b) the proposed deterministic-doc-id + create() shape does NOT.
// This is an executable specification of the bug + its fix contract.

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
    // Query that matches the production filter: studentId + autoKey.
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

// Current production strategy (query-before-create, auto-id, no txn).
// Faithful to server_functions.js:1185-1210.
async function upsertCurrent(col, studentId, autoKey, gate) {
  const existing = await col.queryMatching(studentId, autoKey, gate).get();
  if (!existing.empty) return false;
  await col.add({ studentId, autoKey });
  return true;
}

// Proposed fix: deterministic doc-id + create() (atomic; ALREADY_EXISTS => no-op).
async function upsertFixed(col, studentId, autoKey) {
  const id = `${studentId}_${autoKey}`;
  try {
    col.docCreate(id, { studentId, autoKey });
    return true;
  } catch (e) {
    if (e.code === 6) return false; // ALREADY_EXISTS — concurrent peer won the race
    throw e;
  }
}

test('SEQUENTIAL: current strategy is correctly idempotent (no dup)', async () => {
  const col = makeCollection();
  const a = await upsertCurrent(col, 's1', 'streak_7');
  const b = await upsertCurrent(col, 's1', 'streak_7');
  assert.equal(a, true, 'first creates');
  assert.equal(b, false, 'second is a no-op');
  assert.equal(col.store.size, 1, 'exactly one milestone after sequential calls');
});

test('CONCURRENT: current strategy DUPLICATES (the bug) under exact interleave', async () => {
  const col = makeCollection();

  // Two executions for the SAME (studentId, autoKey): cron worker vs on-demand
  // recompute callable hitting the same student at the same instant. We gate both
  // reads so they BOTH resolve before either add() runs — the worst-case but
  // entirely possible interleave on Firestore (no txn => no read isolation).
  let releaseReads;
  const readGate = new Promise((r) => { releaseReads = r; });

  const exec1 = upsertCurrent(col, 's1', 'streak_7', readGate);
  const exec2 = upsertCurrent(col, 's1', 'streak_7', readGate);

  // Both reads observe an empty collection, THEN both proceed to add().
  releaseReads();
  const [r1, r2] = await Promise.all([exec1, exec2]);

  assert.equal(r1, true, 'exec1 thinks it created');
  assert.equal(r2, true, 'exec2 ALSO thinks it created');
  assert.equal(
    col.store.size,
    2,
    'BUG: two duplicate milestones for the same (studentId, autoKey)'
  );
});

test('CONCURRENT: proposed fix (deterministic id + create) is dup-free', async () => {
  const col = makeCollection();

  // Same interleave intent, but create() on a deterministic id is atomic: the
  // second create() throws ALREADY_EXISTS and the upsert no-ops.
  const [r1, r2] = await Promise.all([
    upsertFixed(col, 's1', 'streak_7'),
    upsertFixed(col, 's1', 'streak_7'),
  ]);

  // Exactly one wins, the other no-ops; never two docs.
  assert.equal(r1 !== r2, true, 'exactly one create succeeds, the other no-ops');
  assert.equal(col.store.size, 1, 'FIX: single milestone even under concurrency');
  assert.ok(col.store.has('s1_streak_7'), 'doc id is deterministic ${studentId}_${autoKey}');
});

// Guard: the production source still uses the non-atomic shape (ref.add + a
// query-before-create, with NO runTransaction and NO .create()). If a future
// refactor adopts the fix, this test flips and should be updated — it is the
// canary that the bug is still present.
test('SOURCE CANARY: production upsertAutoAchievement is still non-atomic', () => {
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  // Isolate the function body.
  const start = src.indexOf('async function upsertAutoAchievement');
  assert.ok(start > 0, 'upsertAutoAchievement present');
  const body = src.slice(start, start + 1500);

  assert.match(body, /\.where\('studentId'/, 'still query-before-create');
  assert.match(body, /await ref\.add\(/, 'still uses auto-id ref.add()');
  assert.doesNotMatch(body, /runTransaction/, 'no transaction (race open)');
  assert.doesNotMatch(body, /\.create\(/, 'no atomic .create() (race open)');
});
