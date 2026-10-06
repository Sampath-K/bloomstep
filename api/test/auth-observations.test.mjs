import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { eventSchema } from '../src/contracts.mjs';
import { authObservationSummary } from '../src/auth-observations.mjs';
import { aggregateEvents } from '../src/engagement.mjs';
import { dashboardSummaries } from '../src/dashboards.mjs';
import { dailySnapshotRecordSchema } from '../src/snapshot-contracts.mjs';

const event = (properties = {}, ts = '2026-09-01T00:00:00.000Z') => ({
  id: randomUUID(), name: 'auth_observation', ts, properties: {
    attemptId: randomUUID(), authStage: 'api_token', outcome: 'started',
    authErrorKind: 'none', elapsedMs: 0, authSource: 'external_unattributed',
    platform: 'windows', ...properties,
  },
});
test('closed required schema rejects invalid claims and sensitive payloads', () => {
  assert.equal(eventSchema.safeParse(event()).success, true);
  for (const properties of [
    {}, { ...event().properties, url: 'https://secret?token=x' },
    { ...event().properties, authSource: 'google' },
    { ...event().properties, outcome: 'failed', authErrorKind: 'none' },
    { ...event().properties, outcome: 'succeeded', authErrorKind: 'timeout' },
    { ...event().properties, elapsedMs: -1 },
    { ...event().properties, elapsedMs: 180001 },
  ]) assert.equal(eventSchema.safeParse({ ...event(), properties }).success, false);
});

const pair = (userId, outcome = 'succeeded') => {
  const start = event();
  return [
    { userId, record: start },
    { userId, record: event({ ...start.properties, outcome,
      authErrorKind: outcome === 'failed' ? 'unknown' : 'none', elapsedMs: 1000 },
    '2026-09-01T00:00:01.000Z') },
  ];
};
test('only ordered same-owner pairs in time window count; absence stays unknown', () => {
  const rows = Array.from({ length: 50 }, (_, i) => pair(`user${i}`)).flat();
  const summary = authObservationSummary([...rows, ...rows], '2026-09-01', '2026-09-01');
  assert.equal(summary.stages.api_token.observedUsers, 50);
  assert.equal(summary.stages.api_token.succeededUsers, 50);
  assert.equal(summary.stages.api_token.failedUsers, null);
  assert.equal(summary.allUserSigninSuccessRate, null);
  assert.match(summary.definition, /pre-auth/);
  assert.equal(authObservationSummary([], '2026-09-01', '2026-09-01').stages.api_token.observedUsers, null);
  for (const mutate of [
    pair => pair[1].userId = 'different',
    pair => pair[1].record.ts = '2026-08-31T23:59:59.000Z',
    pair => pair[1].record.ts = '2026-09-01T00:04:00.000Z',
    pair => pair[1].record.properties.elapsedMs = 0,
    pair => pair.shift(),
    pair => pair.push({ ...pair[1], record: { ...pair[1].record, id: randomUUID() } }),
  ]) {
    const invalid = Array.from({ length: 50 }, (_, i) => pair(`u${i}`));
    invalid.forEach(mutate);
    assert.equal(authObservationSummary(invalid.flat(), '2026-09-01', '2026-09-01').stages.api_token.succeededUsers, null);
  }
});

test('conflicting event IDs across attempt IDs cannot manufacture pairs', () => {
  const rows = Array.from({ length: 50 }, (_, i) => pair(`u${i}`)).flat();
  const conflicts = rows.filter(row => row.record.properties.outcome === 'succeeded')
    .map(row => ({ ...row, record: { ...row.record,
      properties: { ...row.record.properties, attemptId: randomUUID() } } }));
  assert.equal(authObservationSummary([...rows, ...conflicts], '2026-09-01', '2026-09-01')
    .stages.api_token.succeededUsers, null);
});

test('failure categories publish only non-subtractable >=50-user partitions', () => {
  const failed = Array.from({ length: 50 }, (_, i) => pair(`u${i}`, 'failed')).flat();
  const summary = authObservationSummary(failed, '2026-09-01', '2026-09-01');
  assert.equal(summary.stages.api_token.failedUsers, 50);
  assert.equal(summary.stages.api_token.failureKinds.unknown, 50);
  failed.at(-1).record.properties.authErrorKind = 'network';
  const suppressed = authObservationSummary(failed, '2026-09-01', '2026-09-01');
  assert.equal(suppressed.stages.api_token.failedUsers, 50);
  assert.equal(suppressed.stages.api_token.failureKinds.unknown, null);
  assert.equal(suppressed.stages.api_token.failureKinds.network, null);
  // A one-user retry overlap must not be subtractable from overall outcomes.
  const overlap = [...Array.from({ length: 50 }, (_, i) => pair(`u${i}`)).flat(),
    ...Array.from({ length: 50 }, (_, i) => pair(`f${i}`, 'failed')).flat(),
    ...pair('u0', 'failed')];
  assert.equal(authObservationSummary(overlap, '2026-09-01', '2026-09-01')
    .stages.api_token.observedUsers, null);
});

test('daily snapshots persist typed auth summaries and preserve pre-instrumentation history', () => {
  const rows = Array.from({ length: 50 }, (_, i) => pair(`u${i}`)).flat();
  const record = { ...aggregateEvents(rows, '2026-09-01', '2026-09-01'),
    dashboards: dashboardSummaries(rows, '2026-09-01', '2026-09-01', '2026-09-02') };
  assert.equal(dailySnapshotRecordSchema.safeParse(record).success, true);
  assert.equal(record.dashboards.authentication.stages.api_token.succeededUsers, 50);
  delete record.dashboards.authentication;
  delete record.daily[0].counts.auth_observation;
  assert.equal(dailySnapshotRecordSchema.safeParse(record).success, true);
});
