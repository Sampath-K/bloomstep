import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SignJWT } from 'jose';
import { createLocalTestServer } from './support/local_api_server.mjs';
import { eventSchema } from '../src/contracts.mjs';
import { dashboardSummaries } from '../src/dashboards.mjs';
import { experienceObservationSummary } from '../src/experience-experiments.mjs';
import { dailySnapshotRecordSchema } from '../src/snapshot-contracts.mjs';
import { aggregateEvents } from '../src/engagement.mjs';

function exposure(userId = 'synthetic') {
  return { userId, record: { id: randomUUID(), name: 'experience_observation',
    ts: '2026-07-01T00:00:00.000Z', properties: {
      experienceStudy: 'garden_prompt_v1', experienceArm: 'control', experienceOutcome: 'rendered',
      experiencePolicy: 'app_experience_v1', configVersion: 1,
      cohortId: randomUUID(), consentEpoch: randomUUID(), platform: 'windows',
    } } };
}
test('closed registry rejects content, delivery and malformed dimensions', () => {
  const row = exposure().record;
  assert.equal(eventSchema.safeParse(row).success, true);
  for (const extra of [{ email: 'private' }, { experienceOutcome: 'delivered' }, { configVersion: 0 }, { platform: 'web' }]) {
    assert.equal(eventSchema.safeParse({ ...row, properties: { ...row.properties, ...extra } }).success, false);
  }
});
test('observation-only summary suppresses repeated units and cannot select or promote winners', () => {
  const repeated = Array.from({ length: 60 }, () => exposure());
  const summary = experienceObservationSummary(repeated, '2026-07-01', '2026-07-31');
  assert.equal(summary.provider, 'growthbook');
  assert.equal(summary.productionEnabled, false);
  assert.equal(summary.studies[1].exposedUnits, null);
  const unique = repeated.map((r, i) => ({ ...r, userId: `synthetic-${i}` }));
  const observed = experienceObservationSummary(unique, '2026-07-01', '2026-07-31');
  assert.equal(observed.studies[1].exposedUnits, 60);
  assert.equal(observed.studies[1].decision, 'inconclusive');
  assert.equal(observed.studies[1].reason, 'growthbook_analysis_not_connected');
});
test('daily snapshot accepts bounded GrowthBook status and older absent instrumentation', () => {
  const rows = Array.from({ length: 60 }, (_, i) => exposure(`synthetic-${i}`));
  const record = { ...aggregateEvents(rows, '2026-07-01', '2026-07-01'),
    dashboards: dashboardSummaries(rows, '2026-07-01', '2026-07-01', '2026-07-02') };
  assert.equal(dailySnapshotRecordSchema.safeParse(record).success, true);
  const legacy = structuredClone(record);
  delete legacy.dashboards.appExperience;
  delete legacy.daily[0].counts.experience_observation;
  assert.equal(dailySnapshotRecordSchema.safeParse(legacy).success, true);
  const unsafe = structuredClone(record);
  unsafe.dashboards.appExperience.studies[1].exposedUnits = 1;
  assert.equal(dailySnapshotRecordSchema.safeParse(unsafe).success, false);
});
test('authenticated experiment-epoch deletion is scoped, retryable and suppresses offline replay across API restart', async () => {
  const root = await mkdtemp(join(tmpdir(), 'budlark-it-experience-'));
  const databasePath = join(root, 'experience.json'), key = randomBytes(32);
  let server = await createLocalTestServer({ databasePath, key });
  try {
    const token = async sub => new SignJWT({ scp: 'Garden.ReadWrite' })
      .setProtectedHeader({ alg: 'HS256' }).setIssuer('https://budlark.test')
      .setAudience('budlark-test-api').setSubject(sub).setIssuedAt().setExpirationTime('2m').sign(key);
    const owner = await token('synthetic-experience'), other = await token('synthetic-other');
    const send = (bearer, body) => fetch(`${server.url}/api/sync`, { method: 'POST',
      headers: { 'x-budlark-authorization': `Bearer ${bearer}`, 'content-type': 'application/json' },
      body: JSON.stringify(body) });
    const blank = { habits: [], checkins: [], reflections: [], voice: [], events: [], settings: [], deletions: [] };
    const row = exposure().record;
    const ts = new Date().toISOString();
    const unrelated = { id: randomUUID(), name: 'session_started', ts, properties: { platform: 'windows' } };
    assert.equal((await send(owner, { ...blank, events: [row, unrelated] })).status, 200);
    assert.equal((await send(other, { ...blank, events: [row] })).status, 200);
    const marker = { id: randomUUID(), type: 'experienceEvents', recordId: row.properties.consentEpoch, ts };
    assert.equal((await send('invalid', { ...blank, deletions: [marker] })).status, 401);
    for (let i = 0; i < 2; i++) {
      const result = await send(owner, { ...blank, deletions: [marker] });
      assert.equal(result.status, 200, await result.text());
    }
    await server.close();
    server = await createLocalTestServer({ databasePath, key, reuseDatabase: true });
    assert.equal((await send(owner, { ...blank, events: [row] })).status, 200);
    const docs = JSON.parse(await readFile(databasePath, 'utf8')).documents;
    assert.equal(docs.filter(d => d.type === 'events' && d.record.id === row.id).length, 1);
    assert.equal(docs.filter(d => d.type === 'events' && d.record.id === unrelated.id).length, 1);
  } finally {
    await server.close();
    await rm(root, { recursive: true, force: true });
  }
});
