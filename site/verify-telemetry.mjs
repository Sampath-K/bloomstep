import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdtemp, readFile, writeFile, mkdir, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import puppeteer from 'puppeteer-core';
import { createLocalTestServer } from '../api/test/support/local_api_server.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
if (!process.env.EVIDENCE_DIR) throw Error('Set EVIDENCE_DIR to an owned artifact directory to retain evidence.');
const output = resolve(process.env.EVIDENCE_DIR);
await mkdir(output, { recursive: true });
const receiptPath = join(output, 'telemetry-receipt.json');
try { await access(receiptPath); throw Error('Refusing to overwrite previous evidence.'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const candidates = [process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', '/usr/bin/google-chrome'];
let executablePath;
for (const candidate of candidates.filter(Boolean)) {
  try { await access(candidate); executablePath = candidate; break; } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}
if (!executablePath) throw Error('CHROME_PATH must identify an installed trusted browser.');
const temporary = await mkdtemp(join(tmpdir(), 'bloomstep-it-telemetry-'));
let now = Date.now();
const collectorErrors = [];
const onError = error => collectorErrors.push({ code: error.code, syscall: error.syscall });
const databasePath = join(temporary, 'website.json'), key = randomBytes(32);
let server = null, browser = null;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const persisted = async () => JSON.parse(await readFile(databasePath, 'utf8')).documents;
const accepted = async (synthetic = false) => (await persisted()).find(doc => doc.type === 'website_budget' &&
  doc.userId === (synthetic ? '__website_synthetic' : '__website_counts'))?.accepted ?? 0;
const waitCount = async count => {
  for (let i = 0; i < 100; i++) {
    // Wait for transport completion before independently opening the output file.
    // Continuous disk polling races atomic replacement on Windows.
    if (httpOutcomes.filter(status => status === 202).length >= count) {
      assert.equal(await accepted(), count);
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.equal(await accepted(), count, `Collector readback failed: ${JSON.stringify(collectorErrors)}`);
};
const reports = [];
const httpOutcomes = [];
const report = async () => {
  const response = await fetch(`${server.url}/api/team/website?days=1`, {
    headers: { 'x-bloomstep-test-admin': server.adminToken },
  });
  assert.equal(response.status, 200);
  const value = await response.json();
  reports.push(value);
  return value;
};
const scenarios = [];
let cleanupVerified = false;
try {
  server = await createLocalTestServer({ databasePath, key, telemetry: true, clock: () => new Date(now), onError });
  browser = await puppeteer.launch({ executablePath, headless: true });
  assert.equal((await fetch(`${server.url}/healthz`)).status, 200);
  assert.equal((await fetch(`${server.url}/api/team/website`)).status, 401);
  const page = await browser.newPage();
  page.on('response', response => {
    if (response.url().endsWith('/api/web/events')) httpOutcomes.push(response.status());
  });
  const click = selector => page.$eval(selector, node => node.click());
  await page.setViewport({ width: 1280, height: 900 });
  await page.setRequestInterception(true);
  page.on('request', request => {
    if (new URL(request.url()).origin === server.url || request.url().startsWith('blob:')) void request.continue();
    else void request.abort();
  });
  await page.evaluateOnNewDocument(() => {
    const OriginalDate = Date;
    globalThis.__telemetryClock = null;
    globalThis.Date = class extends OriginalDate {
      constructor(...args) { super(...(args.length ? args : [globalThis.__telemetryClock ?? OriginalDate.now()])); }
      static now() { return globalThis.__telemetryClock ?? OriginalDate.now(); }
    };
  });
  const load = async search => {
    await page.goto(`${server.url}/${search}`, { waitUntil: 'domcontentloaded' });
    await page.evaluate(time => { globalThis.__telemetryClock = time; }, now);
    // Suppress file navigation only; the actual production click listener still runs.
    await page.$$eval('[data-download]', links => links.forEach(link =>
      link.addEventListener('click', event => event.preventDefault())));
  };
  await load('?utm_source=newsletter&utm_medium=email&utm_campaign=launch&private=secret');
  assert.equal(await page.$eval('#website-consent', input => input.checked), false);
  await click('#primary-cta');
  await page.$eval('[data-download="unknown"]', link => link.click());
  assert.equal(await accepted(), 0);
  await page.screenshot({ path: join(output, 'default-off.png'), fullPage: true });
  await click('#website-consent'); await waitCount(1);
  await page.$eval('#receipt-consent', input => input.click());
  assert.equal(await page.$eval('#receipt-consent', input => input.checked), true);
  const downloadSession = await page.createCDPSession();
  await downloadSession.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: temporary });
  await click('#primary-cta'); await waitCount(2);
  await page.$eval('[data-download="unknown"]', link => link.click()); await waitCount(3);
  await page.$eval('#receipt-export', button => button.click());
  assert.match(await page.$eval('#receipt-status', node => node.textContent), /Receipt export requested/);
  const exported = join(temporary, 'bloomstep-website-measurement.json');
  for (let i = 0; i < 100; i++) {
    try { await access(exported); break; } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
  }
  const websiteReceipt = await readFile(exported);
  await writeFile(join(output, 'website-receipt.json'), websiteReceipt, { flag: 'wx' });
  assert.deepEqual(JSON.parse(websiteReceipt).events.map(event => event.name), ['landing_view', 'download_click']);
  await page.$eval('[data-download="unknown"]', link => link.click());
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(await accepted(), 3);
  await click('#website-consent');
  await click('#primary-cta');
  assert.equal(await accepted(), 3);
  await click('#website-consent'); await waitCount(4);
  assert.equal(await page.evaluate(() => localStorage.length), 0);
  assert.equal((await page.cookies()).length, 0);
  scenarios.push('real browser default-off, opt-in, actual CTA/download click, page dedup, revoke, new consent epoch, explicit receipt export');
  assert.ok(Object.values((await report()).stages).every(value => value === null));
  for (let index = 1; index < 50; index++) {
    now += 61000;
    await load(index % 2 ? '' : '?utm_source=newsletter&utm_medium=email&utm_campaign=launch');
    await click('#website-consent'); await waitCount(4 + index * 3 - 2);
    await click('#primary-cta');
    try { await waitCount(4 + index * 3 - 1); }
    catch (error) { throw new Error(`CTA acceptance failed: ${await page.$eval('#website-status', node => node.textContent)}; recent HTTP=${httpOutcomes.slice(-5)}; errors=${JSON.stringify(collectorErrors)}; iteration=${index}`, { cause: error }); }
    await page.$eval('[data-download="unknown"]', link => link.click()); await waitCount(4 + index * 3);
    if (index === 48) assert.ok(Object.values((await report()).stages).every(value => value === null));
  }
  const result = await report();
  assert.deepEqual(result.stages, { landing_view: 51, primary_cta_click: 50, download_click: 50 });
  assert.equal(result.steps[0].rate, 50 / 51);
  assert.equal(result.steps[1].rate, 1);
  assert.equal(result.acquisition.scope, 'consented_page_epoch');
  assert.equal(result.acquisition.firstTouch.landing_view.referrerDomain.none, 51);
  assert.equal(result.acquisition.lastTouch.download_click.referrerDomain.none, 50);
  assert.ok(Object.values(result.sources).every(value => value === null));
  scenarios.push('50-stage exact publication threshold and complementary source suppression from persisted collector readback');
  await page.screenshot({ path: join(output, 'consented-observations.png'), fullPage: true });
  for (const signal of ['dnt', 'gpc']) {
    const blocked = await browser.newPage();
    await blocked.evaluateOnNewDocument(signal => Object.defineProperty(navigator,
      signal === 'dnt' ? 'doNotTrack' : 'globalPrivacyControl', { get: () => signal === 'dnt' ? '1' : true }), signal);
    await blocked.goto(server.url, { waitUntil: 'domcontentloaded' });
    assert.equal(await blocked.$eval('#website-consent', input => input.disabled), true);
    await blocked.$eval('#primary-cta', link => link.click());
    await blocked.close();
    assert.equal(await accepted(), 151);
  }
  scenarios.push('browser DNT/GPC suppress collection');
  await page.evaluate(() => Object.defineProperty(navigator, 'globalPrivacyControl', { configurable: true, get: () => true }));
  await click('#primary-cta');
  assert.equal(await page.$eval('#website-consent', input => input.checked), false);
  await page.evaluate(() => Object.defineProperty(navigator, 'globalPrivacyControl', { configurable: true, get: () => false }));
  await click('#primary-cta');
  assert.equal(await accepted(), 151);
  scenarios.push('new privacy signal revokes active page epoch; removing signal never restores consent');
  now += 61000;
  const retry = { channel: 'web', event: 'landing_view', source: 'unknown', architecture: 'unknown',
    eventId: randomUUID(), synthetic: true, observedAt: new Date(now).toISOString() };
  const post = value => fetch(`${server.url}/api/web/events`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify(value) });
  assert.equal((await post(retry)).status, 202);
  await server.close();
  server = await createLocalTestServer({ databasePath, key, telemetry: true, reuseDatabase: true, clock: () => new Date(now) });
  assert.equal((await post(retry)).status, 204);
  assert.equal((await post({ ...retry, event: 'download_click' })).status, 400);
  assert.equal(await accepted(true), 1);
  assert.equal(await accepted(), 151);
  now += 300001;
  assert.equal((await post(retry)).status, 400);
  assert.equal((await post({ ...retry, eventId: randomUUID(), observedAt: new Date(now).toISOString(), url: 'private' })).status, 400);
  scenarios.push('HTTP retry dedup across restart, conflicting reuse, stale retries, synthetic isolation, private field rejection');
  await load('');
  await page.setOfflineMode(true);
  await click('#website-consent');
  await page.waitForFunction(() => document.getElementById('website-status').textContent.includes('unavailable'));
  await click('#primary-cta');
  assert.equal(await page.evaluate(() => location.hash), '#download');
  assert.equal(await accepted(), 151);
  await page.setOfflineMode(false);
  await page.close();
  scenarios.push('offline collector never blocks ordinary CTA/download navigation');
  const saved = await readFile(databasePath);
  assert.doesNotMatch(saved.toString(), /private|secret|eventId|observedAt|utm_|127\.0\.0\.1/);
  const sourceHashes = {};
  for (const path of ['site/customer.mjs', 'site/assets/customer.js', 'site/index.html', 'site/verify-telemetry.mjs',
    'api/src/website-funnel.mjs', 'api/src/website-attribution.mjs', 'api/test/support/local_api_server.mjs',
    'api/test/support/file_backed_cosmos.mjs']) sourceHashes[path] = hash(await readFile(join(root, path)));
  await writeFile(join(output, 'computed-reports.json'), JSON.stringify(reports, null, 2), { flag: 'wx' });
  await server.close(); server = null;
  await browser.close();
  await rm(temporary, { recursive: true });
  cleanupVerified = true;
  await writeFile(receiptPath, JSON.stringify({ schemaVersion: 1, kind: 'isolated-synthetic-telemetry-acceptance',
    customerAcceptance: false, installerExecuted: false, passed: true, cleanupVerified,
    sourceRevision: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(),
    sourceHashes, persistedCollectorSha256: hash(saved), reportsSha256: hash(JSON.stringify(reports, null, 2)),
    scenarios, stages: result.stages, steps: result.steps, websiteReceiptSha256: hash(websiteReceipt) }, null, 2), { flag: 'wx' });
  process.stdout.write('Telemetry browser/HTTP persisted-readback acceptance passed (synthetic, not customer/installer acceptance).\n');
} finally {
  if (server) await server.close();
  if (browser?.connected) await browser.close();
  if (!cleanupVerified) await rm(temporary, { recursive: true });
}
