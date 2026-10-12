import test from 'node:test';
import assert from 'node:assert/strict';
import { automationAccounts, runIsolationAcceptance, redactSignInText, signIn } from '../production-isolation.mjs';
import { createHash } from 'node:crypto';

test('sign-in diagnostics redact credentials, accounts, tokens and identifiers', () => {
  const account = { email: 'fixture@example.com', password: 'sensitive-fixture-password' };
  const text = redactSignInText(`${account.email} ${account.password} eyJfixture.payload.signature 11111111-1111-4111-8111-111111111111 More information required`, account);
  assert.equal(text.includes(account.email), false);
  assert.equal(text.includes(account.password), false);
  assert.equal(text.includes('eyJ'), false);
  assert.match(text, /More information required/);
});

test('hosted sign-in uses PKCE/state with the real username control and stops on an MFA prompt', async () => {
  const account = { email: 'bloomstep-test-a@bloomstepcustomers261004.onmicrosoft.com', password: 'synthetic-password-not-for-login' };
  for (const mfa of [false, true]) {
    let authorization, passwordEntered = false, closed = false, exchanges = 0;
    const page = {
      setDefaultTimeout() {},
      goto: async url => { authorization = new URL(url); },
      url: () => authorization.href,
      locator: selector => ({
        first() { return this; },
        fill: async value => {
          if (selector === 'input[type="password"]') { assert.equal(value, account.password); passwordEntered = true; }
          else { assert.match(selector, /input\[name="username"\]/); assert.equal(value, account.email); }
        },
        isVisible: async () => false, waitFor: async () => {},
        innerText: async () => mfa && passwordEntered ? 'Verify your identity' : 'Sign in',
        evaluateAll: async () => [],
      }),
      getByRole: () => ({ click: async () => {
        if (passwordEntered && !mfa) {
          const callback = new URL(authorization.searchParams.get('redirect_uri'));
          callback.search = new URLSearchParams({ state: authorization.searchParams.get('state'), code: 'synthetic-code' });
          assert.equal((await fetch(callback)).status, 200);
        }
      } }),
    };
    const browser = { newContext: async () => ({ newPage: async () => page, close: async () => { closed = true; } }) };
    const exchange = async (_url, options) => {
      exchanges++;
      assert.equal(options.body.get('grant_type'), 'authorization_code');
      assert.equal(options.body.has('client_secret'), false);
      assert.equal(createHash('sha256').update(options.body.get('code_verifier')).digest('base64url'),
        authorization.searchParams.get('code_challenge'));
      return { ok: true, json: async () => ({ access_token: 'synthetic-access-token' }) };
    };
    const run = signIn(browser, account, '11111111-1111-4111-8111-111111111111', exchange);
    if (mfa) { await assert.rejects(run, /Hosted sign-in blocked: Verify your identity/); assert.equal(exchanges, 0); }
    else { assert.equal(await run, 'synthetic-access-token'); assert.equal(exchanges, 1); }
    assert.equal(closed, true);
  }
});

test('only dedicated local accounts are accepted and missing/duplicate credentials fail closed', () => {
  const env = {};
  for (const label of ['A', 'B', 'ADMIN']) {
    env[`BLOOMSTEP_TEST_${label}_EMAIL`] = `bloomstep-test-${label.toLowerCase()}@bloomstepcustomers261004.onmicrosoft.com`;
    env[`BLOOMSTEP_TEST_${label}_PASSWORD`] = 'synthetic-fixture-password-not-for-login';
  }
  assert.equal(automationAccounts(env).length, 3);
  for (const invalid of [{}, { ...env, BLOOMSTEP_TEST_A_EMAIL: 'real-customer@example.com' },
    { ...env, BLOOMSTEP_TEST_A_PASSWORD: '' }, { ...env, BLOOMSTEP_TEST_B_EMAIL: env.BLOOMSTEP_TEST_A_EMAIL }]) {
    assert.throws(() => automationAccounts(invalid), /Dedicated automation credentials/);
  }
});

function fixture({ wrongRead = false, wrongDenial = false, failCleanup = false } = {}) {
  const gardens = new Map(), calls = [], audits = new Map();
  const ids = { A: 'a'.repeat(64), B: 'b'.repeat(64), ADMIN: 'c'.repeat(64) };
  const call = async (label, route, method = 'GET', payload) => {
    calls.push({ label, route, method, payload });
    if (route === '/api/account/isolation') {
      if (method === 'GET') return { status: 200, data: { userId: ids[label] } };
      const auditId = label === 'A' ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222';
      audits.set(label, auditId);
      return { status: 200, data: { userId: ids[label], auditId, counts: { habits: 1, checkins: 0, reflections: 0, voice: 1, settings: 0 },
        checks: { ownRead: 200, ownEmptySync: 200, foreignRead: 400, foreignWrite: 400, teamFeedback: 403 } } };
    }
    if (route.startsWith('/api/team/')) return { status: label === 'ADMIN' ? 200 : wrongDenial ? 200 : 403, data: { daily: [] } };
    if (route.startsWith('/api/sync?')) return { status: 400, data: {} };
    if (payload?.userId) return { status: 400, data: {} };
    if (method === 'POST') {
      if (payload.deletions?.length) {
        if (failCleanup) return { status: 503, data: {} };
        gardens.delete(label);
      } else gardens.set(label, payload);
    }
    const other = label === 'A' ? 'B' : 'A';
    return { status: 200, data: gardens.get(wrongRead ? other : label) ?? { habits: [], voice: [] } };
  };
  return { call, calls, gardens };
}

test('real acceptance exercises same-record-id writes, own reads, peer denial, Admin metrics and cleanup', async () => {
  const f = fixture();
  const evidence = await runIsolationAcceptance(f.call);
  assert.equal(evidence.passed, true);
  assert.equal(evidence.cleanup, 'passed');
  assert.equal(evidence.adminMetrics, 200);
  assert.equal(evidence.accounts.length, 2);
  assert.equal(f.gardens.size, 0);
  const writes = f.calls.filter(c => c.route === '/api/sync' && c.payload?.habits?.length && !c.payload.userId);
  assert.equal(writes[0].payload.habits[0].id, writes[1].payload.habits[0].id);
  assert.equal(writes[0].payload.voice[0].id, writes[1].payload.voice[0].id);
  const receipt = JSON.stringify(evidence);
  assert.equal(receipt.includes('a'.repeat(64)), false);
  assert.equal(receipt.includes('b'.repeat(64)), false);
  assert.equal(receipt.includes('Automation isolation fixture'), false);
  assert.equal(receipt.includes('@'), false);
});

test('cross-account leakage, missing denial and failed cleanup cannot produce passing evidence', async () => {
  for (const options of [{ wrongRead: true }, { wrongDenial: true }, { failCleanup: true }]) {
    const f = fixture(options);
    const evidence = await runIsolationAcceptance(f.call);
    assert.equal(evidence.passed, false);
    assert.ok(f.calls.filter(c => c.payload?.deletions?.length).length >= 2);
    assert.equal(JSON.stringify(evidence).includes('a'.repeat(64)), false);
  }
});
