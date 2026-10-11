import test from 'node:test';
import assert from 'node:assert/strict';
import { aarrrPanels, loadAarrr } from '../aarrr-panels.mjs';
const empty = () => ({
  schemaVersion: 1, unit: 'consented_account', minimumContributors: 50,
  startDay: '2026-09-01', endDay: '2026-09-07', observedThrough: '2026-09-08',
  coverage: 'Partial observations, not a population watermark.',
  acquisition: { status: 'unsupported', accountAttributionRate: null, definition: 'Separate anonymous event counts.' },
  funnel: {
    stages: ['signin_succeeded', 'recipe_created', 'first_checkin'].map(name => ({ name, accounts: null, status: 'unknown' })),
    transitions: [['signin_succeeded', 'recipe_created'], ['recipe_created', 'first_checkin']].map(([from, to]) => ({
      from, to, horizonDays: 7, eligibleAccounts: null, convertedAccounts: null, laggedAccounts: null,
      pendingAccounts: null, censoredAccounts: null, rate: null, status: 'unknown',
    })),
    definition: 'Ordered account observations; missing stages are never abandonment.',
  },
  retention: { cohorts: [], cohortStartDay: '2026-08-02', definition: 'Effective exact local-day practice.' },
  referral: {
    initiated: { accounts: null, status: 'unknown' }, linkOpened: { accounts: null, status: 'unknown' },
    accepted: { accounts: null, status: 'unknown' }, sent: { accounts: null, status: 'unsupported' },
    referredActivation: { accounts: null, status: 'unsupported' }, definition: 'Distinct observations, not one linked funnel.',
  },
  revenue: { status: 'unsupported', value: null, definition: 'No payment evidence.' },
  experiment: { eligible: false, reason: 'No verified exposures; historical experiment OFF.' },
});
test('empty overview labels unknown and unsupported, never fabricated revenue or conversions', () => {
  const panels = aarrrPanels(empty());
  assert.equal(panels.overview.length, 5);
  assert.match(panels.overview[1].value, /Unknown/);
  assert.match(panels.overview[4].value, /Not implemented/);
  assert.match(panels.details.map(panel => panel.definition).join(' '), /never abandonment/);
});

test('shared production loader clears stale output on invalid input or failed/partial pipeline', async () => {
  let cleared = 0;
  const output = { replaceChildren() { cleared++; } };
  await assert.rejects(loadAarrr(output, async () => { throw Error('HTTP 503'); }, 7), /503/);
  assert.equal(cleared, 2);
  await assert.rejects(loadAarrr(output, async () => ({ dashboards: {} }), 7), /Invalid/);
  await assert.rejects(loadAarrr(output, async () => { throw Error('must not request'); }, 31), /1-30/);
});
test('incomplete, negative, stale-shape and impossible rate responses fail closed', () => {
  for (const mutate of [
    value => { delete value.funnel; },
    value => { value.unit = 'visitor'; },
    value => { value.funnel.transitions[0].rate = 1.1; },
    value => { value.funnel.stages[0].accounts = 49; },
    value => { value.revenue.value = 0; },
    value => { value.endDay = value.observedThrough; },
    value => { value.referral.sent.status = 'measured'; },
    value => { value.retention.cohorts = [{ cohortDay: 'bad' }]; },
  ]) {
    const value = empty(); mutate(value);
    assert.throws(() => aarrrPanels(value), /Invalid|Incomplete/);
  }
});

test('measured transition partitions must sum to eligible denominator and preserve seven-day rate', () => {
  const value = empty();
  value.funnel.stages = [
    { name: 'signin_succeeded', accounts: 150, status: 'measured' },
    { name: 'recipe_created', accounts: 100, status: 'measured' },
    { name: 'first_checkin', accounts: 50, status: 'measured' },
  ];
  value.funnel.transitions = [
    { from: 'signin_succeeded', to: 'recipe_created', horizonDays: 7, eligibleAccounts: 150,
      convertedAccounts: 100, laggedAccounts: 50, pendingAccounts: 0, censoredAccounts: 0, rate: 2 / 3, status: 'measured' },
    { from: 'recipe_created', to: 'first_checkin', horizonDays: 7, eligibleAccounts: 100,
      convertedAccounts: 50, laggedAccounts: 50, pendingAccounts: 0, censoredAccounts: 0, rate: 0.5, status: 'measured' },
  ];
  assert.equal(aarrrPanels(value).overview[1].value, '50.0%');
  value.funnel.transitions[1].laggedAccounts = 49;
  assert.throws(() => aarrrPanels(value), /Invalid/);
  value.funnel.transitions[1].laggedAccounts = 50;
  value.funnel.transitions[1].rate = 1;
  assert.throws(() => aarrrPanels(value), /Invalid/);
});
