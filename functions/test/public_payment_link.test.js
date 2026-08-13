'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  CHECKOUT_TTL_MS,
  decryptPublicToken,
  encryptPublicToken,
  generatePublicToken,
  hashPublicToken,
  isReusableAttempt,
  isValidPublicToken,
  isValidRequestId,
  publicAvailableMethods,
  publicAttemptStatusFromProvider,
  publicChargeStatus,
} = require('../public_payment_link');

const secret = 'test-secret-with-at-least-thirty-two-characters';

test('public token is opaque, 32-byte base64url and hash-addressed', () => {
  const token = generatePublicToken();
  assert.equal(isValidPublicToken(token), true);
  assert.equal(Buffer.from(token, 'base64url').length, 32);
  assert.match(hashPublicToken(token), /^[a-f0-9]{64}$/);
});

test('stored token ciphertext round-trips and rejects tampering', () => {
  const token = generatePublicToken();
  const encrypted = encryptPublicToken(token, secret);
  assert.equal(decryptPublicToken(encrypted, secret), token);
  assert.notEqual(encrypted.tokenCiphertext, token);
  assert.throws(() => decryptPublicToken({
    ...encrypted,
    tokenTag: Buffer.alloc(16).toString('base64'),
  }, secret));
});

test('public charge exposes only open, paid, cancelled or unavailable states', () => {
  assert.equal(publicChargeStatus({ status: 'pending' }), 'open');
  assert.equal(publicChargeStatus({ status: 'overdue' }), 'open');
  assert.equal(publicChargeStatus({ status: 'paid' }), 'paid');
  assert.equal(publicChargeStatus({ status: 'cancelled' }), 'cancelled');
  assert.equal(publicChargeStatus({ status: 'pending', publicPaymentEnabled: false }), 'unavailable');
});

test('public methods honor financial policy and Mercado Pago connection', () => {
  const academy = {
    mpConnected: true,
    mpNeedsReauth: false,
    publicPaymentLinksEnabled: true,
  };
  assert.deepEqual(
    publicAvailableMethods({ status: 'pending', paymentMethodPolicy: 'both' }, academy),
    ['pix', 'credit_card']
  );
  assert.deepEqual(
    publicAvailableMethods({ status: 'pending', paymentMethodPolicy: 'pix_only' }, academy),
    ['pix']
  );
  assert.deepEqual(
    publicAvailableMethods({ status: 'pending', paymentMethodPolicy: 'card_only' }, academy),
    []
  );
  assert.deepEqual(
    publicAvailableMethods({ status: 'pending' }, { mpConnected: false }),
    []
  );
  assert.deepEqual(
    publicAvailableMethods(
      { status: 'pending' },
      { mpConnected: true, publicPaymentLinksEnabled: false }
    ),
    []
  );
});

test('checkout reuse requires same link, version, amount, mode and live expiry', () => {
  const nowMs = Date.now();
  const attempt = {
    status: 'ready',
    mode: 'checkout_pro',
    providerRedirectUrl: 'https://www.mercadopago.com.br/checkout',
    publicLinkHash: 'hash',
    financialVersion: 3,
    amount: 120,
    expiresAtMs: nowMs + CHECKOUT_TTL_MS,
  };
  const expected = {
    publicLinkHash: 'hash',
    financialVersion: 3,
    amount: 120,
    mode: 'checkout_pro',
    nowMs,
  };
  assert.equal(isReusableAttempt(attempt, expected), true);
  assert.equal(isReusableAttempt({ ...attempt, financialVersion: 2 }, expected), false);
  assert.equal(isReusableAttempt({ ...attempt, expiresAtMs: nowMs }, expected), false);
});

test('request ids are UUID v4 only', () => {
  assert.equal(isValidRequestId('f47ac10b-58cc-4372-a567-0e02b2c3d479'), true);
  assert.equal(isValidRequestId('f47ac10b-58cc-1372-a567-0e02b2c3d479'), false);
});

test('provider statuses map to an attempt-only lifecycle without cancelling debt', () => {
  assert.equal(publicAttemptStatusFromProvider('approved'), 'paid');
  assert.equal(publicAttemptStatusFromProvider('pending'), 'pending');
  assert.equal(publicAttemptStatusFromProvider('cancelled'), 'cancelled');
  assert.equal(publicAttemptStatusFromProvider('rejected'), 'failed');
  assert.equal(publicAttemptStatusFromProvider('charged_back'), 'reversed');
  assert.equal(publicAttemptStatusFromProvider('unknown'), null);
});

test('source canary: reminders create stable links, never Mercado Pago payments', () => {
  const root = path.resolve(__dirname, '..');
  const server = fs.readFileSync(path.join(root, 'server_functions.js'), 'utf8');
  const reminderStart = server.indexOf('async function sendBillingReminderWhatsApp(');
  const reminderEnd = server.indexOf('function isValidBillingEmail(', reminderStart);
  const reminder = server.slice(reminderStart, reminderEnd);
  assert.match(server, /exports\.resolvePublicCharge\s*=\s*onRequest/);
  assert.match(server, /exports\.startPublicCheckout\s*=\s*onRequest/);
  assert.match(server, /exports\.scheduledPublicPaymentAttemptReconcile\s*=\s*onSchedule/);
  assert.match(server, /projectPublicPaymentAttempt\(acad, payment\)/);
  assert.match(reminder, /getOrCreatePublicPaymentLink\(/);
  assert.doesNotMatch(reminder, /createMpPix\(|createMpPixPayment|checkout\/preferences/);
  assert.doesNotMatch(server, /function generateReminderPix\(/);
});

test('public site starts checkout only from the pay button handler', () => {
  const site = fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'site', 'pay', 'pay.js'),
    'utf8'
  );
  assert.match(site, /elements\.pay\.addEventListener\('click', startCheckout\)/);
  const resolveStart = site.indexOf('async function resolveCharge()');
  const resolveEnd = site.indexOf('function safeMercadoPagoUrl', resolveStart);
  assert.doesNotMatch(site.slice(resolveStart, resolveEnd), /public-pay\/start/);
});
