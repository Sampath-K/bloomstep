import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createAarrrFixture } from './support/aarrr-fixture.mjs';
import { aarrrPanels } from '../../site/aarrr-panels.mjs';

test('real HTTP sync -> restartable disk -> admin report -> renderer projection excludes deleted owners', async () => {
  const fixture = await createAarrrFixture();
  try {
    assert.equal((await fetch(fixture.url + '/healthz')).status, 200);
    assert.equal((await fetch(fixture.url + '/api/team/metrics?days=14')).status, 401);
    let result = await fixture.request('/api/team/metrics?days=14');
    assert.equal(result.status, 200);
    assert.equal((await result.json()).dashboards.aarrr.funnel.stages[0].status, 'unknown');
    await fixture.seed();
    const { token, payload } = fixture.subjects[0];
    assert.equal((await fixture.request('/api/team/metrics?days=14', token)).status, 403);
    assert.equal((await fixture.request('/api/sync', token, 'POST', payload)).status, 200, 'retry is idempotent');
    await fixture.restartStore();
    const persisted = JSON.parse(await readFile(fixture.databasePath, 'utf8'));
    const disk = JSON.stringify(persisted);
    assert.match(disk, /first_checkin/);
    assert.doesNotMatch(disk, /Bearer|synthetic-admin/);
    result = await fixture.request('/api/team/metrics?days=14');
    assert.equal(result.status, 200);
    const data = await result.json(), report = data.dashboards.aarrr;
    assert.deepEqual(report.funnel.stages.map(stage => stage.accounts), [150, 100, 50]);
    assert.equal(report.funnel.transitions[0].rate, 100 / 150);
    assert.equal(report.funnel.transitions[1].rate, 0.5);
    assert.equal(report.funnel.transitions[1].laggedAccounts, 50);
    assert.equal(report.retention.cohorts[0].d7.rate, 1);
    assert.equal(report.retention.cohorts[0].d30.status, 'pending');
    assert.equal(report.revenue.value, null);
    assert.equal(aarrrPanels(report).overview[1].value, '50.0%');
    assert.equal(data.dailySnapshots.days.at(-1).status, 'unavailable', 'no worker snapshot substituted');
    for (const { token } of fixture.subjects.slice(0, 50)) {
      assert.equal((await fixture.request('/api/account', token, 'DELETE')).status, 204);
    }
    await fixture.restartStore();
    result = await fixture.request('/api/team/metrics?days=14');
    assert.equal(result.status, 200);
    const deletedReport = (await result.json()).dashboards.aarrr;
    assert.deepEqual(deletedReport.funnel.stages.map(stage => stage.accounts), [100, 50, null]);
    assert.equal(deletedReport.retention.cohorts.length, 0);
    fixture.failPipeline(true);
    assert.equal((await fixture.request('/api/team/metrics?days=14')).status, 503);
  } finally { await fixture.close(); }
});
