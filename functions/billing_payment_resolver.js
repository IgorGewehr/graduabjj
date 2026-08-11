'use strict';

const BillingPaymentMode = Object.freeze({
  MERCADO_PAGO: 'mercado_pago',
  MANUAL_PIX: 'manual_pix',
  NONE: 'none',
});

const validPreferences = new Set(Object.values(BillingPaymentMode));

/**
 * Missing or unknown values keep the legacy/default behavior: Mercado Pago is
 * tried first and personal PIX is its fallback.
 */
function normalizeBillingPaymentPreference(value) {
  return validPreferences.has(value)
    ? value
    : BillingPaymentMode.MERCADO_PAGO;
}

function getManualPix(academy) {
  const pixKey = String(academy?.pixKey || '').trim();
  if (!pixKey) return null;

  return {
    mode: BillingPaymentMode.MANUAL_PIX,
    pixKey,
    pixKeyType: academy?.pixKeyType || null,
  };
}

function canTryMercadoPago(academy) {
  return academy?.mpConnected === true && academy?.mpNeedsReauth !== true;
}

async function getMercadoPagoPix(academy, generateMercadoPagoPix) {
  if (!canTryMercadoPago(academy) ||
      typeof generateMercadoPagoPix !== 'function') {
    return null;
  }

  try {
    const generated = await generateMercadoPagoPix();
    const pixCode = String(generated?.pixCode || '').trim();
    if (!pixCode) return null;

    return {
      mode: BillingPaymentMode.MERCADO_PAGO,
      pixCode,
      ticketUrl: String(generated?.ticketUrl || '').trim() || null,
    };
  } catch (_) {
    // Generation failures are expected fallback conditions. The integration
    // that generates the PIX remains responsible for logging/monitoring them.
    return null;
  }
}

/**
 * Resolves one payment instruction for a charge without mutating Firestore.
 *
 * - mercado_pago: MP first, then personal PIX.
 * - manual_pix: personal PIX first, then MP.
 * - none: no payment data, even when either method is configured.
 */
async function resolveBillingPaymentInstruction({
  academy = {},
  generateMercadoPagoPix,
} = {}) {
  const preference = normalizeBillingPaymentPreference(
    academy.billingPaymentPreference
  );

  if (preference === BillingPaymentMode.NONE) {
    return { mode: BillingPaymentMode.NONE };
  }

  const orderedModes = preference === BillingPaymentMode.MANUAL_PIX
    ? [BillingPaymentMode.MANUAL_PIX, BillingPaymentMode.MERCADO_PAGO]
    : [BillingPaymentMode.MERCADO_PAGO, BillingPaymentMode.MANUAL_PIX];

  for (const mode of orderedModes) {
    const instruction = mode === BillingPaymentMode.MANUAL_PIX
      ? getManualPix(academy)
      : await getMercadoPagoPix(academy, generateMercadoPagoPix);

    if (instruction) return instruction;
  }

  return { mode: BillingPaymentMode.NONE };
}

module.exports = {
  BillingPaymentMode,
  canTryMercadoPago,
  normalizeBillingPaymentPreference,
  resolveBillingPaymentInstruction,
};
