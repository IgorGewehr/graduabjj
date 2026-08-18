'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { BillingPaymentMode } = require('../billing_payment_resolver');
const {
  buildBillingTemplatePayload,
  mercadoPagoButtonUrlParam,
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
      ticketUrl: 'https://www.mercadopago.com.br/payments/172335605249/ticket?caller_id=1629589953&hash=abc-123',
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
    buttonUrl: '172335605249/ticket?caller_id=1629589953&hash=abc-123',
  });
});

test('Mercado Pago button keeps only the dynamic suffix expected by Meta', () => {
  assert.equal(
    mercadoPagoButtonUrlParam(
      'https://www.mercadopago.com.br/payments/174298148560/ticket?caller_id=1629589953&hash=f8cffe44-01df-4211-aa96-ac565c2636a9'
    ),
    '174298148560/ticket?caller_id=1629589953&hash=f8cffe44-01df-4211-aa96-ac565c2636a9'
  );
  assert.equal(
    mercadoPagoButtonUrlParam('174298148560/ticket?caller_id=1&hash=x'),
    '174298148560/ticket?caller_id=1&hash=x'
  );
  assert.equal(
    mercadoPagoButtonUrlParam('https://evil.example/payments/174298148560'),
    ''
  );
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

test('one-time charges use open and pending template families', () => {
  for (const type of ['avulsa', 'private_lesson']) {
    for (const stage of ['CREATED', 'UPCOMING', 'due-7', 'D+0']) {
      assert.equal(
        templateNameFor(stage, BillingPaymentMode.MERCADO_PAGO, type),
        'cobranca_avulsa_aberta'
      );
      assert.equal(
        templateNameFor(stage, BillingPaymentMode.MANUAL_PIX, type),
        'cobranca_avulsa_aberta_pix_manual'
      );
      assert.equal(
        templateNameFor(stage, BillingPaymentMode.NONE, type),
        'cobranca_avulsa_aberta_sempix'
      );
    }
    for (const stage of ['D+1', 'D+3', 'D+7', 'D+15', 'D+30']) {
      assert.equal(
        templateNameFor(stage, BillingPaymentMode.MERCADO_PAGO, type),
        'cobranca_avulsa_pendente'
      );
    }
  }
});

test('one-time Mercado Pago payload sends description as 5 and PIX as 6', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    stage: 'UPCOMING',
    chargeType: 'private_lesson',
    description: 'Aula particular — 20/08/2026',
    paymentInstruction: {
      mode: BillingPaymentMode.MERCADO_PAGO,
      pixCode: '000201-MP',
      ticketUrl: 'https://www.mercadopago.com.br/payments/1/ticket?hash=x',
    },
  });

  assert.deepEqual(payload, {
    templateName: 'cobranca_avulsa_aberta',
    variables: [
      'Ana',
      'Academia Centro',
      'R$ 150,00',
      '10/08/2026',
      'Aula particular — 20/08/2026',
      '000201-MP',
    ],
    paymentMode: BillingPaymentMode.MERCADO_PAGO,
    buttonUrl: '1/ticket?hash=x',
  });
});

test('one-time sempix payload retains description without payment variable', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    chargeType: 'avulsa',
    description: 'Taxa de matrícula',
    paymentInstruction: { mode: BillingPaymentMode.NONE },
  });

  assert.equal(payload.templateName, 'cobranca_avulsa_pendente_sempix');
  assert.deepEqual(payload.variables, [
    'Ana',
    'Academia Centro',
    'R$ 150,00',
    '10/08/2026',
    'Taxa de matrícula',
  ]);
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
