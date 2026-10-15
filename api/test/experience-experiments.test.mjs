import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { randomBytes } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SignJWT } from 'jose';
import { createLocalTestServer } from './support/local_api_server.mjs';
import { eventSchema } from '../src/contracts.mjs';
import { dashboardSummaries } from '../src/dashboards.mjs';
import { evaluateExperience, experiencePolicy, experiencePolicyHash } from '../src/experience-experiments.mjs';

const startAt = '2026-07-01T00:00:00.000Z';
const observedThrough = '2026-08-13T00:00:00.000Z';
const plan = { study: 'garden_prompt_v1', version: 1, startAt, policyHash: experiencePolicyHash };
function fixture(n = 2000, successes = [600, 900]) {
  const rows = [];
  for (let armIndex = 0; armIndex < 2; armIndex++) {
    for (let i = 0; i < n; i++) {
      const userId = `${armIndex}:${i}`, cohortId = randomUUID(), consentEpoch = randomUUID();
      const base = { experienceStudy: plan.study, experienceArm: armIndex ? 'candidate' : 'control',
        experiencePolicy: 'app_experience_v1', configVersion: 1, cohortId, consentEpoch, platform: 'windows' };
      for (const outcome of ['rendered', 'task_completed', 'followup', ...(i < successes[armIndex] ? ['practice'] : [])]) {
        rows.push({ userId, record: { id: randomUUID(), name: 'experience_observation',
          ts: outcome === 'rendered' ? startAt : outcome === 'task_completed' ? '2026-07-01T01:00:00.000Z' : '2026-07-08T00:00:00.000Z',
          properties: { ...base, experienceOutcome: outcome } } });
      }
    }
  }
  return rows;
}
const evidence = { syntheticOnly: true, accessibility: 'pass', optOut: 'observed', burden: 'observed', errors: 'observed', captureComplete: true };
test('closed registry rejects content, delivery and malformed dimensions', () => {
  const row = fixture(1, [0, 0])[0].record;
  assert.equal(eventSchema.safeParse(row).success, true);
  for (const extra of [{ email: 'private' }, { experienceOutcome: 'delivered' }, { configVersion: 0 }, { platform: 'web' }]) {
    assert.equal(eventSchema.safeParse({ ...row, properties: { ...row.properties, ...extra } }).success, false);
  }
});
test('honest sample planning, no peeking, absent evidence and suppression block winners', () => {
  assert.equal(experiencePolicy.design.minimumPerArm, 2000);
  assert.match(experiencePolicy.design.planning, /1902/);
  assert.equal(evaluateExperience(fixture(50, [10, 45]), plan, observedThrough, evidence).decision, 'inconclusive');
  assert.equal(evaluateExperience(fixture(), plan, '2026-07-30T00:00:00.000Z', evidence).reason, 'not_final');
  assert.equal(evaluateExperience(fixture(), plan, observedThrough).reason, 'guardrails_unobservable');
  assert.equal(evaluateExperience([], plan, observedThrough).reason, 'no_data');
});
test('large synthetic lift can only produce an isolated reversible draft recommendation', () => {
  const rows = fixture();
  const receipt = evaluateExperience(rows, plan, observedThrough, evidence);
  assert.equal(receipt.decision, 'candidate_review');
  assert.equal(receipt.productionEligible, false);
  assert.equal(receipt.promotion, null);
  assert.equal(receipt.syntheticOnly, true);
  assert.ok(receipt.statistics.lowerLift > .05);
  assert.match(receipt.receiptHash, /^[a-f0-9]{64}$/);
  assert.equal(evaluateExperience([...rows].reverse(), plan, observedThrough, evidence).receiptHash, receipt.receiptHash);
});
test('missing followup, arm contamination, duplicate drift and task harm block recommendation', () => {
  for (const mutate of [
    rows => rows.filter(r => r.record.properties.experienceOutcome !== 'followup'),
    rows => [...rows, { ...rows[0], record: { ...rows[0].record, id: randomUUID(),
      properties: { ...rows[0].record.properties, experienceArm: 'candidate' } } }],
    rows => [...rows, { ...rows[0], record: { ...rows[0].record, ts: '2026-07-01T00:00:01.000Z' } }],
    rows => rows.filter(r => !(r.record.properties.experienceArm === 'candidate' && r.record.properties.experienceOutcome === 'task_completed')),
  ]) {
    assert.notEqual(evaluateExperience(mutate(fixture()), plan, observedThrough, evidence).decision, 'candidate_review');
  }
});
test('no useful-practice or tiny/conflicting lift retains control, not invite-volume optimization', () => {
  assert.equal(evaluateExperience(fixture(2000, [600, 610]), plan, observedThrough, evidence).decision, 'retain_control');
  assert.equal(evaluateExperience(fixture(2000, [600, 0]), plan, observedThrough, evidence).decision, 'rollback_harm');
});
test('existing account dashboard exposes privacy-suppressed observation status, not a live winner', () => {
  const summary = dashboardSummaries(fixture(10, [2, 8]), '2026-07-01', '2026-07-31', '2026-08-13');
  assert.equal(summary.appExperience.productionEnabled, false);
  assert.equal(summary.appExperience.studies[0].exposedUnits, null);
  assert.equal(summary.appExperience.studies[0].decision, 'inconclusive');
});

