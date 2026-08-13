'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '..', '..');

test('all Firebase Hosting API rewrites target Firebase Functions', () => {
  const firebaseConfig = JSON.parse(fs.readFileSync(
    path.join(repositoryRoot, 'firebase.json'),
    'utf8'
  ));
  const apiRewrites = (firebaseConfig.hosting?.rewrites || [])
    .filter((rewrite) => rewrite.source.startsWith('/api/'));

  assert.ok(apiRewrites.length > 0, 'expected at least one /api rewrite');
  for (const rewrite of apiRewrites) {
    assert.equal(typeof rewrite.function?.functionId, 'string');
    assert.ok(rewrite.function.functionId.length > 0);
    assert.equal(rewrite.run, undefined);
    assert.equal(rewrite.destination, undefined);
    assert.equal(rewrite.redirect, undefined);
  }
});

test('public payment site calls only same-origin API routes', () => {
  const publicPayScript = fs.readFileSync(
    path.join(repositoryRoot, 'site', 'pay', 'pay.js'),
    'utf8'
  );

  assert.match(publicPayScript, /post\('\/api\/public-pay\/resolve'/);
  assert.match(publicPayScript, /post\('\/api\/public-pay\/start'/);
  assert.doesNotMatch(publicPayScript, /cloudfunctions\.net|netlify|vercel|supabase/i);
});

test('production runtime and webhook secrets stay deployable', () => {
  const packageJson = JSON.parse(fs.readFileSync(
    path.join(repositoryRoot, 'functions', 'package.json'),
    'utf8'
  ));
  const workflow = fs.readFileSync(
    path.join(repositoryRoot, '.github', 'workflows', 'quality.yml'),
    'utf8'
  );
  const server = fs.readFileSync(
    path.join(repositoryRoot, 'functions', 'server_functions.js'),
    'utf8'
  );
  const index = fs.readFileSync(
    path.join(repositoryRoot, 'functions', 'index.js'),
    'utf8'
  );
  const accessIngest = fs.readFileSync(
    path.join(repositoryRoot, 'functions', 'access_control', 'ingest.js'),
    'utf8'
  );

  assert.equal(packageJson.engines.node, '22');
  assert.match(workflow, /node-version: '22'/);
  assert.match(
    server,
    /const MP_MKT_WEBHOOK_SECRETS = \[\.\.\.MP_MKT_SECRETS, 'MP_MKT_WEBHOOK_SECRET'\]/
  );
  assert.match(
    server,
    /mercadoPagoMarketplaceWebhook = onRequest\(\s*\/\/[^]*?secrets: MP_MKT_WEBHOOK_SECRETS/
  );
  for (const functionName of [
    'mercadoPagoOAuthCallback',
    'resolvePublicCharge',
    'startPublicCheckout',
    'mercadoPagoMarketplaceWebhook',
  ]) {
    assert.match(
      server,
      new RegExp(`${functionName} = onRequest\\([^]*?invoker: 'public'`)
    );
  }
  for (const functionName of ['caktoWebhook', 'mercadoPagoWebhook']) {
    assert.match(
      index,
      new RegExp(`${functionName} = onRequest\\([^]*?invoker: 'public'`)
    );
  }
  assert.match(accessIngest, /ingestAccessEvent = onRequest\(\s*\{[^}]*invoker: 'public'/);
});
