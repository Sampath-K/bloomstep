import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { operatorRequest } from '../operator-auth.mjs';
import { isolationIdentity, isolationPayload, isolationSummary } from '../isolation-check.mjs';

const userId = 'a'.repeat(64), peerUserId = 'b'.repeat(64);
const result = { userId, auditId: '11111111-1111-4111-8111-111111111111',
  counts: { habits: 0, checkins: 1, reflections: 0, voice: 2, settings: 0 },
  checks: { ownRead: 200, ownEmptySync: 200, foreignRead: 400, foreignWrite: 400, teamFeedback: 403 } };

test('isolation UI requires a different account hash and never treats incomplete proof as success', () => {
  assert.equal(isolationIdentity({ userId }), userId);
  assert.deepEqual(isolationPayload(userId, ` ${peerUserId} `), { peerUserId });
  for (const peer of ['', userId, 'raw-account-subject']) assert.throws(() => isolationPayload(userId, peer));
  assert.match(isolationSummary(result, userId), /Verified/);
  assert.match(isolationSummary(result, userId), /Own feedback: 2/);
  assert.match(isolationSummary(result, userId), /11111111-1111-4111-8111-111111111111/);
  for (const invalid of [null, {}, { ...result, userId: peerUserId }, { ...result, auditId: '' },
    { ...result, counts: { ...result.counts, voice: -1 } },
    { ...result, checks: { ...result.checks, foreignWrite: 200 } },
    { ...result, checks: { ...result.checks, ownRead: undefined } }]) {
    assert.throws(() => isolationSummary(invalid, userId));
  }
  assert.match(isolationSummary({ ...result, checks: { ...result.checks, teamFeedback: 'admin-authorized-not-tested' } }, userId),
    /Admin team access is intentionally authorized/);
});

test('bundled console allows the exact Admin-free isolation route, not arbitrary account routes', async () => {
  let calls = 0;
  const auth = { token: async () => 'fixture.token' };
  const fetcher = async () => { calls++; return { ok: true, json: async () => ({ userId }) }; };
  await operatorRequest(auth, 'https://test.azurestaticapps.net', '/api/account/isolation', {}, fetcher);
  assert.equal(calls, 1);
  for (const path of ['/api/account', '/api/account/isolation/other', '/api/account/isolation?userId=x', '/api/sync']) {
    await assert.rejects(operatorRequest(auth, 'https://test.azurestaticapps.net', path, {}, fetcher));
  }
  const html = readFileSync(new URL('../console.html', import.meta.url), 'utf8');
  for (const id of ['isolation-identity', 'isolation-peer', 'isolation-check', 'isolation-status']) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
  assert.match(html, /Verify my data isolation/);
});
