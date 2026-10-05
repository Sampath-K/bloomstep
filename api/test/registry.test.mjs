import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, sep } from 'node:path';
import { eventSchema } from '../src/contracts.mjs';
import { registryVersion, eventRegistry } from '../src/event_registry.g.mjs';
import { dashboardSummaries } from '../src/dashboards.mjs';
import { aggregateEvents } from '../src/engagement.mjs';

const ts = '2026-09-01T12:00:00Z';
const event = (name, properties) => ({ id: randomUUID(), name, ts, ...(properties ? { properties } : {}) });
test('generated registry is versioned, reproducible and self-contained', () => {
  assert.equal(registryVersion, 1);
  assert.ok(eventRegistry.first_launch);
  execFileSync(process.execPath, ['tool/generate_event_registry.mjs', '--check'], { cwd: new URL('../../', import.meta.url) });
});
test('generated registry checks out as LF even with Windows autocrlf enabled', () => {
  const dir = mkdtempSync(join(tmpdir(), 'bloomstep-registry-checkout-'));
  try {
    const files = ['api/src/event_registry.g.mjs', 'api/src/event_registry.g.d.mts', 'lib/core/event_registry.g.dart'];
    execFileSync('git', ['-c', 'core.autocrlf=true', 'checkout-index', `--prefix=${dir}${sep}`, '--', ...files],
      { cwd: new URL('../../', import.meta.url) });
    for (const file of files) {
      const bytes = readFileSync(join(dir, ...file.split('/')), 'utf8');
      assert.equal(bytes.includes('\r'), false, `Generated ${file} must remain LF in a fresh Windows checkout.`);
    }
  } finally {
    rmSync(dir, { recursive: true });
  }
});
test('strict event-specific properties reject private and misplaced fields', () => {
  const valid = [
    event('checkin', { habitId: randomUUID(), localDay: '2026-09-01', result: 'did', latencyMs: 300 }),
    event('automaticity_score', { habitId: randomUUID(), score: 5.5, localDay: '2026-09-01' }),
    event('signin_provider_selected', { provider: 'microsoft' }),
    event('landing_view', { platform: 'windows', channel: 'website' }),
    event('notif_actioned', { action: 'did', notificationId: randomUUID() }),
    event('experiment_exposure', { experiment: 'reminder_copy_v1', variant: 'control' }),
    event('crash', { sessionId: randomUUID(), platform: 'windows', diagnosticSource: 'dart_unhandled', errorKind: 'unknown' }),
  ];
  for (const row of valid) assert.equal(eventSchema.safeParse(row).success, true, row.name);
  for (const row of [
    event('checkin', { email: 'private@example.invalid' }), event('checkin', { result: 'anything' }),
    event('checkin', { localDay: '2026-02-30' }), event('checkin', { latencyMs: -1 }),
    event('automaticity_score', { score: 8 }), event('landing_view', { url: 'https://private.invalid' }),
    event('signin_failed', { reason: 'my error text' }), event('checkin', { provider: 'google' }),
    event('rated', { body: 'private' }), event('signin_succeeded', { userId: randomUUID() }),
    { ...event('first_launch'), schemaVersion: 2 },
    event('notif_actioned', { action: 'anything' }),
    event('experiment_exposure', { experiment: 'arbitrary_experiment', variant: 'control' }),
    event('rated', { rating: 3.5 }),
    event('crash', { message: 'private error' }),
    event('crash', { stack: 'private path' }),
    event('crash', { diagnosticSource: 'native_complete_capture' }),
  ]) assert.equal(eventSchema.safeParse(row).success, false, row.name);
  for (const name of ['recipe_created','checkin','reflection','habit_graduated','feedback_submitted','share_initiated','reminder_sent','signin_succeeded','weekly_reflection','rating_prompted']) {
    assert.equal(eventSchema.safeParse(event(name)).success, true);
  }
});
test('observed recipe taxonomy, weekly recipe and share choices are fixed and event-specific', () => {
  for (const properties of [{ templateCategory: 'calm' }, { templateCategory: 'connection' }]) {
    assert.equal(eventSchema.safeParse(event('recipe_created', properties)).success, true);
  }
  assert.equal(eventSchema.safeParse(event('weekly_reflection', { habitId: randomUUID() })).success, true);
  for (const channel of ['link', 'email']) {
    assert.equal(eventSchema.safeParse(event('share_initiated', { channel })).success, true);
  }
  for (const row of [
    event('recipe_created', { templateCategory: 'My private aspiration' }),
    event('checkin', { templateCategory: 'calm' }),
    event('weekly_reflection', { habitId: 'private habit name' }),
    event('share_initiated', { channel: 'private@example.invalid' }),
    event('analytics_consent', { enabled: true }),
  ]) assert.equal(eventSchema.safeParse(row).success, false);
});
test('explicit opt-in observation allows only fixed platform, not remote consent control or a receipt', () => {
  assert.equal(eventSchema.safeParse(event('analytics_consent', { platform: 'windows' })).success, true);
  for (const properties of [{ enabled: true }, { enabled: false }, { consent: true }, { email: 'private' }, { platform: 'anything' }]) {
    assert.equal(eventSchema.safeParse(event('analytics_consent', properties)).success, false);
  }
});
test('receipt metadata requires matching source/event/platform/channel and no private envelope', () => {
  for (const name of ['landing_view', 'invite_link_open', 'download_click']) {
    assert.equal(eventSchema.safeParse(event(name, { measurementSource: 'website_receipt', platform: 'web', channel: 'website' })).success, true);
  }
  for (const name of ['installer_started', 'install_completed', 'first_launch', 'signin_view']) {
    assert.equal(eventSchema.safeParse(event(name, { measurementSource: 'installer_receipt', platform: 'windows', channel: 'direct' })).success, true);
  }
  for (const row of [
    event('landing_view', { measurementSource: 'installer_receipt', platform: 'web', channel: 'website' }),
    event('installer_started', { measurementSource: 'website_receipt', platform: 'windows', channel: 'direct' }),
    event('landing_view', { measurementSource: 'website_receipt', platform: 'windows', channel: 'website' }),
    event('landing_view', { measurementSource: 'website_receipt' }),
    event('first_launch', { measurementSource: 'installer_receipt', platform: 'windows', channel: 'website' }),
    event('crash', { measurementSource: 'website_receipt' }),
    event('download_click', { receipt: { email: 'private' } }),
  ]) assert.equal(eventSchema.safeParse(row).success, false, row.name);
});
test('registry optional envelopes never make unobservable metrics or sparse ratios available', () => {
  const rows = Array.from({ length: 50 }, (_, i) => [
    row(String(i), 'checkin', '2026-09-01'),
    row(String(i), 'reflection', '2026-09-01'),
    row(String(i), 'reminder_sent', '2026-09-01'),
    row(String(i), 'experiment_exposure', '2026-09-01', { experiment: 'reminder_copy_v1', variant: 'control' }),
  ]).flat();
  const data = dashboardSummaries(rows, '2026-09-01', '2026-09-01', '2026-09-02');
  assert.equal(data.outcomes.daily[0].medianAutomaticity, null);
  assert.equal(data.outcomes.daily[0].practicingUsers, null);
  assert.equal(data.reminderHealth.actionRate.rate, null);
  assert.deepEqual(data.retention.cohorts, []);
  assert.equal(data.experiment.enabled, false);
  const daily = aggregateEvents(rows, '2026-09-01', '2026-09-01');
  assert.equal(daily.daily[0].counts.experiment_exposure, null);
  assert.equal(daily.daily[0].counts.landing_view, null);
  assert.equal(daily.daily[0].counts.checkin, 50);
});

