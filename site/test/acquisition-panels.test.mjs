import test from 'node:test';
import assert from 'node:assert/strict';
import { acquisitionPanels } from '../acquisition-panels.mjs';
import { loadWebsite, websitePanels } from '../website-panels.mjs';

function fixture() {
  const touch = Object.fromEntries(['landing_view', 'primary_cta_click', 'download_click'].map(stage => [stage, {
    source: { search: 50, unknown: null }, referrerDomain: { 'google.com': 50, unknown: null },
    campaignSource: { newsletter: null }, campaignMedium: { email: null }, campaignName: { launch: null },
  }]));
  return { schemaVersion: 1, scope: 'consented_page_epoch', firstTouch: structuredClone(touch),
    lastTouch: structuredClone(touch), definition: 'Page consent epoch margins; no cross-visit identity.' };
}
test('first/last touch marginal drilldowns label missing cells unknown and never calculate account conversion', () => {
  const panels = acquisitionPanels(fixture());
  assert.equal(panels.length, 2);
  assert.match(panels[0].title, /First touch/);
  assert.match(panels[1].title, /Last touch/);
  assert.equal(panels[0].rows.find(row => row.label === 'Landing views · source · search').value, '50 events');
  assert.equal(panels[0].rows.find(row => row.label === 'Landing views · source · unavailable labels').value,
    'Unknown / absent or privacy suppressed (unknown)');
  assert.match(panels[0].definition, /not people/);
});
test('shared website loader clears stale data on pipeline errors and malformed responses', async () => {
  let cleared = 0;
  const output = { replaceChildren() { cleared++; } };
  await assert.rejects(loadWebsite(output, async () => { throw Error('HTTP 429'); }, 7), /429/);
  assert.equal(cleared, 2);
  await assert.rejects(loadWebsite(output, async () => ({}), 7), /Incomplete/);
  await assert.rejects(loadWebsite(output, async () => { throw Error('must not request'); }, 0), /1-30/);
});
test('legacy report enrichment is explicitly unavailable', () => {
  assert.match(acquisitionPanels(undefined)[0].rows[0].value, /Unavailable/);
});
test('partial dimensions, malformed scope and unsuppressed small cells fail closed', () => {
  for (const mutate of [
    value => { value.scope = 'visitor'; },
    value => { delete value.lastTouch.download_click; },
    value => { value.firstTouch.landing_view.source.search = 49; },
    value => { value.firstTouch.landing_view.campaignName = {}; },
    value => { value.firstTouch.landing_view.campaignName = { 'https://private.invalid/path?customer=alice': 50 }; },
    value => { value.firstTouch.landing_view.campaignName = { 'private-unbounded': 50 }; },
  ]) {
    const value = fixture(); mutate(value);
    assert.throws(() => acquisitionPanels(value), /Invalid/);
  }
});

test('launch overview publishes supported event denominators/window, never visits or installed people', () => {
  const data = { schemaVersion: 1, channel: 'web', synthetic: false, startDay: '2026-09-01', endDay: '2026-09-07',
    definition: 'Anonymous event counts, not unique visitors.',
    stages: { landing_view: 100, primary_cta_click: 50, download_click: 50 },
    sources: { search: 100, referral: null, direct: null, campaign: null, unknown: null },
    architectures: { arm64: null, x64: null, unknown: 50 },
    steps: [{ from: 'landing_view', to: 'primary_cta_click', rate: 0.5, reason: null },
      { from: 'primary_cta_click', to: 'download_click', rate: 1, reason: null }],
    linked: { minimumContributors: 50, definition: 'Voluntary linked receipts.', stages: { landing_view: null },
      steps: [{ from: 'landing_view', to: 'download_click', rate: null }] } };
  const panel = websitePanels(data)[0];
  assert.match(panel.title, /Launch decision/);
  assert.match(panel.rows.find(row => row.label.includes('landing_view →')).value, /50.0% \(50 \/ 100 events\)/);
  assert.match(panel.definition, /2026-09-01 through 2026-09-07/);
  assert.match(panel.definition, /Freshness.*unknown/);
  for (const mutate of [
    value => { value.synthetic = true; },
    value => { delete value.stages.download_click; },
    value => { value.startDay = 'yesterday'; },
    value => { value.endDay = '2026-08-01'; },
    value => { value.steps = []; },
    value => { value.stages.download_click = 0; },
    value => { value.sources.private = 50; },
    value => { value.linked.steps[0].rate = 1; },
  ]) {
    const broken = structuredClone(data); mutate(broken);
    assert.throws(() => websitePanels(broken), /Invalid|Incomplete/);
  }
  data.stages.download_click = 100;
  data.steps[1].rate = 2;
  assert.match(websitePanels(data)[0].rows.find(row => row.label.includes('primary_cta_click →')).value,
    /200.0% \(100 \/ 50 events\)/, 'event ratios above100 must not be clamped into person conversion');
  for (const name of Object.keys(data.stages)) data.stages[name] = null;
  data.steps.forEach(step => { step.rate = null; step.reason = 'events_below_50'; });
  assert.match(websitePanels(data)[0].rows[0].value, /Unknown/);
  assert.match(websitePanels(data)[0].rows.find(row => row.label.includes('landing_view →')).value, /no conversion claim/);
});
