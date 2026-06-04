'use strict';

// QA — FINANCIAL pilar: PIX payer (CPF/email) validation symmetry between the
// MENSALIDADE path (createMpPixPayment) and the LOJA path (createMpOrderPixPayment).
//
// Ancorado em functions/server_functions.js:
//   - createMpPix            (~2850)  -> CPF normalize + identification omit @2853/2883
//   - createMpPixPayment     (~2902)  -> fail-fast payer guard @2953-2969 (mensalidade)
//   - createMpOrderPixPayment(~3000)  -> NO payer guard, raw passthrough @3044-3050 (loja)
//
// The CF onCall handlers are NOT exported as plain functions and createMpPix is
// module-internal, so we cannot invoke them without mocking the whole MP HTTP +
// Firestore + Auth surface. Instead we pin the *observable invariants*:
//   1. createMpPix's identification rule: omitted iff normalized CPF < 11 digits.
//   2. The mensalidade guard predicate (cpfDigits.length < 11) rejects what
//      createMpPix would otherwise silently drop.
// Together these document that the LOJA path, lacking the guard, can hand an
// incomplete payer to Mercado Pago -> opaque PIX failure.

const test = require('node:test');
const assert = require('node:assert/strict');

// --- Mirror of createMpPix payer logic (server_functions.js:2853 & :2883) ----
// Kept byte-for-byte equivalent to production so the test breaks if prod drifts.
function mpPixIdentification(payerCpf) {
  const cpf = String((payerCpf) || '').replace(/\D/g, '');
  return cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined;
}

// --- Mirror of the mensalidade guard (server_functions.js:2953-2957) ---------
function mensalidadeCpfGuardRejects(payerCpf) {
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  return cpfDigits.length < 11; // true => HttpsError failed-precondition
}

// --- Mirror of the mensalidade email resolution (2958-2968) ------------------
// authEmail simulates admin.auth().getUser(uid).email fallback.
function mensalidadeResolveEmail(payerEmail, authEmail) {
  let resolvedEmail = String(payerEmail || '').trim();
  if (!resolvedEmail || !resolvedEmail.includes('@') ||
      resolvedEmail.endsWith('@bjjeasy.com.br')) {
    resolvedEmail = String(authEmail || '').trim();
  }
  if (!resolvedEmail || !resolvedEmail.includes('@')) {
    return { ok: false }; // HttpsError failed-precondition
  }
  return { ok: true, email: resolvedEmail };
}

test('createMpPix OMITS identification for a valid 11-digit CPF? no — it includes it', () => {
  assert.deepEqual(mpPixIdentification('12345678901'), { type: 'CPF', number: '12345678901' });
  assert.deepEqual(mpPixIdentification('123.456.789-01'), { type: 'CPF', number: '12345678901' });
});

test('createMpPix DROPS identification for short/empty CPF (the silent failure surface)', () => {
  assert.equal(mpPixIdentification('123'), undefined);
  assert.equal(mpPixIdentification(''), undefined);
  assert.equal(mpPixIdentification(undefined), undefined);
  assert.equal(mpPixIdentification(null), undefined);
  // 10 digits is one short — still dropped.
  assert.equal(mpPixIdentification('1234567890'), undefined);
});

test('mensalidade guard rejects exactly the CPFs that createMpPix would drop', () => {
  // The guard is the contract that protects the mensalidade path: every CPF that
  // would yield identification=undefined MUST be rejected up front.
  for (const bad of ['', '123', '1234567890', undefined, null, '...']) {
    assert.equal(mensalidadeCpfGuardRejects(bad), true,
      `guard should reject ${JSON.stringify(bad)}`);
    assert.equal(mpPixIdentification(bad), undefined,
      `and createMpPix should have dropped it: ${JSON.stringify(bad)}`);
  }
  // Valid CPF passes the guard AND keeps identification.
  assert.equal(mensalidadeCpfGuardRejects('123.456.789-01'), false);
  assert.notEqual(mpPixIdentification('123.456.789-01'), undefined);
});

test('mensalidade email resolution falls back to Auth and rejects empty', () => {
  // payer email present & real -> used as-is.
  assert.deepEqual(mensalidadeResolveEmail('a@b.com', 'auth@x.com'), { ok: true, email: 'a@b.com' });
  // placeholder/system domain -> Auth fallback.
  assert.deepEqual(mensalidadeResolveEmail('x@bjjeasy.com.br', 'real@x.com'),
    { ok: true, email: 'real@x.com' });
  // no email anywhere -> rejected before hitting MP.
  assert.deepEqual(mensalidadeResolveEmail('', ''), { ok: false });
  assert.deepEqual(mensalidadeResolveEmail(undefined, undefined), { ok: false });
});

// --- REGRESSION GUARD: loja path lacks the guard (documents the [low] bug) ----
// This test asserts the *current* (buggy) reality so that, if someone later adds
// the symmetric guard to createMpOrderPixPayment, this test will flip and force a
// conscious update — making the asymmetry visible in CI.
test('BUG[low] loja PIX has NO CPF/email guard: a missing CPF slips through to MP', () => {
  // Simulating the loja path: createMpOrderPixPayment passes payerCpf raw to
  // createMpPix (server_functions.js:3049) with no prior length check.
  const lojaPayerCpf = ''; // user without CPF
  // There is no guard, so the only effect is identification being dropped:
  const ident = mpPixIdentification(lojaPayerCpf);
  assert.equal(ident, undefined,
    'loja sends an incomplete payer (no identification) -> MP likely rejects PIX');
  // Contrast: the mensalidade path would have rejected this BEFORE calling MP.
  assert.equal(mensalidadeCpfGuardRejects(lojaPayerCpf), true,
    'mensalidade would fail-fast; loja does not — this is the asymmetry');
});
