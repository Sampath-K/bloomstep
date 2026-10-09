import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createAarrrFixture } from './support/aarrr-fixture.mjs';
import { websitePanels } from '../../site/website-panels.mjs';

test('real collector and account sync persist separately; acquisition margins do not change account denominators', async () => {
  const fixture = await createAarrrFixture();
  try {
    await fixture.seed();
    const touch = { source: 'search', referrerDomain: 'google.com', campaignSource: 'newsletter',
      campaignMedium: 'email', campaignName: 'launch' };
    assert.equal(await fixture.seedWebsite({ firstTouch: touch, lastTouch: touch }), 150);
    await fixture.restartStore();
    const disk = JSON.parse(await readFile(fixture.databasePath, 'utf8'));
    assert.equal(disk.documents.filter(row => row.type === 'website_daily').reduce((sum, row) => sum + row.accepted, 0), 150);
    const webResponse = await fixture.request('/api/team/website?days=7');
    assert.equal(webResponse.status, 200);
    const web = await webResponse.json();
    assert.deepEqual(web.stages, { landing_view: 50, primary_cta_click: 50, download_click: 50 });
    assert.equal(web.acquisition.scope, 'consented_page_epoch');
    for (const touch of ['firstTouch', 'lastTouch']) {
      for (const stage of ['landing_view', 'primary_cta_click', 'download_click']) {
        assert.equal(web.acquisition[touch][stage].source.search, 50);
        assert.equal(web.acquisition[touch][stage].referrerDomain['google.com'], 50);
        assert.equal(web.acquisition[touch][stage].campaignSource.newsletter, 50);
        assert.equal(web.acquisition[touch][stage].campaignMedium.email, 50);
        assert.equal(web.acquisition[touch][stage].campaignName.launch, 50);
      }
    }
    const panels = websitePanels(web);
    assert.equal(panels.find(panel => panel.title.startsWith('First touch')).rows
      .find(row => row.label === 'Landing views · source · search').value, '50 events');
    const report = (await (await fixture.request('/api/team/metrics?days=14')).json()).dashboards.aarrr;
    assert.deepEqual(report.funnel.stages.map(stage => stage.accounts), [150, 100, 50]);
    assert.equal(report.funnel.transitions[1].eligibleAccounts, 100);
    assert.equal(report.acquisition.accountAttributionRate, null);
    assert.equal(report.revenue.value, null);
  } finally { await fixture.close(); }
});
