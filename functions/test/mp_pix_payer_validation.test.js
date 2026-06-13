'use strict';

// QA — FINANCIAL pilar: PIX payer (CPF/email) validation SYMMETRY between the
// MENSALIDADE path (createMpPixPayment) and the LOJA path (createMpOrderPixPayment).
//
// Historico: a auditoria 2026-06 apontou ([low]) que a LOJA nao tinha o guard de
// payer e repassava CPF/email crus ao MP (falha opaca de PIX). O fix (commit
// 7952bc0) espelhou o guard da mensalidade no caminho da loja e adicionou a
// resolucao/validacao de e-mail tambem ao CARTAO (achado #25). Este teste fixa a
// SIMETRIA atual e quebra se qualquer caminho regredir.
//
// Ancorado em functions/server_functions.js (pos-7952bc0):
//   - createMpPix             (~3100) -> CPF normalize @3103 + identification omit @3133
//   - createMpPixPayment      (~3240) -> fail-fast payer guard @3299-3315 (mensalidade)
//   - createMpOrderPixPayment (~3359) -> fail-fast payer guard @3429-3445 (loja, simetrico)
//   - createMpCardPayment     (~3492) -> e-mail resolve+guard @3585-3596; CPF opcional @3623
//
// The CF onCall handlers are NOT exported as plain functions and createMpPix is
// module-internal, so we cannot invoke them without mocking the whole MP HTTP +
// Firestore + Auth surface. Instead we pin the *observable invariants*:
//   1. createMpPix's identification rule: omitted iff normalized CPF < 11 digits.
//   2. The shared PIX guard predicate (cpfDigits.length < 11) rejects exactly
//      what createMpPix would otherwise silently drop — on BOTH paths.
//   3. The shared e-mail resolution (Auth fallback, placeholder domain rejected)
//      used by mensalidade, loja AND cartao.
// A SOURCE-SYNC canary then greps server_functions.js to prove the mirrors below
// still match production byte-for-byte (the test flips if prod drifts again).

const test = require('node:test');
const assert = require('node:assert/strict');

// --- Mirror of createMpPix payer logic (server_functions.js:3103 & :3133) ----
// Kept byte-for-byte equivalent to production so the test breaks if prod drifts.
function mpPixIdentification(payerCpf) {
  const cpf = String((payerCpf) || '').replace(/\D/g, '');
  return cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined;
}

// --- Mirror of the SHARED PIX CPF guard ---------------------------------------
// Identical in mensalidade (3299-3303) and loja (3429-3433).
function pixCpfGuardRejects(payerCpf) {
  const cpfDigits = String(payerCpf || '').replace(/\D/g, '');
  return cpfDigits.length < 11; // true => HttpsError failed-precondition
}

