'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const functionsRoot = path.resolve(__dirname, '..');
const repositoryRoot = path.resolve(functionsRoot, '..');
const serverSource = fs.readFileSync(
  path.join(functionsRoot, 'server_functions.js'),
  'utf8'
);
const paymentServiceSource = fs.readFileSync(
  path.join(repositoryRoot, 'lib', 'services', 'payment_service.dart'),
  'utf8'
);
const financialScreenSource = fs.readFileSync(
  path.join(repositoryRoot, 'lib', 'screens', 'admin', 'financial_screen.dart'),
  'utf8'
);
const buildSource = fs.readFileSync(
  path.join(repositoryRoot, 'build.sh'),
  'utf8'
);

test('financial mutations are exported as authenticated backend actions', () => {
  for (const action of [
    'createFinancialCharge',
    'updateFinancialTerms',
    'markFinancialPaidManual',
    'cancelFinancialCharge',
    'reactivateFinancialCharge',
    'refreshOverdueFinancials',
    'deleteFinancialCharge',
  ]) {
    assert.match(serverSource, new RegExp(`exports\\.${action}\\s*=\\s*onCall`));
    assert.match(paymentServiceSource, new RegExp(`httpsCallable\\('${action}'\\)`));
  }
});

test('staff authorization supports legacy academy-scoped user roles', () => {
  assert.match(
    serverSource,
    /async function isAcademyStaff\(uid, academyId\) \{[^]*?getUserAcademyMembership\(uid, academyId\)[^]*?membership\.role === 'admin'[^]*?membership\.role === 'instructor'[^]*?\n\}/
  );
  assert.match(
    serverSource,
    /async function getUserAcademyMembership\(uid, academyId\) \{[^]*?collection\('users'\)\.doc\(uid\)\.get\(\)/
  );
});

test('opening Financeiro does not run overdue maintenance', () => {
  assert.doesNotMatch(financialScreenSource, /markOverduePayments\(/);
  assert.match(serverSource, /exports\.scheduledOverdueCheck\s*=/);
});

test('distributed build contains no notification credential defines', () => {
  assert.doesNotMatch(
    buildSource,
    /--dart-define=(?:WHATSAPP_API_KEY|EMAIL_API_KEY|NOTIFICATION_API_KEY)=/
  );
  assert.doesNotMatch(buildSource, /NOTIFICATION_INTERNAL_KEY\s*=/);
});

test('billing dispatch is server-side and preview no longer mints PIX', () => {
  const billingServiceSource = fs.readFileSync(
    path.join(repositoryRoot, 'lib', 'services', 'billing_reminder_service.dart'),
    'utf8'
  );
  const billingScreenSource = fs.readFileSync(
    path.join(repositoryRoot, 'lib', 'screens', 'admin', 'billing_reminders_screen.dart'),
    'utf8'
  );
  assert.match(serverSource, /exports\.sendBillingReminder\s*=\s*onCall/);
  assert.match(
    serverSource,
    /exports\.sendBillingReminder\s*=\s*onCall\(\s*\{[^]*?invoker:\s*'public'/
  );
  assert.match(
    serverSource,
    /const key = process\.env\.WHATSAPP_API_KEY \|\| process\.env\.NOTIFICATION_API_KEY;/
  );
  const dispatchStart = serverSource.indexOf(
    'exports.sendBillingReminder = onCall('
  );
  const dispatchHandler = serverSource.indexOf(
    'async (request) =>',
    dispatchStart
  );
  const dispatchOptions = serverSource.slice(dispatchStart, dispatchHandler);
  assert.doesNotMatch(dispatchOptions, /'NOTIFICATION_API_KEY'/);
  assert.match(billingServiceSource, /httpsCallable\('sendBillingReminder'\)/);
  assert.doesNotMatch(billingScreenSource, /resolvePaymentInstruction\(/);
  assert.match(
    serverSource,
    /payerFallbackUid:\s*request\.auth\.uid/
  );
  assert.match(
    serverSource,
    /admin\.auth\(\)\.getUser\(payerFallbackUid\)/
  );
});
