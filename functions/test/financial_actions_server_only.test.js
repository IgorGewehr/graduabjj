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
  assert.match(billingServiceSource, /httpsCallable\('sendBillingReminder'\)/);
  assert.doesNotMatch(billingScreenSource, /resolvePaymentInstruction\(/);
});
