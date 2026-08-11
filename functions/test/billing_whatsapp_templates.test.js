'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { BillingPaymentMode } = require('../billing_payment_resolver');
const {
  buildBillingTemplatePayload,
  normalizeTemplateStage,
  templateNameFor,
} = require('../billing_whatsapp_templates');

const common = {
  stage: 'D+7',
  studentName: 'Ana',
  academyName: 'Academia Centro',
  amountFormatted: 'R$ 150,00',
  dueDateFormatted: '10/08/2026',
};

test('maps every approved stage to its three payment variants', () => {
  for (const [stage, suffix] of [
    ['D+0', 'd0'],
    ['D+1', 'd1'],
    ['D+3', 'd3'],
    ['D+7', 'd7'],
    ['D+15', 'd15'],
    ['D+30', 'd30'],
  ]) {
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.MERCADO_PAGO),
      `cobranca_${suffix}`
    );
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.MANUAL_PIX),
      `cobranca_${suffix}_pix_manual`
    );
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.NONE),
      `cobranca_${suffix}_sempix`
    );
  }
});

test('Mercado Pago sends code as variable 5 and checkout as button', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    paymentInstruction: {
      mode: BillingPaymentMode.MERCADO_PAGO,
      pixCode: '000201-MP',
      ticketUrl: 'https://mp.example/checkout',
    },
  });

  assert.deepEqual(payload, {
    templateName: 'cobranca_d7',
    variables: [
      'Ana',
      'Academia Centro',
      'R$ 150,00',
      '10/08/2026',
      '000201-MP',
    ],
    paymentMode: BillingPaymentMode.MERCADO_PAGO,
    buttonUrl: 'https://mp.example/checkout',
  });
});

test('personal PIX selects manual template without a button', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    paymentInstruction: {
      mode: BillingPaymentMode.MANUAL_PIX,
      pixKey: 'professor@academia.com',
    },
  });

  assert.equal(payload.templateName, 'cobranca_d7_pix_manual');
  assert.deepEqual(payload.variables.slice(-1), ['professor@academia.com']);
  assert.equal(payload.buttonUrl, undefined);
});

test('none selects four-variable template without payment data', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    paymentInstruction: { mode: BillingPaymentMode.NONE },
  });

  assert.equal(payload.templateName, 'cobranca_d7_sempix');
  assert.equal(payload.variables.length, 4);
  assert.equal(payload.buttonUrl, undefined);
});

test('missing payment data degrades to the sempix template', () => {
  const mp = buildBillingTemplatePayload({
    ...common,
    paymentInstruction: { mode: BillingPaymentMode.MERCADO_PAGO, pixCode: '' },
  });
  const manual = buildBillingTemplatePayload({
    ...common,
    paymentInstruction: { mode: BillingPaymentMode.MANUAL_PIX, pixKey: '' },
  });

  assert.equal(mp.templateName, 'cobranca_d7_sempix');
  assert.equal(manual.templateName, 'cobranca_d7_sempix');
});

test('only due today maps from due-soon stages to an approved template', () => {
  assert.equal(normalizeTemplateStage('due-0'), 'D+0');
  assert.equal(normalizeTemplateStage('due-1'), null);
  assert.equal(normalizeTemplateStage('CREATED'), null);
  assert.equal(templateNameFor('UPCOMING', BillingPaymentMode.NONE), null);
});

test('SOURCE SYNC: automatic reminders use Meta templates and the resolver', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );

  assert.match(source, /send-whatsapp-template/);
  assert.match(source, /resolveBillingPaymentInstruction\(\{/);
  assert.match(source, /buildBillingTemplatePayload\(\{/);
  assert.match(source, /type: 'billing_reminder'/);
  assert.doesNotMatch(source, /settings\.messageTemplates\?\.whatsapp/);
});
