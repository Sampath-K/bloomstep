import test from 'node:test';
import assert from 'node:assert/strict';
import { acquisitionPanels } from '../acquisition-panels.mjs';
import { loadWebsite } from '../website-panels.mjs';

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
