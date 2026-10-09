import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { aarrrSummary } from '../src/aarrr.mjs';

const habitId = '10000000-0000-4000-8000-000000000001';
function event(userId, name, ts, properties = {}) {
  return { userId, record: { id: randomUUID(), name, ts, properties } };
}
function group(prefix, count, build) {
  return Array.from({ length: count }, (_, i) => build(`${prefix}-${i}`)).flat();
}
const signin = user => event(user, 'signin_succeeded', '2026-09-01T10:00:00Z');
const recipe = user => event(user, 'recipe_created', '2026-09-01T11:00:00Z', { habitId, localDay: '2026-09-01' });
const practice = (user, day = '2026-09-01', name = 'first_checkin', result = 'did') =>
  event(user, name, `${day}T12:00:00Z`, { habitId, localDay: day, result });
const summarize = rows => aarrrSummary(rows, '2026-09-01', '2026-09-14', '2026-09-15');

test('ordered saved activation uses unique account and same habit evidence, not stage totals', () => {
  const rows = [
    ...group('active', 100, user => [signin(user), recipe(user), practice(user)]),
    ...group('recipe-only', 100, user => [signin(user), recipe(user)]),
    ...group('signin-only', 100, user => [signin(user)]),
    ...group('wrong-order', 50, user => [practice(user), event(user, 'recipe_created', '2026-09-02T10:00:00Z', { habitId }), signin(user)]),
    ...group('wrong-habit', 50, user => [signin(user), recipe(user),
      event(user, 'first_checkin', '2026-09-02T12:00:00Z', { habitId: randomUUID(), localDay: '2026-09-02', result: 'did' })]),
  ];
  const report = summarize(rows);
  assert.deepEqual(report.funnel.stages.map(stage => stage.accounts), [400, 300, 100]);
  assert.equal(report.funnel.transitions[0].rate, 300 / 400);
  assert.equal(report.funnel.transitions[1].rate, 100 / 300);
  assert.equal(report.funnel.transitions[1].eligibleAccounts, 300);
  assert.equal(report.funnel.transitions[1].laggedAccounts, 200);
  assert.equal(report.unit, 'consented_account');
  assert.equal(report.revenue.status, 'unsupported');
  assert.equal(report.revenue.value, null);
  assert.equal(report.acquisition.accountAttributionRate, null);
});

test('pending, historical right censoring and observed no-next are separate, never abandonment', () => {
  const rows = [
    ...group('converted', 50, user => [signin(user), recipe(user)]),
    ...group('lagged', 50, user => [signin(user)]),
    ...group('censored', 50, user => [event(user, 'signin_succeeded', '2026-09-12T10:00:00Z')]),
    ...group('pending', 50, user => [event(user, 'signin_succeeded', '2026-09-14T10:00:00Z')]),
  ];
  const report = aarrrSummary(rows, '2026-09-01', '2026-09-14', '2026-09-21');
  const step = report.funnel.transitions[0];
  assert.equal(step.eligibleAccounts, 200);
  assert.equal(step.convertedAccounts, 50);
  assert.equal(step.laggedAccounts, 50);
  assert.equal(step.censoredAccounts, 50);
  assert.equal(step.pendingAccounts, 50);
  assert.equal(step.rate, 0.25);
  assert.equal(step.horizonDays, 7);
});

test('late conversions outside seven-day horizon do not become seven-day successes', () => {
  const rows = group('late', 50, user => [
    signin(user), event(user, 'recipe_created', '2026-09-10T11:00:00Z', { habitId }), practice(user, '2026-09-11'),
  ]);
  const report = summarize(rows);
  assert.equal(report.funnel.transitions[0].convertedAccounts, 0);
  assert.equal(report.funnel.transitions[0].laggedAccounts, 50);
  assert.equal(report.funnel.transitions[0].rate, 0);
});

test('duplicate retries, out-of-order arrival and conflicting UUIDs cannot inflate counts', () => {
  const rows = group('active', 100, user => [signin(user), recipe(user), practice(user)]);
  const repeated = [...rows, ...rows.map(row => structuredClone(row))].reverse();
  assert.deepEqual(summarize(repeated), summarize(rows));
  const conflict = structuredClone(rows[1]);
  conflict.record.ts = '2026-09-02T11:00:00Z';
  const report = summarize([...rows, conflict]);
  assert.equal(report.funnel.stages[0].accounts, null, 'small complement suppresses entire cumulative chain');
  assert.equal(report.funnel.stages[2].accounts, null);
});

test('account identity rotation never joins observations, absent data is unknown', () => {
  const rows = [
    ...group('old', 50, user => [signin(user)]),
    ...group('new', 50, user => [recipe(user), practice(user)]),
  ];
  assert.equal(summarize(rows).funnel.stages[2].accounts, null);
  assert.equal(summarize([]).funnel.stages[0].status, 'unknown');
  assert.equal(summarize([]).funnel.transitions[0].rate, null);
});

test('small partitions and complements do not expose subtractable counts or rates', () => {
  const rows = [
    ...group('active', 50, user => [signin(user), recipe(user), practice(user)]),
    ...group('waiting', 49, user => [signin(user)]),
  ];
  const report = summarize(rows);
  for (const stage of report.funnel.stages) assert.equal(stage.accounts, null);
  for (const step of report.funnel.transitions) {
    assert.equal(step.eligibleAccounts, null);
    assert.equal(step.convertedAccounts, null);
    assert.equal(step.rate, null);
  }
});

