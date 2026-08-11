'use strict';

const { BillingPaymentMode } = require('./billing_payment_resolver');

const stageTemplateBase = Object.freeze({
  'D+0': 'cobranca_d0',
  'D+1': 'cobranca_d1',
  'D+3': 'cobranca_d3',
  'D+7': 'cobranca_d7',
  'D+15': 'cobranca_d15',
  'D+30': 'cobranca_d30',
});

function normalizeTemplateStage(stage) {
  if (stage === 'due-0') return 'D+0';
  return Object.hasOwn(stageTemplateBase, stage) ? stage : null;
}

function templateNameFor(stage, paymentMode) {
  const normalizedStage = normalizeTemplateStage(stage);
  if (!normalizedStage) return null;

  const base = stageTemplateBase[normalizedStage];
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
 * Builds the exact payload accepted by /api/send-whatsapp-template.
 * CREATED and due-soon stages above zero intentionally return null because no
 * approved Meta template exists for those message copies yet.
 */
function buildBillingTemplatePayload({
  stage,
  paymentInstruction = { mode: BillingPaymentMode.NONE },
  studentName,
  academyName,
  amountFormatted,
  dueDateFormatted,
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

  const templateName = templateNameFor(stage, mode);
  if (!templateName) return null;

  const variables = [
    String(studentName || ''),
    String(academyName || ''),
    String(amountFormatted || ''),
    String(dueDateFormatted || ''),
  ];

  if (mode === BillingPaymentMode.MERCADO_PAGO) {
    variables.push(String(paymentInstruction.pixCode).trim());
  } else if (mode === BillingPaymentMode.MANUAL_PIX) {
    variables.push(String(paymentInstruction.pixKey).trim());
  }

  const payload = { templateName, variables, paymentMode: mode };
  if (mode === BillingPaymentMode.MERCADO_PAGO) {
    const buttonUrl = String(paymentInstruction.ticketUrl || '').trim();
    if (buttonUrl) payload.buttonUrl = buttonUrl;
  }
  return payload;
}

module.exports = {
  buildBillingTemplatePayload,
  normalizeTemplateStage,
  templateNameFor,
};
