import test from 'node:test';
import assert from 'node:assert/strict';
import { approvedConnection, formatMetric, replyAttempt, metricPanels, tokenHeaders, dashboardPanels } from '../site/console.mjs';
import { dashboardSummaries } from '../api/src/dashboards.mjs';

test('typed dashboards surface unavailable cohorts and completed-day definitions', () => {
  const data = { dashboards: dashboardSummaries([], '2026-09-01', '2026-09-01', '2026-09-02') };
  const panels = dashboardPanels(data);
  assert.equal(panels.length, 4);
  assert.equal(panels[0].rows.some(row => row.value === 'Unavailable / suppressed'), true);
  assert.equal(panels[1].rows[0].value, 'No observed eligible cohorts');
  assert.match(panels[2].definition, /UTC/);
  assert.match(panels[3].definition, /not OS delivery/);
  assert.throws(() => dashboardPanels({}));
  data.dashboards.funnel.sameDayActivation.rate = 2;
  assert.throws(() => dashboardPanels(data));
});

test('operator never sends bearer tokens to a different origin', () => {
  assert.equal(approvedConnection('https://example.test', 'aa.bb.cc', 'https://example.test').origin, 'https://example.test');
  for (const origin of ['https://other.test', 'http://example.test', 'https://example.test/path', 'https://user@example.test']) {
    assert.throws(() => approvedConnection(origin, 'aa.bb.cc', 'https://example.test'));
  }
});
test('real broker token uses a dedicated header, not the SWA-reserved Authorization header', () => {
  const headers = tokenHeaders('synthetic.token.fixture');
  assert.equal(headers['X-Bloomstep-Authorization'], 'Bearer synthetic.token.fixture');
  assert.equal(Object.hasOwn(headers, 'Authorization'), false);
});
test('unknown or suppressed counts are never rendered as zeros', () => {
  assert.equal(formatMetric(null), 'Unavailable / suppressed');
  assert.equal(formatMetric(0), '0');
  assert.throws(() => formatMetric(undefined));
  assert.throws(() => formatMetric(-1));
  assert.throws(() => metricPanels({ daily: [], minimumCohort: 50, limitations: [] }));
});
test('reply retry IDs persist only for the same payload', () => {
  const payload = { id: 'synthetic', status: 'planned', reply: 'Synthetic test' };
  const first = replyAttempt(null, payload, () => 'first');
  assert.equal(replyAttempt(first, payload, () => 'second').requestId, 'first');
  assert.equal(replyAttempt(first, { ...payload, status: 'shipped' }, () => 'second').requestId, 'second');
});
