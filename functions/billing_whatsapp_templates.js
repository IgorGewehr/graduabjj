'use strict';

const { BillingPaymentMode } = require('./billing_payment_resolver');

const MP_TICKET_PREFIX = 'https://www.mercadopago.com.br/payments/';

const stageTemplateBase = Object.freeze({
  'D+0': 'cobranca_d0',
  'D+1': 'cobranca_d1',
  'D+3': 'cobranca_d3',
  'D+7': 'cobranca_d7',
  'D+15': 'cobranca_d15',
  'D+30': 'cobranca_d30',
});

const oneTimeChargeTypes = new Set([
  'avulsa',
  'private_lesson',
  // Legacy financial documents may still use these more specific values.
  'uniform',
  'seminar',
  'graduation',
  'competition',
  'other',
]);

function isOneTimeChargeType(chargeType) {
  return oneTimeChargeTypes.has(String(chargeType || '').trim());
}

function oneTimeTemplateBase(stage) {
  if (stage === 'CREATED' || stage === 'UPCOMING' || stage === 'D+0' ||
      stage === 'due-0' || /^due-\d+$/.test(String(stage || ''))) {
    return 'cobranca_avulsa_aberta';
  }
  if (['D+1', 'D+3', 'D+7', 'D+15', 'D+30'].includes(stage)) {
    return 'cobranca_avulsa_pendente';
  }
  return null;
}

function normalizeTemplateStage(stage) {
  if (stage === 'due-0') return 'D+0';
  return Object.hasOwn(stageTemplateBase, stage) ? stage : null;
}

function templateNameFor(stage, paymentMode, chargeType = 'monthly_tuition') {
  const base = isOneTimeChargeType(chargeType)
    ? oneTimeTemplateBase(stage)
    : stageTemplateBase[normalizeTemplateStage(stage)];
  if (!base) return null;
  switch (paymentMode) {
    case BillingPaymentMode.MERCADO_PAGO:
      return base;
    case BillingPaymentMode.MANUAL_PIX:
      return `${base}_pix_manual`;
    case BillingPaymentMode.NONE:
    default:
      return `${base}_sempix`;
  }
}

/**
 * The Meta template already owns the fixed URL prefix:
 *   https://www.mercadopago.com.br/payments/{{1}}
 *
 * Therefore the API parameter must contain only what comes after
 * `/payments/`. Keeping this normalization at the producer boundary prevents
 * an older notification-server from duplicating the prefix.
 */
function mercadoPagoButtonUrlParam(ticketUrl) {
  const value = String(ticketUrl || '').trim();
  if (!value) return '';

  if (value.startsWith(MP_TICKET_PREFIX)) {
    return value.slice(MP_TICKET_PREFIX.length);
  }

  if (/^\d+\/ticket\?[A-Za-z0-9_~.!$&'()*+,;=:@%/?-]+$/.test(value)) {
    return value;
  }

  return '';
}

/**
 * Builds the exact payload accepted by /api/send-whatsapp-template.
 * Monthly tuition keeps the D+0..D+30 matrix. One-time charges use the
 * approved open/pending families, including creation and due-soon stages.
 */
function buildBillingTemplatePayload({
  stage,
  paymentInstruction = { mode: BillingPaymentMode.NONE },
  studentName,
  academyName,
  amountFormatted,
  dueDateFormatted,
  chargeType = 'monthly_tuition',
  description,
} = {}) {
  let mode = paymentInstruction.mode;
  if (mode === BillingPaymentMode.MERCADO_PAGO &&
      !String(paymentInstruction.pixCode || '').trim()) {
    mode = BillingPaymentMode.NONE;
  }
  if (mode === BillingPaymentMode.MANUAL_PIX &&
      !String(paymentInstruction.pixKey || '').trim()) {
    mode = BillingPaymentMode.NONE;
  }

  const templateName = templateNameFor(stage, mode, chargeType);
  if (!templateName) return null;

  const variables = [
    String(studentName || ''),
    String(academyName || ''),
    String(amountFormatted || ''),
    String(dueDateFormatted || ''),
  ];

  if (isOneTimeChargeType(chargeType)) {
    variables.push(String(description || 'Cobrança avulsa').trim());
  }

  if (mode === BillingPaymentMode.MERCADO_PAGO) {
    variables.push(String(paymentInstruction.pixCode).trim());
  } else if (mode === BillingPaymentMode.MANUAL_PIX) {
    variables.push(String(paymentInstruction.pixKey).trim());
  }

  const payload = { templateName, variables, paymentMode: mode };
  if (mode === BillingPaymentMode.MERCADO_PAGO) {
    const buttonUrl = mercadoPagoButtonUrlParam(paymentInstruction.ticketUrl);
    if (buttonUrl) payload.buttonUrl = buttonUrl;
  }
  return payload;
}

module.exports = {
  buildBillingTemplatePayload,
  isOneTimeChargeType,
  mercadoPagoButtonUrlParam,
  normalizeTemplateStage,
  oneTimeTemplateBase,
  templateNameFor,
};
