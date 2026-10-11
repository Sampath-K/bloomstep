import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import puppeteer from 'puppeteer-core';
import { createLocalTestServer } from '../api/test/support/local_api_server.mjs';

const out = resolve(process.env.EVIDENCE_DIR ?? join(tmpdir(), 'bloomstep-public-launch-evidence'));
await mkdir(out, { recursive: true });
const temp = await mkdtemp(join(tmpdir(), 'bloomstep-it-launch-'));
const databasePath = join(temp, 'website.json');
const errors = [], requests = [], screenshots = {};
let server, browser;
try {
  server = await createLocalTestServer({ databasePath, key: randomBytes(32), telemetry: true,
    onError: error => errors.push(error.message) });
  browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH ??
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', headless: true,
    args: ['--no-sandbox'] });
  const page = await browser.newPage();
  page.on('pageerror', error => errors.push(error.message));
  await page.setRequestInterception(true);
  page.on('request', request => {
    if (request.url().endsWith('/api/web/events')) requests.push(JSON.parse(request.postData()));
    if (new URL(request.url()).origin === server.url) void request.continue();
    else void request.abort();
  });
  await page.setViewport({ width: 1280, height: 1000, deviceScaleFactor: 1 });
  await page.goto(server.url + '/?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits',
    { waitUntil: 'networkidle0' });
  await page.$$eval('[data-download]', nodes => nodes.forEach(node =>
    node.addEventListener('click', event => event.preventDefault())));
  await page.click('[data-primary-cta="footer"]');
  assert.equal(new URL(page.url()).hash, '#download');
  await page.click('[data-universal-download] a');
  assert.equal(requests.length, 0, 'CTA and downloads do not require consent or issue observations when off');
  await page.click('#website-consent');
  await page.waitForFunction(() => document.querySelector('#website-status').textContent.includes('active'));
  await page.click('[data-primary-cta="footer"]');
  await page.click('#primary-cta');
  await page.click('[data-universal-download] a');
  await page.waitForNetworkIdle();
  assert.deepEqual(requests.map(row => row.event), ['landing_view', 'primary_cta_click', 'download_click'],
    'Footer intent enters existing bounded event funnel; hero/footer are deduplicated in this consent epoch');
  for (const row of requests) {
    assert.equal(row.attribution.firstTouch.campaignSource, 'linkedin');
    assert.equal(row.attribution.lastTouch.campaignName, 'tiny_habits');
  }
  const disk = JSON.parse(await readFile(databasePath, 'utf8'));
  const daily = disk.documents.find(row => row.type === 'website_daily');
  assert.equal(daily.accepted, 3);
  const response = await fetch(server.url + '/api/team/website?days=1',
    { headers: { 'x-bloomstep-test-admin': server.adminToken } });
  assert.equal(response.status, 200);
  const report = await response.json();
  assert.equal(report.stages.landing_view, null, 'Small cells stay suppressed; no lead count inferred');
  await page.click('#website-consent');
  const before = requests.length;
  await page.click('[data-primary-cta="footer"]');
  await page.waitForNetworkIdle();
  assert.equal(requests.length, before, 'Withdrawal stops additional intent observations');
  const shot = async (name, selector) => {
    const path = join(out, `${name}.png`);
    if (selector) await (await page.$(selector)).screenshot({ path });
    else await page.screenshot({ path, fullPage: true });
    screenshots[name] = createHash('sha256').update(await readFile(path)).digest('hex');
  };
  await shot('launch-download-desktop', '#download');
  for (const [width, js] of [[1280, true], [390, true], [320, true], [390, false]]) {
    await page.setViewport({ width, height: 1000, deviceScaleFactor: 1 });
    await page.setJavaScriptEnabled(js);
    await page.goto(server.url, { waitUntil: 'networkidle0' });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `reflow ${width} JS=${js}`);
    assert.equal(await page.$eval('#website-consent', node => node.checked), false);
    assert.match(await page.$eval('#download-prerequisites', node => node.textContent), /unsigned/);
    assert.equal(await page.$eval('[data-universal-download] a', node => new URL(node.href).hostname), 'github.com');
    assert.equal((await page.cookies()).length, 0);
    if (js) {
      assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0);
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement.className), 'skip');
      await page.keyboard.press('Enter');
      assert.equal(new URL(page.url()).hash, '#main');
      await page.$eval('#feedback-help summary', node => node.focus());
      await page.keyboard.press('Space');
      assert.equal(await page.$eval('#feedback-help', node => node.open), true);
      await page.$eval('#privacy-notice summary', node => node.focus());
      await page.keyboard.press('Space');
      assert.equal(await page.$eval('#privacy-notice', node => node.open), true);
      assert.match(await page.$eval('#privacy-notice', node => node.textContent), /Sampath Kumar's personal independent project/);
      assert.equal(await page.$eval('a[href="mailto:store-developer@outlook.com"]', node =>
        node.getBoundingClientRect().width > 0 && node.textContent === 'store-developer@outlook.com'), true);
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement.href),
        'mailto:store-developer@outlook.com', 'the public contact is reachable from the privacy notice by keyboard');
      await shot(`launch-privacy-${width}`, '#privacy-notice');
    }
    await shot(`launch-home-${width}-${js ? 'js' : 'no-js'}`);
    await shot(`launch-download-${width}-${js ? 'js' : 'no-js'}`, '#download');
  }
  assert.deepEqual(errors, []);
  const sources = {};
  for (const file of ['site/index.html', 'site/releases/index.html', 'site/customer.mjs', 'site/verify-launch.mjs', 'docs/website-launch.md']) {
    sources[file] = createHash('sha256').update(await readFile(new URL('../' + file, import.meta.url))).digest('hex');
  }
  await writeFile(join(out, 'launch-receipt.json'), JSON.stringify({ passed: true, syntheticOnly: true,
    sourceRevision: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
    sourceDirty: !!execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim(),
    actualPersistedObservations: daily.accepted, campaign: 'linkedin/social/tiny_habits',
    downloadRequestsExecuted: false, qualifiedLeads: 'unobservable', experimentsEnabled: false,
    sources, screenshots }, null, 2));
  console.log(`Public launch UX/HTTP/disk verification passed: ${out}`);
} finally {
  if (browser) await browser.close();
  if (server) await server.close();
  await rm(temp, { recursive: true, force: true });
}
