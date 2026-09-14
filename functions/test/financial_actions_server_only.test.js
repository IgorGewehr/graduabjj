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

test('deleting a charge invalidates pending provider payments before removal', () => {
  const deleteStart = serverSource.indexOf(
    'exports.deleteFinancialCharge = onCall('
  );
  const deleteEnd = serverSource.indexOf(
    '/** Parses `${academyId}:fin:${id}`',
    deleteStart
  );
  const deleteSource = serverSource.slice(deleteStart, deleteEnd);

  assert.match(deleteSource, /secrets:\s*MP_MKT_SECRETS/);
  assert.match(deleteSource, /cancelCompetingPaymentsFailClosed\(/);
  assert.match(deleteSource, /competingProviderPaymentIds\(financial\)/);
  assert.match(deleteSource, /verifiedIds\.has\(id\)/);
  assert.match(deleteSource, /invalidatePublicCheckoutAttemptBestEffort\(/);
  assert.match(deleteSource, /tx\.delete\(financialRef\)/);
});

test('Mercado Pago cancellation uses the documented PUT endpoint', () => {
  const cancelHelperStart = serverSource.indexOf(
    'async function mpCancelPixPayment('
  );
  const cancelHelperEnd = serverSource.indexOf(
    '/**\n * Auditoria MP',
    cancelHelperStart
  );
  const cancelHelperSource = serverSource.slice(
    cancelHelperStart,
    cancelHelperEnd
  );

  assert.match(
    cancelHelperSource,
    /mpRequest\('PUT', `\/v1\/payments\/\$\{paymentId\}`/
  );
  assert.doesNotMatch(
    cancelHelperSource,
    /mpRequest\('POST', `\/v1\/payments\/\$\{paymentId\}`/
  );
  assert.match(cancelHelperSource, /body:\s*\{ status: 'cancelled' \}/);
  assert.match(cancelHelperSource, /idempotencyKey:\s*cancellationKey/);
  assert.match(cancelHelperSource, /'authorized'/);
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

test('academy ownership prefers ownerId with legacy adminUserId fallback', () => {
  assert.match(
    serverSource,
    /function getAcademyOwnerUid\(academy\) \{[^]*?academy\?\.ownerId \|\| academy\?\.adminUserId \|\| null;/
  );
  assert.match(
    serverSource,
    /exports\.scheduledOverdueCheck\s*=[^]*?const academyOwnerUid = getAcademyOwnerUid\(academy\);[^]*?if \(!academyOwnerUid\)/
  );
  assert.doesNotMatch(serverSource, /if \(!academy\.adminUserId\)/);
  assert.doesNotMatch(
    serverSource,
    /if \(academy\.adminUserId !== context\.auth\.uid\)/
  );
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

test('Mercado Pago reminder fallback distinguishes missing CPF and email', () => {
  assert.match(
    serverSource,
    /throw new Error\('missing_valid_pix_payer_cpf'\)/
  );
  assert.match(
    serverSource,
    /throw new Error\('missing_valid_pix_payer_email'\)/
  );
  assert.match(serverSource, /return 'missing_payer_cpf'/);
  assert.match(serverSource, /return 'missing_payer_email'/);
});

test('scheduled billing retries WhatsApp independently without duplicating app alerts', () => {
  const whatsappStart = serverSource.indexOf(
    'async function sendBillingReminderWhatsApp('
  );
  const whatsappEnd = serverSource.indexOf(
    'function isValidBillingEmail(',
    whatsappStart
  );
  const whatsappSource = serverSource.slice(whatsappStart, whatsappEnd);

  const overdueStart = serverSource.indexOf(
    'exports.scheduledOverdueCheck = functions'
  );
  const dueSoonStart = serverSource.indexOf(
    'exports.scheduledDueSoonReminder = functions'
  );
  const dueSoonEnd = serverSource.indexOf(
    'exports.scheduledMonthlyTuitionGeneration',
    dueSoonStart
  );
  const overdueSource = serverSource.slice(overdueStart, dueSoonStart);
  const dueSoonSource = serverSource.slice(dueSoonStart, dueSoonEnd);

  assert.match(whatsappSource, /financial\.lastWhatsAppReminderStage === stage/);
  assert.doesNotMatch(whatsappSource, /financial\.lastReminderStage === stage/);
  assert.match(whatsappSource, /lastWhatsAppAttemptResult/);
  assert.match(whatsappSource, /lastWhatsAppReminderStage = stage/);

  assert.match(overdueSource, /timeoutSeconds:\s*540/);
  assert.match(overdueSource, /const appStageCovered =/);
  assert.match(overdueSource, /migrateLegacyWhatsAppReminderStage\(/);
  assert.doesNotMatch(
    overdueSource,
    /if \(financial\.lastReminderStage === stage\) continue/
  );

  assert.match(dueSoonSource, /timeoutSeconds:\s*540/);
  assert.match(dueSoonSource, /const appDueStageCovered =/);
  assert.match(dueSoonSource, /migrateLegacyWhatsAppReminderStage\(/);
  assert.doesNotMatch(
    dueSoonSource,
    /if \(financial\.lastDueSoonStage === dueStage\) continue/
  );
});