const row = (userId, name, day, properties = {}) => ({ userId, record: { ...event(name, properties), ts: `${day}T12:00:00Z` } });
test('retention uses matured first-checkin cohorts and practicing result, never immature zeroes', () => {
  const rows = Array.from({ length: 50 }, (_, i) => [
    row(String(i), 'first_checkin', '2026-08-01', { localDay: '2026-08-01', result: 'did' }),
    row(String(i), 'checkin', '2026-08-02', { localDay: '2026-08-02', result: 'didMore' }),
    row(String(i), 'checkin', '2026-08-08', { localDay: '2026-08-08', result: 'notToday' }),
  ]).flat();
  const result = dashboardSummaries(rows, '2026-08-01', '2026-09-01', '2026-09-02');
  assert.equal(result.retention.cohorts[0].d1.rate, 1);
  assert.equal(result.retention.cohorts[0].d7.rate, null);
  assert.equal(result.retention.cohorts[0].d7.practicingUsers, null);
  const incomplete = dashboardSummaries(rows, '2026-08-01', '2026-08-01', '2026-08-02');
  assert.equal(incomplete.retention.cohorts[0].d1.matured, false);
  assert.equal(incomplete.retention.cohorts[0].d1.rate, null);
});
test('outcomes, reminder health and funnel require observable contributor cohorts', () => {
  const rows = Array.from({ length: 50 }, (_, i) => [
    row(String(i), 'signin_succeeded', '2026-09-01', { channel: 'website', platform: 'windows' }),
    row(String(i), 'first_checkin', '2026-09-01', { result: 'did', localDay: '2026-09-01' }),
    row(String(i), 'automaticity_score', '2026-09-01', { score: 5 }),
    row(String(i), 'notif_delivered', '2026-09-01', { notificationId: `${String(i).padStart(8,'0')}-0000-4000-8000-000000000000` }),
    row(String(i), 'notif_actioned', '2026-09-01', { notificationId: `${String(i).padStart(8,'0')}-0000-4000-8000-000000000000`, action: 'did' }),
  ]).flat();
  const result = dashboardSummaries(rows, '2026-09-01', '2026-09-01', '2026-09-02');
  assert.equal(result.funnel.sameDayActivation.rate, 1);
  assert.equal(result.funnel.visitToDownload.rate, null);
  assert.equal(result.outcomes.daily[0].medianAutomaticity, 5);
  assert.equal(result.reminderHealth.actionRate.rate, 1);
  assert.equal(result.reminderHealth.disableRate.rate, null);
  assert.equal(result.experiment.enabled, false);
  assert.deepEqual(result, dashboardSummaries([...rows].reverse(), '2026-09-01', '2026-09-01', '2026-09-02'));
});
test('latest per-user score and ordered funnels honor microseconds independent of fractional width', () => {
  const rows = Array.from({ length: 50 }, (_, i) => [
    { userId: String(i), record: { ...event('automaticity_score', { score: 4 }), ts: '2026-09-01T12:00:00.000Z' } },
    { userId: String(i), record: { ...event('automaticity_score', { score: 6 }), ts: '2026-09-01T12:00:00.000001Z' } },
    { userId: String(i), record: { ...event('signin_succeeded', { localDay: '2026-09-01' }), ts: '2026-09-01T12:00:00.000Z' } },
    { userId: String(i), record: { ...event('first_checkin', { localDay: '2026-09-01', result: 'did' }), ts: '2026-09-01T12:00:00.000001Z' } },
  ]).flat();
  const result = dashboardSummaries(rows, '2026-09-01', '2026-09-01', '2026-09-02');
  assert.equal(result.outcomes.daily[0].medianAutomaticity, 6);
  assert.equal(result.funnel.sameDayActivation.rate, 1);
});
test('D30 includes earlier first-practice cohorts rather than always dropping them from recent windows', () => {
  const rows = Array.from({ length: 50 }, (_, i) => [
    row(String(i), 'first_checkin', '2026-08-01', { localDay: '2026-08-01', result: 'did' }),
    row(String(i), 'checkin', '2026-08-31', { localDay: '2026-08-31', result: 'did' }),
  ]).flat();
  const result = dashboardSummaries(rows, '2026-08-26', '2026-08-31', '2026-09-01');
  assert.equal(result.retention.cohorts[0].cohortDay, '2026-08-01');
  assert.equal(result.retention.cohorts[0].d30.matured, true);
  assert.equal(result.retention.cohorts[0].d30.rate, 1);
});
test('later checkin corrections and undo cannot inflate practicing retention or outcome counts', () => {
  const habitId = randomUUID();
  const rows = Array.from({ length: 50 }, (_, i) => [
    row(String(i), 'first_checkin', '2026-08-01', { habitId, localDay: '2026-08-01', result: 'did' }),
    { userId: String(i), record: { ...event('checkin', { habitId, localDay: '2026-08-02', result: 'did' }), ts: '2026-08-02T12:00:00.000Z' } },
    { userId: String(i), record: { ...event('checkin', { habitId, localDay: '2026-08-02', result: 'undo' }), ts: '2026-08-02T12:00:00.000001Z' } },
  ]).flat();
  const result = dashboardSummaries(rows, '2026-08-01', '2026-08-02', '2026-08-03');
  assert.equal(result.retention.cohorts[0].d1.practicingUsers, null);
  assert.equal(result.outcomes.daily[1].practicingUsers, null);
  assert.deepEqual(result, dashboardSummaries([...rows].reverse(), '2026-08-01', '2026-08-02', '2026-08-03'));
});