test('retention uses actual effective local-day practice and closes target UTC dates', () => {
  const rows = [
    ...group('retained', 50, user => [signin(user), recipe(user), practice(user),
      practice(user, '2026-09-02', 'checkin'), practice(user, '2026-09-08', 'checkin')]),
    ...group('inactive', 50, user => [signin(user), recipe(user), practice(user)]),
  ];
  const report = summarize(rows);
  const cohort = report.retention.cohorts.find(value => value.cohortDay === '2026-09-01');
  assert.equal(cohort.accounts, 100);
  assert.equal(cohort.d1.rate, 0.5);
  assert.equal(cohort.d7.rate, 0.5);
  assert.equal(cohort.d30.status, 'pending');
  assert.equal(cohort.d30.rate, null);
  const undo = group('retained', 50, user =>
    [event(user, 'checkin', '2026-09-08T15:00:00Z', { habitId, localDay: '2026-09-08', result: 'undo' })]);
  assert.equal(summarize([...rows, ...undo]).retention.cohorts[0].d7.practicingAccounts, 0);
  assert.equal(aarrrSummary(rows, '2026-09-01', '2026-09-01', '2026-09-02').retention.cohorts[0].d1.status, 'pending');
});

test('referral initiation, link opening and acceptance are not delivery or referred activation', () => {
  const rows = group('referral', 50, user => [
    event(user, 'share_initiated', '2026-09-01T10:00:00Z', { channel: 'link' }),
    event(user, 'invite_link_open', '2026-09-01T11:00:00Z', { channel: 'website', platform: 'web', measurementSource: 'website_receipt' }),
    event(user, 'invite_accepted', '2026-09-01T12:00:00Z', { channel: 'invite' }),
  ]);
  const report = summarize(rows);
  assert.equal(report.referral.initiated.accounts, 50);
  assert.equal(report.referral.linkOpened.accounts, 50);
  assert.equal(report.referral.accepted.accounts, 50);
  assert.equal(report.referral.sent.status, 'unsupported');
  assert.equal(report.referral.referredActivation.status, 'unsupported');
});

test('invalid or reversed date windows fail explicitly', () => {
  for (const args of [
    ['invalid', '2026-09-14', '2026-09-15'],
    ['2026-09-14', '2026-09-01', '2026-09-15'],
    ['2026-09-01', '2026-09-15', '2026-09-15'],
  ]) assert.throws(() => aarrrSummary([], ...args), /window/i);
});

test('seven-day deadline respects microseconds and observation cutoff equality', () => {
  const rows = [
    ...group('inside', 50, user => [
      event(user, 'signin_succeeded', '2026-09-01T10:00:00.000001Z'),
      event(user, 'recipe_created', '2026-09-08T10:00:00.000001Z', { habitId }),
    ]),
    ...group('outside', 50, user => [
      event(user, 'signin_succeeded', '2026-09-01T10:00:00.000001Z'),
      event(user, 'recipe_created', '2026-09-08T10:00:00.000002Z', { habitId }),
    ]),
  ];
  assert.equal(summarize(rows).funnel.transitions[0].rate, 0.5);
  const cutoff = group('cutoff', 50, user => [event(user, 'signin_succeeded', '2026-09-08T00:00:00Z')]);
  assert.equal(summarize(cutoff).funnel.transitions[0].pendingAccounts, 50);
});

test('local cohort date, not UTC event date, determines exact-day retention with explicit cutoff limit', () => {
  const rows = group('local', 50, user => [
    event(user, 'signin_succeeded', '2026-09-01T22:00:00Z'),
    event(user, 'recipe_created', '2026-09-01T22:30:00Z', { habitId, localDay: '2026-09-02' }),
    event(user, 'first_checkin', '2026-09-01T23:00:00Z', { habitId, localDay: '2026-09-02', result: 'didMore' }),
    event(user, 'checkin', '2026-09-02T23:00:00Z', { habitId, localDay: '2026-09-03', result: 'did' }),
  ]);
  const report = summarize(rows);
  assert.equal(report.retention.cohorts[0].cohortDay, '2026-09-02');
  assert.equal(report.retention.cohorts[0].d1.targetDay, '2026-09-03');
  assert.equal(report.retention.cohorts[0].d1.rate, 1);
  assert.match(report.retention.definition, /timezone\/offset.*unavailable/);
  assert.equal(aarrrSummary(rows, '2026-09-01', '2026-09-02', '2026-09-03')
    .retention.cohorts[0].d1.status, 'pending');
});

test('missing saved metadata, click proxies and reserved purchase events cannot create activation or revenue', () => {
  const rows = group('proxies', 50, user => [
    signin(user),
    event(user, 'recipe_created', '2026-09-01T11:00:00Z'),
    event(user, 'first_checkin', '2026-09-01T12:00:00Z', { result: 'did', localDay: '2026-09-01' }),
    event(user, 'download_click', '2026-09-01T13:00:00Z'),
    event(user, 'purchase', '2026-09-01T14:00:00Z'),
  ]);
  const report = summarize(rows);
  assert.deepEqual(report.funnel.stages.map(stage => stage.accounts), [50, null, null]);
  assert.equal(report.retention.cohorts.length, 0);
  assert.equal(report.revenue.status, 'unsupported');
  assert.equal(report.revenue.value, null);
});
