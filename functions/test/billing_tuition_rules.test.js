'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  billingDateAtStartOfDay,
  clampDueDay,
  findConflictingStudentIds,
  isMembershipEligibleForMonth,
} = require('../billing_tuition_rules');

test('membership created on the due date is eligible', () => {
  assert.equal(isMembershipEligibleForMonth({
    planCreatedAt: '2026-08-01T12:00:00Z',
    studentAddedAt: '2026-08-10T23:30:00Z', // 20:30 in Sao Paulo
    referenceYear: 2026,
    referenceMonth: 8,
    dueDay: 10,
  }), true);
});

test('plan or membership created after the due date is deferred', () => {
  assert.equal(isMembershipEligibleForMonth({
    planCreatedAt: '2026-08-11T03:01:00Z', // 00:01 on Aug 11 in Sao Paulo
    referenceYear: 2026,
    referenceMonth: 8,
    dueDay: 10,
  }), false);
  assert.equal(isMembershipEligibleForMonth({
    planCreatedAt: '2026-07-01T12:00:00Z',
    studentAddedAt: '2026-08-12T12:00:00Z',
    referenceYear: 2026,
    referenceMonth: 8,
    dueDay: 10,
  }), false);
});

test('legacy timestamps stay eligible and due days are clamped', () => {
  assert.equal(isMembershipEligibleForMonth({
    referenceYear: 2026,
    referenceMonth: 2,
    dueDay: 31,
  }), true);
  assert.equal(clampDueDay(2026, 2, 31), 28);
});

test('billing due date is midnight in Sao Paulo, not midnight UTC', () => {
  assert.equal(
    billingDateAtStartOfDay(2026, 8, 10).toISOString(),
    '2026-08-10T03:00:00.000Z'
  );
});

test('students eligible in more than one plan are reported as conflicts', () => {
  const conflicts = findConflictingStudentIds([
    {studentId: 'a', planId: 'adult'},
    {studentId: 'a', planId: 'family'},
    {studentId: 'b', planId: 'kids'},
    {studentId: 'b', planId: 'kids'},
  ]);
  assert.deepEqual([...conflicts], ['a']);
});

test('source canary: auto tuition fails closed across plans and cancelled charges', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('async function generateAcademyTuitions(');
  const end = source.indexOf('exports.generateAcademyTuitions', start);
  const generator = source.slice(start, end);

  assert.match(generator, /findConflictingStudentIds\(monthlyCandidates\)/);
  assert.match(generator, /conflictingStudentIds\.has\(studentId\)/);
  assert.match(generator, /c\.studentId === studentId && c\.type === 'monthly_tuition'/);
  assert.match(generator, /isMembershipEligibleForMonth\(/);
  assert.doesNotMatch(generator, /if \(d\.status === 'cancelled'\) continue/);
});

test('source canary: manual tuition uses the same transactional guard', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('exports.createFinancialCharge = onCall');
  const end = source.indexOf('exports.updateFinancialTerms', start);
  const createCharge = source.slice(start, end);
  const rules = fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'firestore.rules'),
    'utf8'
  );

  assert.match(createCharge, /createTuitionWithGuard\(/);
  assert.match(createCharge, /existingTuition/);
  assert.match(createCharge, /isMembershipEligibleForMonth\(/);
  assert.match(createCharge, /memberships\.length > 1/);
  assert.match(
    rules,
    /request\.resource\.data\.type in \['avulsa', 'private_lesson'\]/
  );
});
