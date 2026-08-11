'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const {
  ManualPixConfirmationDecision,
  classifyManualPixConfirmation,
  classifyMercadoPagoCancellation,
} = require('../manual_pix_confirmation');

test('only pending and overdue charges can be manually confirmed', () => {
  for (const status of ['pending', 'overdue']) {
    assert.equal(
      classifyManualPixConfirmation({ status }),
      ManualPixConfirmationDecision.CONFIRM
    );
  }
  for (const status of ['cancelled', 'refunded', 'chargeback', 'unexpected']) {
    assert.equal(
      classifyManualPixConfirmation({ status }),
      ManualPixConfirmationDecision.INVALID_STATUS
    );
  }
});

test('an existing audited manual PIX is idempotent', () => {
  assert.equal(classifyManualPixConfirmation({
    status: 'paid',
    method: 'pix',
    paymentGateway: 'manual',
    manualPaymentAudit: { type: 'personal_pix' },
  }), ManualPixConfirmationDecision.ALREADY_CONFIRMED);
});

test('a payment settled by another method cannot be overwritten', () => {
  for (const financial of [
    { status: 'paid', method: 'cash', paymentGateway: 'manual' },
    { status: 'paid', method: 'pix', paymentGateway: 'mercadopago' },
    { status: 'paid', method: 'pix', paymentGateway: 'manual' },
  ]) {
    assert.equal(
      classifyManualPixConfirmation(financial),
      ManualPixConfirmationDecision.PAID_BY_OTHER_METHOD
    );
  }
});

test('Mercado Pago cancellation fails closed except for non-payable states', () => {
  for (const result of [
    { cancelled: true, status: 'cancelled' },
    { cancelled: false, status: 'rejected' },
    { cancelled: false, status: 'refunded' },
    { cancelled: false, status: 'charged_back' },
  ]) {
    assert.equal(classifyMercadoPagoCancellation(result).safe, true);
  }

  for (const result of [
    { cancelled: false, status: 'approved', alreadyApproved: true },
    { cancelled: false, status: 'pending' },
    { cancelled: false, status: 'in_process' },
    { cancelled: false, status: 'error' },
    null,
  ]) {
    assert.equal(classifyMercadoPagoCancellation(result).safe, false);
  }
});

test('server callable is admin-only and writes an immutable audit record', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('exports.confirmManualPixPayment');
  assert.ok(start > 0, 'confirmManualPixPayment callable present');
  const end = source.indexOf('\n});', start);
  assert.ok(end > start, 'callable body delimited');
  const body = source.slice(start, end);

  assert.ok(body.includes('requireAdminOf(request, academyId)'), 'admin gate present');
  assert.ok(body.includes('manualPaymentAudit'), 'audit snapshot written to financial');
  assert.ok(body.includes('paymentAuditLogs'), 'immutable audit collection written');
  assert.ok(body.includes("paymentGateway: 'manual'"), 'manual gateway recorded');
  assert.ok(body.includes("method: 'pix'"), 'PIX method recorded');
  assert.ok(
    body.includes('verifiedCompetingPaymentIds') &&
      body.includes('liveCompetingPaymentIds'),
    'a competing payment minted during the race is rejected'
  );
  assert.ok(!body.includes('pixKey'), 'personal PIX key is never copied into audit');
});
