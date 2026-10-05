import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { approvedConnection, formatMetric, replyAttempt, metricPanels, tokenHeaders, dashboardPanels, snapshotPanels, goalPanels, supportPanels } from '../site/console.mjs';
import { dashboardSummaries } from '../api/src/dashboards.mjs';
import { goalMetrics } from '../api/src/goals.mjs';
import { supportMetrics } from '../api/src/support.mjs';

test('support panel labels server facts and unanswered denominators without a fake SLA pass', () => {
  const data = { supportMetrics: supportMetrics([], '2026-08-31', '2026-08-31', '2026-09-03T00:00:00.000Z') };
  const panels = supportPanels(data);
  assert.equal(panels.length, 1);
  assert.match(panels[0].definition, /not product-event analytics/);
  assert.match(panels[0].definition, /not an all-feedback census/);
  assert.match(panels[0].rows.find(row => row.label.includes('Business-day')).value, /2.*Unavailable.*calendar_not_configured/);
  assert.match(panels[0].rows.find(row => row.label.includes('Observed mature')).value, /48.*Unavailable.*cohort_below_50/);
  assert.match(panels[0].rows.find(row => row.label.includes('Median')).value, /Unavailable.*cohort_below_50/);
  assert.equal(panels[0].rows.some(row => /target met|100%|passed/i.test(row.value)), false);
  assert.throws(() => supportPanels({}));
  for (const corrupt of [
    value => value.schemaVersion = 2,
    value => value.source = 'client_reply_prefixes',
    value => value.firstResponses.medianHours = 0,
    value => value.lowRatings48h.thresholdHours = 24,
    value => value.lowRatings48h.complianceFraction = 1.1,
    value => value.businessDays.value = 0,
    value => value.coverage.legacyRecords = 1,
    value => value.lowRatings48h.overdueUnanswered = -1,
    value => value.firstResponses.reason = 'unknown_default',
  ]) {
    const broken = structuredClone(data);
    corrupt(broken.supportMetrics);
    assert.throws(() => supportPanels(broken));
  }
  const source = readFileSync(new URL('../site/console.mjs', import.meta.url), 'utf8');
  assert.match(source, /\.\.\.supportPanels\(data\)/);
});

test('support panel renders actual mature denominators and suppressed subsets without replacing the original goals', () => {
  const rows = Array.from({ length: 100 }, (_, index) => ({
    userId: (index + 1).toString(16).padStart(64, '0'),
    id: `voice:00000000-0000-4000-8000-${(index + 1).toString(16).padStart(12, '0')}`,
    kind: 'Rating', rating: 2, hasResponses: index < 50,
    support: { schemaVersion: 1, receivedAt: '2026-08-31T12:00:00.000Z',
      firstRespondedAt: index < 50 ? '2026-09-02T12:00:00.000Z' : null },
  }));
  const data = { supportMetrics: supportMetrics(rows, '2026-08-31', '2026-08-31', '2026-09-03T00:00:00.000Z') };
  const panel = supportPanels(data)[0];
  assert.match(panel.rows.find(row => row.label.includes('Observed mature')).value, /50% observed.*no numeric compliance target.*50 timely \/ 100 mature/);
  assert.equal(panel.rows.find(row => row.label.includes('Overdue unanswered')).value, '50');
  assert.equal(panel.rows.find(row => row.label.includes('Immature')).value, 'Unavailable / suppressed');
  assert.match(panel.rows.find(row => row.label.includes('Median')).value, /48 hours.*descriptive only/);
  assert.equal(panel.rows.some(row => /target met|passed/i.test(row.value)), false);
  data.supportMetrics.lowRatings48h.complianceFraction = 1;
  assert.throws(() => supportPanels(data));
});

test('goal UI distinguishes target, unavailable actual, denominator, window and coverage without proxy success', () => {
  const data = { goalMetrics: goalMetrics([], '2026-08-31', '2026-08-31', '2026-09-01') };
  const panels = goalPanels(data);
  assert.equal(panels.length, 1);
  assert.match(panels[0].definition, /opt-in/);
  assert.match(panels[0].definition, /2026-08-31/);
  assert.match(panels[0].rows.find(row => row.label.startsWith('D7')).value, /40%.*Unavailable.*cohort_below_50/);
  assert.match(panels[0].rows.find(row => row.label.startsWith('Crash-free')).value, /99.5%.*not_observable/);
  assert.match(panels[0].rows.find(row => row.label.includes('at30')).value, /Tracking only/);
  assert.throws(() => goalPanels({}));
  data.goalMetrics.goals[0].value = 2;
  assert.throws(() => goalPanels(data));
  data.goalMetrics.goals[0].value = null;
  data.goalMetrics.schemaVersion = 99;
  assert.throws(() => goalPanels(data));
});

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

test('worker schedule card shows delayed generation separately from missing/stale snapshots', () => {
  const data = { dailySnapshots: { source: 'persisted_daily_worker', definition: 'No fallback.',
    startDay: '2026-08-31', endDay: '2026-08-31',
    schedule: { cron: '20 2 * * *', latestDueAt: '2026-09-01T02:20:00.000Z', latestTickDue: true,
      backfillMaxDays: 30, definition: 'Generation time is not a scheduled invocation.' },
    days: [{ day: '2026-08-31', status: 'unavailable', reason: 'stale_generation', record: null,
      scheduledAt: '2026-09-01T02:20:00.000Z', generationOffsetSeconds: null }] } };
  const panels = snapshotPanels(data);
  assert.match(panels[0].rows[0].value, /Due.*02:20/);
  assert.match(panels[0].rows[1].value, /stale_generation.*no raw-data fallback/);
  assert.match(panels[0].definition, /30 completed UTC days/);
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
