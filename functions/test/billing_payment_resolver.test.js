'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  BillingPaymentMode,
  normalizeBillingPaymentPreference,
  resolveBillingPaymentInstruction,
} = require('../billing_payment_resolver');

const connectedAcademy = {
  mpConnected: true,
  pixKey: 'professor@academia.com',
  pixKeyType: 'email',
};

test('missing and invalid preferences default to Mercado Pago', () => {
  assert.equal(
    normalizeBillingPaymentPreference(),
    BillingPaymentMode.MERCADO_PAGO
  );
  assert.equal(
    normalizeBillingPaymentPreference('unexpected'),
    BillingPaymentMode.MERCADO_PAGO
  );
});

test('legacy academy uses Mercado Pago first when generation succeeds', async () => {
  let calls = 0;
  const result = await resolveBillingPaymentInstruction({
    academy: connectedAcademy,
    generateMercadoPagoPix: async () => {
      calls += 1;
      return { pixCode: '000201-mp', ticketUrl: 'https://mp.example/pix' };
    },
  });

  assert.deepEqual(result, {
    mode: BillingPaymentMode.MERCADO_PAGO,
    pixCode: '000201-mp',
    ticketUrl: 'https://mp.example/pix',
  });
  assert.equal(calls, 1);
});

test('Mercado Pago failure falls back to personal PIX', async () => {
  const result = await resolveBillingPaymentInstruction({
    academy: connectedAcademy,
    generateMercadoPagoPix: async () => {
      throw new Error('Mercado Pago unavailable');
    },
  });

  assert.deepEqual(result, {
    mode: BillingPaymentMode.MANUAL_PIX,
    pixKey: 'professor@academia.com',
    pixKeyType: 'email',
  });
});

test('empty Mercado Pago response also falls back to personal PIX', async () => {
  const result = await resolveBillingPaymentInstruction({
    academy: connectedAcademy,
    generateMercadoPagoPix: async () => ({ pixCode: '   ' }),
  });

  assert.equal(result.mode, BillingPaymentMode.MANUAL_PIX);
});

test('disconnected or reauth-required Mercado Pago falls back without a call', async () => {
  for (const academy of [
    { ...connectedAcademy, mpConnected: false },
    { ...connectedAcademy, mpNeedsReauth: true },
  ]) {
    let calls = 0;
    const result = await resolveBillingPaymentInstruction({
      academy,
      generateMercadoPagoPix: async () => {
        calls += 1;
        return { pixCode: 'should-not-run' };
      },
    });

    assert.equal(result.mode, BillingPaymentMode.MANUAL_PIX);
    assert.equal(calls, 0);
  }
});

test('personal PIX preference does not generate Mercado Pago when key exists', async () => {
  let calls = 0;
  const result = await resolveBillingPaymentInstruction({
    academy: {
      ...connectedAcademy,
      billingPaymentPreference: BillingPaymentMode.MANUAL_PIX,
    },
    generateMercadoPagoPix: async () => {
      calls += 1;
      return { pixCode: 'should-not-run' };
    },
  });

  assert.equal(result.mode, BillingPaymentMode.MANUAL_PIX);
  assert.equal(calls, 0);
});

test('personal PIX preference falls back to Mercado Pago when key is absent', async () => {
  const result = await resolveBillingPaymentInstruction({
    academy: {
      ...connectedAcademy,
      billingPaymentPreference: BillingPaymentMode.MANUAL_PIX,
      pixKey: '   ',
    },
    generateMercadoPagoPix: async () => ({ pixCode: '000201-fallback' }),
  });

  assert.deepEqual(result, {
    mode: BillingPaymentMode.MERCADO_PAGO,
    pixCode: '000201-fallback',
    ticketUrl: null,
  });
});

test('personal PIX preference returns none when both methods are absent', async () => {
  const result = await resolveBillingPaymentInstruction({
    academy: {
      billingPaymentPreference: BillingPaymentMode.MANUAL_PIX,
      mpConnected: false,
      pixKey: '',
    },
  });

  assert.deepEqual(result, { mode: BillingPaymentMode.NONE });
});

test('none preference never exposes or generates payment data', async () => {
  let calls = 0;
  const result = await resolveBillingPaymentInstruction({
    academy: {
      ...connectedAcademy,
      billingPaymentPreference: BillingPaymentMode.NONE,
    },
    generateMercadoPagoPix: async () => {
      calls += 1;
      return { pixCode: 'should-not-run' };
    },
  });

  assert.deepEqual(result, { mode: BillingPaymentMode.NONE });
  assert.equal(calls, 0);
});

test('returns none when neither method can produce an instruction', async () => {
  const result = await resolveBillingPaymentInstruction({
    academy: { mpConnected: false, pixKey: '' },
  });

  assert.deepEqual(result, { mode: BillingPaymentMode.NONE });
});
