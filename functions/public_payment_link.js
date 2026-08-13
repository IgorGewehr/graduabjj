'use strict';

const crypto = require('crypto');

const PUBLIC_TOKEN_BYTES = 32;
const PUBLIC_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const CHECKOUT_TTL_MS = 3 * 24 * 60 * 60 * 1000;

function isValidPublicToken(token) {
  return PUBLIC_TOKEN_PATTERN.test(String(token || ''));
}

function hashPublicToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function generatePublicToken() {
  return crypto.randomBytes(PUBLIC_TOKEN_BYTES).toString('base64url');
}

function tokenEncryptionKey(secret) {
  const value = String(secret || '');
  if (value.length < 32) {
    throw new Error('PUBLIC_PAY_TOKEN_SECRET must contain at least 32 characters');
  }
  return crypto.createHash('sha256').update(value).digest();
}

function encryptPublicToken(token, secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', tokenEncryptionKey(secret), iv);
  const ciphertext = Buffer.concat([
    cipher.update(String(token), 'utf8'),
    cipher.final(),
  ]);
  return {
    tokenCiphertext: ciphertext.toString('base64'),
    tokenIv: iv.toString('base64'),
    tokenTag: cipher.getAuthTag().toString('base64'),
  };
}

function decryptPublicToken(record, secret) {
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    tokenEncryptionKey(secret),
    Buffer.from(String(record?.tokenIv || ''), 'base64')
  );
  decipher.setAuthTag(Buffer.from(String(record?.tokenTag || ''), 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(String(record?.tokenCiphertext || ''), 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

function publicChargeStatus(financial) {
  if (!financial || financial.publicPaymentEnabled === false) return 'unavailable';
  if (financial.status === 'paid') return 'paid';
  if (financial.status === 'cancelled') return 'cancelled';
  if (financial.status === 'pending' || financial.status === 'overdue') return 'open';
  return 'unavailable';
}

function publicAvailableMethods(financial, academy) {
  if (publicChargeStatus(financial) !== 'open' ||
      academy?.publicPaymentLinksEnabled !== true ||
      academy?.mpConnected !== true || academy?.mpNeedsReauth === true) {
    return [];
  }
  const policy = String(financial.paymentMethodPolicy || 'both');
  if (policy === 'pix_only') return ['pix'];
  if (policy === 'card_only') return [];
  return ['pix', 'credit_card'];
}

function isReusableAttempt(attempt, expected) {
  if (!attempt || attempt.status !== 'ready') return false;
  if (!['checkout_pro', 'pix'].includes(attempt.mode)) return false;
  if (attempt.mode === 'checkout_pro' && !attempt.providerRedirectUrl) return false;
  if (attempt.mode === 'pix' && !attempt.pixCode) return false;
  const expiresAtMs = attempt.expiresAt &&
    typeof attempt.expiresAt.toMillis === 'function'
    ? attempt.expiresAt.toMillis()
    : Number(attempt.expiresAtMs || 0);
  return attempt.publicLinkHash === expected.publicLinkHash &&
    attempt.financialVersion === expected.financialVersion &&
    Math.abs(Number(attempt.amount) - Number(expected.amount)) <= 0.01 &&
    attempt.mode === expected.mode &&
    expiresAtMs > Number(expected.nowMs || Date.now()) + 60 * 1000;
}

function isValidRequestId(requestId) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(String(requestId || ''));
}

function publicAttemptStatusFromProvider(paymentStatus) {
  switch (String(paymentStatus || '').toLowerCase()) {
    case 'approved':
      return 'paid';
    case 'pending':
    case 'in_process':
    case 'authorized':
      return 'pending';
    case 'cancelled':
      return 'cancelled';
    case 'rejected':
      return 'failed';
    case 'refunded':
    case 'charged_back':
      return 'reversed';
    default:
      return null;
  }
}

module.exports = {
  CHECKOUT_TTL_MS,
  decryptPublicToken,
  encryptPublicToken,
  generatePublicToken,
  hashPublicToken,
  isReusableAttempt,
  isValidPublicToken,
  isValidRequestId,
  publicAvailableMethods,
  publicAttemptStatusFromProvider,
  publicChargeStatus,
};
