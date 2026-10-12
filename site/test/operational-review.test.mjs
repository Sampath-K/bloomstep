import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { operatorRequest, validatePublicConfig } from '../operator-auth.mjs';
import { parsePauseStatus, pauseSummary, resumePayload, resumeConfirmation } from '../operational-review.mjs';

const pauseId = '67ceaed3-4af0-5a5d-8d7e-d081069b189e';
const paused = { paused: true, requestId: pauseId, reason: 'paid_sku', pausedAt: '2026-10-10T06:26:23.000Z' };

test('pause status is strictly parsed and shows the exact pause id the Admin reviews', () => {
  assert.deepEqual(parsePauseStatus({ paused: false }), { paused: false });
  assert.deepEqual(parsePauseStatus(paused), paused);
  assert.match(pauseSummary(paused), new RegExp(pauseId));
  assert.match(pauseSummary(paused), /paid_sku/);
  assert.match(pauseSummary({ paused: false }), /not paused/i);
  for (const value of [null, {}, { paused: 'true' }, { ...paused, requestId: 'not-a-uuid' },
    { ...paused, reason: 'other' }, { ...paused, pausedAt: 5 }, { ...paused, extra: 'x' }]) {
    assert.throws(() => parsePauseStatus(value), /Invalid pause status/);
  }
});

test('resume payload uses the existing contract and requires typed confirmation of the current pause id', () => {
  assert.equal(resumeConfirmation, 'reviewed-free-tier-and-spending-limit');
  const id = () => '11111111-1111-4111-8111-111111111111';
  assert.deepEqual(resumePayload(paused, pauseId, id), {
    requestId: '11111111-1111-4111-8111-111111111111', reviewedPauseRequestId: pauseId,
    confirmation: 'reviewed-free-tier-and-spending-limit',
  });
  assert.deepEqual(resumePayload(paused, ` ${pauseId.toUpperCase()} `, id).reviewedPauseRequestId, pauseId);
  assert.throws(() => resumePayload(paused, '', id), /Type the current pause ID/);
  assert.throws(() => resumePayload(paused, randomLike(), id), /Type the current pause ID/);
  assert.throws(() => resumePayload({ paused: false }, pauseId, id), /not paused/);
  assert.throws(() => resumePayload(null, pauseId, id), /Load the current pause status/);
});

const randomLike = () => '22222222-2222-4222-8222-222222222222';

test('operator transport allows only the console team routes, including status/resume', async () => {
  const auth = { token: async () => 'fixture.token' };
  const calls = [];
  const fetcher = async (url, options) => { calls.push({ url, options }); return { ok: true, json: async () => ({}) }; };
  for (const path of ['/api/team/operational-status', '/api/team/operational-resume', '/api/team/website?days=7']) {
    await operatorRequest(auth, 'https://test.azurestaticapps.net', path, {}, fetcher);
  }
  assert.equal(calls.length, 3);
  for (const path of ['/api/team/operational-statusx', '/api/internal/operational-pause', '/api/team/operational-resume/../x']) {
    await assert.rejects(operatorRequest(auth, 'https://test.azurestaticapps.net', path, {}, fetcher), /Invalid same-origin/);
  }
});

test('console token requests Garden.ReadWrite (resume needs Admin role + Garden scope) and the console exposes the review action', () => {
  const config = { clientId: '11111111-1111-4111-8111-111111111111',
    issuer: 'https://example.ciamlogin.com/22222222-2222-4222-8222-222222222222/v2.0',
    scope: 'api://33333333-3333-4333-8333-333333333333/Garden.ReadWrite' };
  assert.match(validatePublicConfig(config, 'https://test.azurestaticapps.net').scope, /\/Garden\.ReadWrite$/);
  assert.throws(() => validatePublicConfig({ ...config, scope: 'api://33333333-3333-4333-8333-333333333333/Other' }, 'https://test.azurestaticapps.net'));
  const html = readFileSync(new URL('../console.html', import.meta.url), 'utf8');
  for (const id of ['pause-status', 'pause-confirm', 'resume-operations', 'pause-admin-status']) assert.match(html, new RegExp(`id="${id}"`));
  assert.match(html, /Resume after spending review/);
  const source = readFileSync(new URL('../console.mjs', import.meta.url), 'utf8');
  assert.match(source, /\/api\/team\/operational-status/);
  assert.match(source, /\/api\/team\/operational-resume/);
});
