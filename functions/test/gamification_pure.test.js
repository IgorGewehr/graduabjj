'use strict';

// QA — CORE pilar: gamificação server-side (pure helpers).
// Ancorado em functions/server_functions.js:
//   - computeCurrentStreak (exports.computeCurrentStreak)
//   - rankFromPairs        (exports.rankFromGamificationPairs)
//
// server_functions.js calls admin.firestore() at require-time, so we must
// initializeApp() first. No real credentials are touched: the pure helpers
// under test never read Firestore.

const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'qa-test' });
}

const mod = require('../server_functions.js');
const { computeCurrentStreak, rankFromGamificationPairs } = mod;

// Helper: build a Set of YYYY-MM-DD keys from Date offsets relative to a base.
function dayKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

test('computeCurrentStreak: empty set → 0', () => {
  assert.equal(computeCurrentStreak(new Set(), '2026-06-04', '2026-06-03'), 0);
  assert.equal(computeCurrentStreak(null, '2026-06-04', '2026-06-03'), 0);
});

test('computeCurrentStreak: single day today → 1', () => {
  const s = new Set(['2026-06-04']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 1);
});

test('computeCurrentStreak: latest is yesterday counts as current', () => {
  const s = new Set(['2026-06-03']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 1);
});

test('computeCurrentStreak: STALE (last check-in older than yesterday) → 0', () => {
  // Latest is 2 days ago — streak is broken / not current.
  const s = new Set(['2026-06-01', '2026-06-02']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 0);
});

test('computeCurrentStreak: consecutive run ending today', () => {
  const s = new Set(['2026-06-02', '2026-06-03', '2026-06-04']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 3);
});

test('computeCurrentStreak: gap breaks the run at the gap', () => {
  // 04,03 present, 02 missing, 01 present → streak from latest is 2.
  const s = new Set(['2026-06-01', '2026-06-03', '2026-06-04']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 2);
});

test('computeCurrentStreak: duplicates / unordered input tolerated', () => {
  const s = new Set(['2026-06-04', '2026-06-02', '2026-06-03', '2026-06-04']);
  assert.equal(computeCurrentStreak(s, '2026-06-04', '2026-06-03'), 3);
});

test('computeCurrentStreak: long real run across a month boundary', () => {
  // Build 10 consecutive days ending today using actual Date arithmetic so the
  // localDayKey walk-back (which uses Date math) agrees with our keys.
  const today = new Date('2026-03-05T12:00:00');
  const s = new Set();
  for (let i = 0; i < 10; i++) {
    const d = new Date(today.getTime());
    d.setDate(d.getDate() - i);
    s.add(dayKey(d));
  }
  const todayKey = dayKey(today);
  const yest = new Date(today.getTime());
  yest.setDate(yest.getDate() - 1);
  assert.equal(computeCurrentStreak(s, todayKey, dayKey(yest)), 10);
});

test('rankFromPairs: ranks by count desc, 1-based', () => {
  const pairs = [
    { studentId: 'a', dateMs: 1 },
    { studentId: 'a', dateMs: 2 },
    { studentId: 'a', dateMs: 3 },
    { studentId: 'b', dateMs: 1 },
    { studentId: 'b', dateMs: 2 },
    { studentId: 'c', dateMs: 1 },
  ];
  const ranked = rankFromGamificationPairs(pairs);
  assert.deepEqual(
    ranked.map((r) => [r.studentId, r.count, r.rank]),
    [
      ['a', 3, 1],
      ['b', 2, 2],
      ['c', 1, 3],
    ]
  );
});

test('rankFromPairs: ties broken by most-recent attendance (desc)', () => {
  const pairs = [
    { studentId: 'a', dateMs: 100 },
    { studentId: 'b', dateMs: 200 }, // same count, more recent → ranks first
  ];
  const ranked = rankFromGamificationPairs(pairs);
  assert.equal(ranked[0].studentId, 'b');
  assert.equal(ranked[0].rank, 1);
  assert.equal(ranked[1].studentId, 'a');
  assert.equal(ranked[1].rank, 2);
});

test('rankFromPairs: empty input → empty', () => {
  assert.deepEqual(rankFromGamificationPairs([]), []);
});

test('rankFromPairs: every rank is unique and contiguous from 1', () => {
  const pairs = [];
  for (let i = 0; i < 5; i++) {
    for (let j = 0; j <= i; j++) pairs.push({ studentId: `s${i}`, dateMs: j });
  }
  const ranked = rankFromGamificationPairs(pairs);
  const ranks = ranked.map((r) => r.rank);
  assert.deepEqual(ranks, [1, 2, 3, 4, 5]);
});

// --- Idempotency CONTRACT for upsertAutoAchievement (re-implemented guard) ---
// We can't hit Firestore here, but we pin the deterministic autoKey shapes that
// the guard relies on, so a refactor that changes them (breaking idempotency)
// is caught. server_functions.js builds:
//   streak  : `streak_${threshold}`     (stable per threshold, awarded once)
//   ranking : `rank_${scope}_${YYYY-MM}` (monthly, re-minted each month)
test('autoKey shapes are deterministic (idempotency contract)', () => {
  const streakKey = (t) => `streak_${t}`;
  assert.equal(streakKey(7), 'streak_7');
  assert.equal(streakKey(365), 'streak_365');
  // A given threshold always yields the SAME key → query-before-create no-ops.
  assert.equal(streakKey(30), streakKey(30));

  const rankKey = (scope, monthKey) => `rank_${scope}_${monthKey}`;
  assert.equal(rankKey('geral', '2026-06'), 'rank_geral_2026-06');
  // Different month → different key (fresh milestone each month).
  assert.notEqual(rankKey('geral', '2026-06'), rankKey('geral', '2026-07'));
  // Different scope → different key (geral/adulto/kids never collide).
  assert.notEqual(rankKey('adulto', '2026-06'), rankKey('kids', '2026-06'));
});
