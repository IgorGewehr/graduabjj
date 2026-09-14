'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  billingDateAtStartOfDay,
  clampDueDay,
  effectiveDueDay,
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

test('effectiveDueDay: customDueDay (Personalizado) wins over legacy tuitionDay', () => {
  // Caso real (Drakkar Academia, auditoria 01/set/2026): a UI mostrava
  // "Personalizado: dia 28", mas a geração automática usava dia 10 (o
  // default do model quando student.tuitionDay nunca foi setado
  // explicitamente). A cobrança sumia do vencimento combinado com a família.
  assert.equal(effectiveDueDay({
    customDueDay: 28,
    studentTuitionDay: 10,
    defaultDueDay: 5,
  }), 28);
});

test('effectiveDueDay: legacy tuitionDay is still the fallback when nothing is personalized', () => {
  // Auditoria 01/set/2026 achou 54 alunos reais, em 10 academias, com
  // tuitionDay divergindo do defaultDueDay do plano SEM customDueDay
  // configurado — não dá pra saber se foi intencional (o form de edição do
  // aluno também grava esse campo). Não pode virar regressão silenciosa.
  assert.equal(effectiveDueDay({
    customDueDay: undefined,
    studentTuitionDay: 19,
    defaultDueDay: 8,
  }), 19);
});

test('effectiveDueDay: falls back to the plan default when neither is set', () => {
  assert.equal(effectiveDueDay({
    customDueDay: undefined,
    studentTuitionDay: undefined,
    defaultDueDay: 10,
  }), 10);
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

test('source canary: auto tuition resolves due day through effectiveDueDay, not an inline tuitionDay-first ternary', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('async function generateAcademyTuitions(');
  const end = source.indexOf('exports.generateAcademyTuitions', start);
  const generator = source.slice(start, end);

  // Regressão real (Drakkar, 01/set/2026): a ordem antiga (tuitionDay antes
  // de customDueDays) atropelava o "Personalizado" configurado no plano.
  assert.match(generator, /effectiveDueDay\(\{/);
  assert.doesNotMatch(
    generator,
    /stu\.tuitionDay != null\s*\?\s*stu\.tuitionDay/
  );
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
  // Mesma regressão do canary de generateAcademyTuitions acima, mas no
  // caminho de cobrança manual: customDueDays precisa vencer tuitionDay.
  assert.match(createCharge, /effectiveDueDay\(\{/);
  assert.doesNotMatch(
    createCharge,
    /student\.tuitionDay != null\s*\?\s*student\.tuitionDay/
  );
  assert.match(
    rules,
    /request\.resource\.data\.type in \['avulsa', 'private_lesson'\]/
  );
});

test('source canary: one-off charges always receive their due-date month', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('exports.createFinancialCharge = onCall');
  const end = source.indexOf('exports.updateFinancialTerms', start);
  const createCharge = source.slice(start, end);

  assert.match(createCharge, /if \(type !== 'monthly_tuition'\)/);
  assert.match(
    createCharge,
    /referenceMonth = `\$\{dueParts\.year\}-\$\{String\(dueParts\.month\)\.padStart\(2, '0'\)\}`/
  );
});