// --- Mirror of the SHARED e-mail resolution -----------------------------------
// Identical in mensalidade (3304-3315), loja (3434-3445) and cartao (3585-3596).
// authEmail simulates the admin.auth().getUser(uid).email fallback.
function resolvePayerEmail(payerEmail, authEmail) {
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

test('PIX guard (mensalidade E loja) rejects exactly the CPFs createMpPix would drop', () => {
  // The guard is the contract that protects BOTH PIX paths: every CPF that
  // would yield identification=undefined MUST be rejected up front.
  for (const bad of ['', '123', '1234567890', undefined, null, '...']) {
    assert.equal(pixCpfGuardRejects(bad), true,
      `guard should reject ${JSON.stringify(bad)}`);
    assert.equal(mpPixIdentification(bad), undefined,
      `and createMpPix would have dropped it: ${JSON.stringify(bad)}`);
  }
  // Valid CPF passes the guard AND keeps identification.
  assert.equal(pixCpfGuardRejects('123.456.789-01'), false);
  assert.notEqual(mpPixIdentification('123.456.789-01'), undefined);
});

test('e-mail resolution (mensalidade/loja/cartao) falls back to Auth and rejects empty', () => {
  // payer email present & real -> used as-is.
  assert.deepEqual(resolvePayerEmail('a@b.com', 'auth@x.com'), { ok: true, email: 'a@b.com' });
  // placeholder/system domain -> Auth fallback.
  assert.deepEqual(resolvePayerEmail('x@bjjeasy.com.br', 'real@x.com'),
    { ok: true, email: 'real@x.com' });
  // no email anywhere -> rejected before hitting MP.
  assert.deepEqual(resolvePayerEmail('', ''), { ok: false });
  assert.deepEqual(resolvePayerEmail(undefined, undefined), { ok: false });
});

// --- SOURCE-SYNC CANARY: the mirrors above must match production --------------
// Greps server_functions.js and asserts that mensalidade AND loja carry the
// SAME fail-fast payer guard (the [low] asymmetry is FIXED), and that the card
// path validates the e-mail (achado #25) while keeping CPF optional. If anyone
// removes a guard (regression to the audited bug) or rewrites it so the local
// mirrors drift, this test flips and forces a conscious update.
test('SOURCE SYNC: payer guards are symmetric in production (loja fix is in place)', () => {
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'server_functions.js'),
    'utf8'
  );

  // Every onCall handler body ends with `});` at column 0.
  const handlerBody = (marker) => {
    const start = src.indexOf(marker);
    assert.ok(start > 0, `${marker} present`);
    const end = src.indexOf('\n});', start);
    assert.ok(end > start, `${marker} body delimited`);
    return src.slice(start, end);
  };

  const cpfNormalize = "const cpfDigits = String(payerCpf || '').replace(/\\D/g, '')";
  const cpfGuard = 'if (cpfDigits.length < 11)';
  const emailPlaceholder = "resolvedEmail.endsWith('@bjjeasy.com.br')";
  const emailGuard = "if (!resolvedEmail || !resolvedEmail.includes('@'))";

  // BOTH PIX paths: full payer guard (CPF + e-mail), byte-symmetric.
  for (const marker of ['exports.createMpPixPayment', 'exports.createMpOrderPixPayment']) {
    const body = handlerBody(marker);
    assert.ok(body.includes(cpfNormalize), `${marker}: CPF normalize present`);
    assert.ok(body.includes(cpfGuard), `${marker}: CPF length guard present`);
    assert.ok(body.includes(emailPlaceholder), `${marker}: placeholder e-mail fallback present`);
    assert.ok(body.includes(emailGuard), `${marker}: e-mail fail-fast guard present`);
    // The guarded values are what actually reach createMpPix (not the raw input).
    assert.ok(body.includes('payer: { email: resolvedEmail, cpf: cpfDigits'),
      `${marker}: validated payer is forwarded to createMpPix`);
  }

  // CARD path (achado #25): e-mail resolved+validated; CPF stays OPTIONAL
  // (identification omitted when < 11 digits — cards do not require CPF).
  const card = handlerBody('exports.createMpCardPayment');
  assert.ok(card.includes(emailPlaceholder), 'card: placeholder e-mail fallback present');
  assert.ok(card.includes(emailGuard), 'card: e-mail fail-fast guard present');
  assert.ok(!card.includes(cpfGuard), 'card: CPF must remain optional (no length guard)');
  assert.ok(card.includes("cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined"),
    'card: identification omitted iff CPF < 11 digits (mirrors createMpPix)');

  // createMpPix itself: identification ternary unchanged (mirror of
  // mpPixIdentification above).
  const pixStart = src.indexOf('async function createMpPix(');
  assert.ok(pixStart > 0, 'createMpPix present');
  const pixBody = src.slice(pixStart, src.indexOf('\n}', pixStart + 1));
  assert.ok(pixBody.includes("identification: cpf.length >= 11 ? { type: 'CPF', number: cpf } : undefined"),
    'createMpPix: identification rule matches the local mirror');
});
