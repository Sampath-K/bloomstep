import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

const puppeteer = createRequire(new URL('../site/package.json', import.meta.url))('puppeteer-core');
const origin = 'https://brave-grass-0e6c8ed00.4.azurestaticapps.net';
const directory = resolve('analytics-evidence', 'live-keyless-staging');
await mkdir(directory, { recursive: true });
const receiptResponse = await fetch(`${origin}/build-receipt.json`);
assert.equal(receiptResponse.status, 200);
const receipt = await receiptResponse.json();
assert.equal(receipt.mode, 'keyless-staging');
const robots = await fetch(`${origin}/robots.txt`);
assert.match(await robots.text(), /Disallow: \//);
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  headless: true,
});
const reports = [];
try {
  for (const path of ['/', '/releases/']) {
    const context = await browser.createBrowserContext();
    const page = await context.newPage();
    const requests = [], errors = [];
    page.on('request', request => requests.push({ origin: new URL(request.url()).origin,
      path: new URL(request.url()).pathname, method: request.method() }));
    page.on('pageerror', error => errors.push(error.message));
    const response = await page.goto(origin + path, { waitUntil: 'networkidle0' });
    assert.equal(response.status(), 200);
    assert.match(response.headers()['x-robots-tag'], /noindex/);
    assert.equal(await page.$eval('#sandbox-consent', node => node.checked), false);
    assert.equal(requests.some(request => request.origin !== origin), false);
    await page.screenshot({ path: join(directory, path === '/' ? 'home-off.png' : 'releases-off.png'), fullPage: true });
    await page.click('#sandbox-consent');
    await page.waitForFunction(() => document.getElementById('sandbox-status').textContent.includes('No vendor keys'));
    await page.evaluate(() => {
      const link = document.querySelector('[data-download]');
      link.addEventListener('click', event => event.preventDefault());
      link.click(); link.click();
    });
    await new Promise(resolve => setTimeout(resolve, 300));
    assert.equal(requests.some(request => request.origin !== origin), false);
    assert.equal(requests.some(request => request.path.startsWith('/api/')), false);
    assert.deepEqual(errors, []);
    await page.screenshot({ path: join(directory, path === '/' ? 'home-on-keyless.png' : 'releases-on-keyless.png'), fullPage: true });
    await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('#sandbox-consent')]);
    assert.equal(await page.$eval('#sandbox-consent', node => node.checked), false);
    reports.push({ path, requests, errors, consentOff: true, keylessConsentOn: true, revoked: true });
    await context.close();
  }
  await writeFile(join(directory, 'readback.json'), JSON.stringify({
    checkedAt: new Date().toISOString(), origin, receipt, reports,
    boundary: 'Real deployed keyless marketing site only; no vendor ingestion, app/API, account attribution or production acceptance.',
  }, null, 2));
} finally { await browser.close(); }
console.log(`Live keyless staging passed. Evidence: ${directory}`);
