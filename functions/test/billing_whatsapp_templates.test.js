'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { BillingPaymentMode } = require('../billing_payment_resolver');
const {
  buildBillingTemplatePayload,
  isUpcomingMonthlyStage,
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

test('due today (due-0) still maps through the D+0 family, not cobranca_avencer', () => {
  assert.equal(normalizeTemplateStage('due-0'), 'D+0');
  assert.equal(isUpcomingMonthlyStage('due-0'), false);
  assert.equal(
    templateNameFor('due-0', BillingPaymentMode.NONE),
    'cobranca_d0_sempix'
  );
});

test('stray/unrecognized stages have no template (CREATED, non-due-N)', () => {
  assert.equal(normalizeTemplateStage('CREATED'), null);
  assert.equal(isUpcomingMonthlyStage('CREATED'), false);
  assert.equal(templateNameFor('CREATED', BillingPaymentMode.NONE), null);
});

// Regressão real (Lobisomens Jiu Jitsu, 03/set/2026): o modelo Meta
// "cobranca_avencer" (aprovado, categoria Marketing) existia e tinha
// conteúdo certo pra avisar ANTES do vencimento, mas nunca foi conectado —
// due-N (N>0) sempre batia em "template_unavailable" e nenhum aviso saía.
// 'UPCOMING' é o literal que o envio manual (sendBillingReminder) usa pra
// mesma situação — os dois precisam resolver pro mesmo template.
test('due-soon (due-N and the manual-send literal UPCOMING) maps to cobranca_avencer, all three payment modes', () => {
  for (const stage of ['due-1', 'due-3', 'due-7', 'UPCOMING']) {
    assert.equal(isUpcomingMonthlyStage(stage), true);
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.MERCADO_PAGO),
      'cobranca_avencer'
    );
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.MANUAL_PIX),
      'cobranca_avencer_pix_manual'
    );
    assert.equal(
      templateNameFor(stage, BillingPaymentMode.NONE),
      'cobranca_avencer_sempix'
    );
  }
});

// Ordem confirmada na definição BRUTA do modelo (não a prévia) direto no
// Meta Business Manager, 03/set/2026:
//   "Olá, {{1}}! Faltam {{5}} dia(s) para o vencimento da sua mensalidade
//   de {{3}} da {{2}}, com vencimento em {{4}}. ... {{6}}" (PIX, quando tem)
// {{1}}=nome {{2}}=academia {{3}}=valor {{4}}=vencimento {{5}}=dias {{6}}=pix
test('cobranca_avencer (Mercado Pago): variables in {{1}}..{{6}} order, dias before PIX', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    stage: 'due-3',
    daysUntilDue: 3,
    paymentInstruction: {
      mode: BillingPaymentMode.MERCADO_PAGO,
      pixCode: '000201-MP',
      ticketUrl: 'https://www.mercadopago.com.br/payments/1/ticket?hash=x',
    },
  });

  assert.deepEqual(payload, {
    templateName: 'cobranca_avencer',
    variables: [
      'Ana',            // {{1}} nome
      'Academia Centro', // {{2}} academia
      'R$ 150,00',      // {{3}} valor
      '10/08/2026',     // {{4}} vencimento
      '3',              // {{5}} dias
      '000201-MP',      // {{6}} pix
    ],
    paymentMode: BillingPaymentMode.MERCADO_PAGO,
    buttonUrl: '1/ticket?hash=x',
  });
});

test('cobranca_avencer_pix_manual: dias at {{5}}, chave PIX manual at {{6}}', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    stage: 'due-7',
    daysUntilDue: 7,
    paymentInstruction: {
      mode: BillingPaymentMode.MANUAL_PIX,
      pixKey: 'financeiro@academiaexemplo.com',
    },
  });

  assert.equal(payload.templateName, 'cobranca_avencer_pix_manual');
  assert.deepEqual(payload.variables, [
    'Ana',
    'Academia Centro',
    'R$ 150,00',
    '10/08/2026',
    '7',
    'financeiro@academiaexemplo.com',
  ]);
});

test('cobranca_avencer_sempix: five variables, dias last, no PIX slot', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    stage: 'due-1',
    daysUntilDue: 1,
    paymentInstruction: { mode: BillingPaymentMode.NONE },
  });

  assert.equal(payload.templateName, 'cobranca_avencer_sempix');
  assert.deepEqual(payload.variables, [
    'Ana',
    'Academia Centro',
    'R$ 150,00',
    '10/08/2026',
    '1',
  ]);
});

// Guarda de regressão: D+1..D+30 (atrasado) não ganham a variável de dias —
// só cobranca_avencer (a-vencer) tem esse quinto slot.
test('overdue stages (D+1..D+30) are unaffected: still four variables, no dias', () => {
  const payload = buildBillingTemplatePayload({
    ...common,
    stage: 'D+7',
    daysUntilDue: 999, // deve ser ignorado — só isUpcomingMonthlyStage usa isso
    paymentInstruction: { mode: BillingPaymentMode.NONE },
  });

  assert.equal(payload.templateName, 'cobranca_d7_sempix');
  assert.deepEqual(payload.variables, [
    'Ana',
    'Academia Centro',
    'R$ 150,00',
    '10/08/2026',
  ]);
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

test('SOURCE SYNC: manual sendBillingReminder computes real days-until-due, not the overdue-clamped-to-0 value', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('exports.sendBillingReminder = onCall');
  const end = source.indexOf('exports.', start + 1);
  const fn = source.slice(start, end);

  // daysOverdueBR clampa futuro pra 0 — sem esse cálculo à parte, o envio
  // manual de um lembrete a-vencer mandava {{5}} (dias) vazio pro cliente,
  // mesmo com o template certo conectado (auditoria 03/set/2026).
  assert.match(fn, /const isUpcoming = dueDay > today;/);
  assert.match(fn, /const whatsappDaysArg = isUpcoming/);
  assert.match(
    fn,
    /sendBillingReminderWhatsApp\(\s*academyId,\s*academyName,\s*settings,\s*financial,\s*stage,\s*whatsappDaysArg,/
  );
});

test('SOURCE SYNC: sendBillingReminderWhatsApp forwards daysUntilDue to the template builder', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );
  const start = source.indexOf('async function sendBillingReminderWhatsApp(');
  const end = source.indexOf(
    '\nfunction isValidBillingEmail',
    start
  );
  const fn = source.slice(start, end === -1 ? undefined : end);

  // Sem isso, cobranca_avencer manda {{5}} vazio pra todo mundo mesmo depois
  // do fix — o wiring do template precisa vir junto com o dado que ele lê.
  assert.match(fn, /daysUntilDue:\s*daysOverdue < 0 \? -daysOverdue : null/);
});