test('authenticated experiment-epoch deletion is scoped, retryable and suppresses offline replay across API restart', async () => {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-experience-'));
  const databasePath = join(root, 'experience.json'), key = randomBytes(32);
  let server = await createLocalTestServer({ databasePath, key });
  try {
    const token = async sub => new SignJWT({ scp: 'Garden.ReadWrite' })
      .setProtectedHeader({ alg: 'HS256' }).setIssuer('https://bloomstep.test')
      .setAudience('bloomstep-test-api').setSubject(sub).setIssuedAt().setExpirationTime('2m').sign(key);
    const owner = await token('synthetic-experience'), other = await token('synthetic-other');
    const send = (bearer, body) => fetch(`${server.url}/api/sync`, { method: 'POST',
      headers: { 'x-bloomstep-authorization': `Bearer ${bearer}`, 'content-type': 'application/json' },
      body: JSON.stringify(body) });
    const blank = { habits: [], checkins: [], reflections: [], voice: [], events: [], settings: [], deletions: [] };
    const exposure = fixture(1, [0, 0])[0].record;
    const ts = new Date().toISOString();
    const unrelated = { id: randomUUID(), name: 'session_started', ts, properties: { platform: 'windows' } };
    assert.equal((await send(owner, { ...blank, events: [exposure, unrelated] })).status, 200);
    assert.equal((await send(other, { ...blank, events: [exposure] })).status, 200);
    const marker = { id: randomUUID(), type: 'experienceEvents', recordId: exposure.properties.consentEpoch, ts };
    assert.equal((await send('invalid', { ...blank, deletions: [marker] })).status, 401);
    for (let i = 0; i < 2; i++) {
      const result = await send(owner, { ...blank, deletions: [marker] });
      assert.equal(result.status, 200, await result.text());
    }
    await server.close();
    server = await createLocalTestServer({ databasePath, key, reuseDatabase: true });
    const replay = await send(owner, { ...blank, events: [exposure] });
    assert.equal(replay.status, 200);
    const disk = await readFile(databasePath, 'utf8');
    const data = JSON.parse(disk);
    const docs = Array.isArray(data) ? data : data.documents;
    assert.equal(docs.filter(d => d.type === 'events' && d.record.id === exposure.id).length, 1);
    assert.equal(docs.filter(d => d.type === 'events' && d.record.id === unrelated.id).length, 1);
  } finally {
    await server.close();
    await rm(root, { recursive: true, force: true });
  }
});
