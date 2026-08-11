'use strict';

const ManualPixConfirmationDecision = Object.freeze({
  CONFIRM: 'confirm',
  ALREADY_CONFIRMED: 'already_confirmed',
  PAID_BY_OTHER_METHOD: 'paid_by_other_method',
  INVALID_STATUS: 'invalid_status',
});

const SAFE_MERCADO_PAGO_TERMINAL_STATUSES = new Set([
  'cancelled',
  'rejected',
  'refunded',
  'charged_back',
]);

/**
 * Classifies a financial record before a manual personal-PIX confirmation.
 * Kept pure so the money-state rules can be exhaustively unit tested.
 */
function classifyManualPixConfirmation(financial) {
  const data = financial || {};
  if (data.status === 'paid') {
    const audit = data.manualPaymentAudit || {};
    if (data.method === 'pix' && data.paymentGateway === 'manual' &&
        audit.type === 'personal_pix') {
      return ManualPixConfirmationDecision.ALREADY_CONFIRMED;
    }
    return ManualPixConfirmationDecision.PAID_BY_OTHER_METHOD;
  }

  if (data.status === 'pending' || data.status === 'overdue') {
    return ManualPixConfirmationDecision.CONFIRM;
  }

  return ManualPixConfirmationDecision.INVALID_STATUS;
}

/**
 * A competing Mercado Pago charge is safe only when it was cancelled by this
 * request or was already in a terminal state that can no longer settle.
 * Unknown/error/intermediate states fail closed to avoid a double payment.
 */
function classifyMercadoPagoCancellation(result) {
  const value = result || {};
  const status = String(value.status || '').toLowerCase();
  if (value.alreadyApproved === true || status === 'approved') {
    return { safe: false, reason: 'approved' };
  }
  if (value.cancelled === true || SAFE_MERCADO_PAGO_TERMINAL_STATUSES.has(status)) {
    return { safe: true, reason: status || 'cancelled' };
  }
  return { safe: false, reason: status || 'unknown' };
}

module.exports = {
  ManualPixConfirmationDecision,
  classifyManualPixConfirmation,
  classifyMercadoPagoCancellation,
};
