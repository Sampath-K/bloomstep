import puppeteer from 'puppeteer-core';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createAarrrFixture } from '../api/test/support/aarrr-fixture.mjs';

const output = process.env.EVIDENCE_DIR;
if (!output) throw Error('EVIDENCE_DIR required for source-bound isolated screenshot receipts.');
await mkdir(output, { recursive: true });
const fixture = await createAarrrFixture();
let browser;
const checks = [];
try {
  assert.equal((await fetch(fixture.url + '/healthz')).status, 200);
  browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH ??
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', headless: true });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.setViewport({ width: 1440, height: 1050, deviceScaleFactor: 1 });
  await page.goto(fixture.url + '/console.html', { waitUntil: 'networkidle0' });
  assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'dark');
  assert.match(await page.$eval('#aarrr-report', node => node.textContent), /No private measurements loaded/);
  const load = async () => page.evaluate(async token => {
    const response = await fetch('/api/team/metrics?days=14', { headers: { 'X-Bloomstep-Authorization': `Bearer ${token}` } });
    if (!response.ok) throw Error(`Fixture pipeline ${response.status}`);
    const data = await response.json();
    const { renderAarrr } = await import('/aarrr-panels.mjs');
    renderAarrr(document.getElementById('aarrr-report'), data.dashboards.aarrr, { fixture: true });
    return data.dashboards.aarrr;
  }, fixture.adminToken);
  await load();
  assert.match(await page.$eval('#aarrr-report', node => node.textContent), /Unknown \/ absent observations/);
  await page.screenshot({ path: join(output, 'aarrr-empty.png'), fullPage: true });
  checks.push('Real authenticated HTTP empty report renders unknown, unsupported revenue; private dark default');
  await fixture.seed();
  assert.equal((await fixture.request('/api/sync', fixture.subjects[0].token, 'POST', fixture.subjects[0].payload)).status, 200);
  await fixture.restartStore();
  const report = await load();
  assert.deepEqual(report.funnel.stages.map(stage => stage.accounts), [150, 100, 50]);
  assert.equal(report.funnel.transitions[1].rate, 0.5);
  const values = await page.$$eval('.aarrr-stage strong', nodes => nodes.map(node => node.textContent));
  assert.deepEqual(values, ['150', '100', '50']);
  assert.equal(await page.$eval('.aarrr-kpi:nth-child(2) .aarrr-value', node => node.textContent), '50.0%');
  assert.equal(await page.$eval('.aarrr-kpi:nth-child(3) .aarrr-value', node => node.textContent), '100.0%');
  assert.match(await page.$eval('#aarrr-report', node => node.textContent), /ISOLATED SYNTHETIC FIXTURE/);
  await page.screenshot({ path: join(output, 'aarrr-desktop.png'), fullPage: true });
  const summary = await page.$('.aarrr-detail summary');
  await summary.focus(); await page.keyboard.press('Space');
  assert.equal(await page.$eval('.aarrr-detail', node => node.open), true);
  assert.match(await page.$eval('.aarrr-detail', node => node.textContent), /50.0% \(50 \/ 100 accounts\)/);
  assert.match(await page.$eval('.aarrr-detail', node => node.textContent), /never abandonment/);
  await page.screenshot({ path: join(output, 'aarrr-drilldown.png'), fullPage: true });
  checks.push('Real HTTP sync + exact retry + disk restart -> report 150/100/50 -> rendered 50.0% activation, 100.0% D7; keyboard Space opens definition/denominators');
  for (const width of [390, 320]) {
    await page.setViewport({ width, height: 900, deviceScaleFactor: 1 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `No ${width}px overflow`);
    await page.screenshot({ path: join(output, `aarrr-mobile-${width}.png`), fullPage: true });
  }
  await page.setViewport({ width: 1280, height: 900, deviceScaleFactor: 1 });
  await page.goto(fixture.url + '/console.html?scoutTheme=light', { waitUntil: 'networkidle0' });
  await load();
  assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'light');
  await page.screenshot({ path: join(output, 'aarrr-light.png'), fullPage: true });
  checks.push('390/320px no horizontal overflow; explicit light theme preserved');
  fixture.failPipeline(true);
  assert.equal((await fixture.request('/api/team/metrics?days=14')).status, 503);
  // Exercise the production console's actual failure/clear path without bypassing operator auth.
  await page.click('#metrics');
  await page.waitForFunction(() => document.getElementById('admin-status').textContent.includes('Measurement unavailable'));
  assert.equal(await page.$eval('#aarrr-report', node => node.children.length), 0);
  assert.match(await page.$eval('#admin-status', node => node.textContent), /No prior or substitute counts/);
  await page.screenshot({ path: join(output, 'aarrr-error.png'), fullPage: true });
  checks.push('Real pipeline returns 503; actual production Load button without configured operator identity clears old fixture report and labels failure (no auth bypass)');
  assert.deepEqual(errors, []);
  const sources = {};
  for (const path of ['api/src/aarrr.mjs', 'api/src/backend.mjs', 'site/aarrr-panels.mjs',
    'site/console.mjs', 'site/console.html', 'site/console.css', 'api/test/support/aarrr-fixture.mjs', 'site/verify-aarrr.mjs']) {
    sources[path] = createHash('sha256').update(await readFile(new URL(`../${path}`, import.meta.url))).digest('hex');
  }
  await writeFile(join(output, 'aarrr-receipt.json'), JSON.stringify({
    schemaVersion: 1, isolatedSynthetic: true, generatedAt: new Date().toISOString(), sources, checks,
    oracle: { stages: [150, 100, 50], activationRate: 0.5, d7Rate: 1, revenue: null },
    limitations: ['No native installation or live customers exercised', 'Operator authentication is not bypassed; populated preview uses production renderer with isolated authenticated handler response',
      'No production synthetic data written; disposable local disk removed after run', 'Acquisition foundation acceptance is a separate composed check'],
  }, null, 2));
  console.log('AARRR HTTP/disk/render acceptance passed; isolated screenshots and source receipt written.');
} finally {
  await browser?.close();
  await fixture.close();
}
