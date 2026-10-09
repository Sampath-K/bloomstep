import test from 'node:test';
import assert from 'node:assert/strict';
import { aarrrPanels } from '../aarrr-panels.mjs';
import { aarrrSummary } from '../../api/src/aarrr.mjs';

const empty = () => aarrrSummary([], '2026-09-01', '2026-09-07', '2026-09-08');
test('empty overview labels unknown and unsupported, never fabricated revenue or conversions', () => {
  const panels = aarrrPanels(empty());
  assert.equal(panels.overview.length, 5);
  assert.match(panels.overview[1].value, /Unknown/);
  assert.match(panels.overview[4].value, /Not implemented/);
  assert.match(panels.details.map(panel => panel.definition).join(' '), /never abandonment/);
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
