import test from 'node:test';
import assert from 'node:assert/strict';
import { reminderPreferencePanels } from '../site/reminder-panels.mjs';
import { reminderPreferenceCohorts } from '../api/src/reminder-cohorts.mjs';

const empty = () => ({ reminderPreferenceCohorts: reminderPreferenceCohorts([], '2026-08-31', '2026-08-31', '2026-09-02T00:00:00.000Z') });

test('private preference panel makes narrower coverage and unknown/suppressed outcomes explicit', () => {
  const panel = reminderPreferencePanels(empty())[0];
  assert.match(panel.title, /Observed app reminder preference/);
  assert.match(panel.definition, /not OS permission\/delivery/);
  assert.match(panel.definition, /Fresh explicit versioned consent/);
  assert.match(panel.rows.find(row => row.label.includes('fraction')).value, /Unavailable.*cohort_below_50/);
  assert.match(panel.rows.find(row => row.label.includes('Original')).value, /Unavailable.*not_observable/);
  assert.equal(panel.rows.some(row => /target met|passed|100%/.test(row.value)), false);
});

test('panel rejects missing schema, accidental unknown defaults and contradictory observed results', () => {
  assert.throws(() => reminderPreferencePanels({}));
  for (const mutate of [
    value => value.schemaVersion = 2,
    value => value.source = 'windows_permission',
    value => value.horizonDays = 7,
    value => value.reason = 'default_success',
    value => value.matureAccounts = 0,
    value => value.disabledAccounts = 1,
    value => value.observedDisableFraction = 0,
    value => value.unknownFollowupAccounts = -1,
    value => value.originalGoalReason = null,
  ]) {
    const data = empty();
    mutate(data.reminderPreferenceCohorts);
    assert.throws(() => reminderPreferencePanels(data));
  }
});

test('available narrower fraction labels no goal comparison and validates its denominator', () => {
  const data = empty();
  Object.assign(data.reminderPreferenceCohorts, {
    matureAccounts: 100, disabledAccounts: 50, confirmedEnabledAccounts: 50,
    unknownFollowupAccounts: null, reason: null, observedDisableFraction: .5,
  });
  const panel = reminderPreferencePanels(data)[0];
  assert.match(panel.rows.find(row => row.label.includes('fraction')).value, /50%.*50.*100.*no original-goal pass/);
  data.reminderPreferenceCohorts.observedDisableFraction = .1;
  assert.throws(() => reminderPreferencePanels(data));
});
