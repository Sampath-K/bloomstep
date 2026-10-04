import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { approvedConnection, formatMetric, replyAttempt, metricPanels, tokenHeaders, dashboardPanels, snapshotPanels } from '../site/console.mjs';
import { dashboardSummaries } from '../api/src/dashboards.mjs';

test('production SWA deployment follows main and serializes the one shared environment', () => {
  const workflow = readFileSync(new URL('../.github/workflows/azure.yml', import.meta.url), 'utf8');
  assert.match(workflow, /branches:\s*\[main\]/);
  assert.match(workflow, /production_branch:\s*main/);
  assert.match(workflow, /group:\s*bloomstep-production-deployment/);
  assert.match(workflow, /cancel-in-progress:\s*false/);
});

test('operator renders persisted latest-day panels and unavailable history separately, never window sums', () => {
  const record = { dashboards: dashboardSummaries([], '2026-08-31', '2026-08-31', '2026-09-01') };
  record.dashboards.reminderHealth.sentUsers = 77;
  const series = { source: 'persisted_daily_worker', startDay: '2026-08-30', endDay: '2026-08-31', definition: 'Never sum daily unique users or medians.',
    days: [{ day: '2026-08-30', status: 'unavailable', reason: 'not_generated', record: null },
      { day: '2026-08-31', status: 'available', generatedAt: '2026-09-01T12:00:00.000Z', registryVersion: 1, record }] };
  const panels = snapshotPanels({ dailySnapshots: series });
  assert.equal(panels.length, 5);
  assert.match(panels[0].title, /Persisted daily worker/);
  assert.match(panels[0].rows[0].value, /Unavailable.*not_generated/);
  assert.match(panels[0].rows[1].value, /2026-09-01T12:00/);
  assert.equal(panels[4].rows[0].value, '77');
  series.days[1] = { day: '2026-08-31', status: 'unavailable', reason: 'stale_generation', record: null };
  assert.equal(snapshotPanels({ dailySnapshots: series }).length, 1);
  assert.throws(() => snapshotPanels({}));
});

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
