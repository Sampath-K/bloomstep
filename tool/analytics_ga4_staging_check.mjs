import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { localConfig, websiteConfig } from './analytics_config.mjs';

const origin = 'https://brave-grass-0e6c8ed00.4.azurestaticapps.net';
const privateMarker = 'PRIVATE_SANDBOX_SENTINEL';
const eventNames = ['page_view', 'sandbox_primary_cta_click', 'sandbox_download_click'];
const allowedFields = ['en', 'dl', 'dr', 'dt', 'ep.utm_source', 'ep.utm_medium',
  'ep.utm_campaign', 'ep.architecture'];

export function collectionEvents(url, body = '') {
  const parsed = new URL(url);
  if (!/^(?:[a-z0-9-]+\.)?google-analytics\.com$/.test(parsed.hostname)
      || parsed.pathname !== '/g/collect') return [];
  assert.equal((url + body).includes(privateMarker), false, 'Private query reached GA4.');
  const query = new URLSearchParams(parsed.search);
  return (body ? body.split(/\r?\n/).filter(Boolean) : ['']).map(line => {
    const parameters = new URLSearchParams(query);
    for (const [key, value] of new URLSearchParams(line)) parameters.set(key, value);
    return {
      measurementId: parameters.get('tid'),
      fields: Object.fromEntries(allowedFields.filter(key => parameters.has(key))
        .map(key => [key, parameters.get(key)])),
      parameterNames: [...parameters.keys()].sort(),
    };
  });
}

export async function checkGa4Staging() {
  const config = websiteConfig(await localConfig());
  assert.ok(config.GA4_ID, 'Configure the approved staging GA4_ID first.');
  assert.equal(['CLARITY_ID', 'CLOUDFLARE_TOKEN', 'POSTHOG_KEY'].some(key => config[key]), false,
    'This check requires GA4-only staging configuration.');
  const receiptResponse = await fetch(`${origin}/build-receipt.json`);
  assert.equal(receiptResponse.status, 200);
  const receipt = await receiptResponse.json();
  assert.equal(receipt.mode, 'ga4-staging', 'Deploy the GA4 staging artifact first.');
  const robots = await fetch(`${origin}/robots.txt`);
  assert.match(await robots.text(), /Disallow: \//);
  const directory = resolve('analytics-evidence', 'live-ga4-staging');
  await mkdir(directory, { recursive: true });
  const puppeteer = createRequire(new URL('../site/package.json', import.meta.url))('puppeteer-core');
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: true,
  });
  const reports = [];
  try {
    for (const path of ['/', '/releases/']) {
      const context = await browser.createBrowserContext();
      const page = await context.newPage();
      const requests = [], events = [], errors = [], failures = [], collectionResponses = [];
      page.on('request', request => {
        const url = new URL(request.url());
        requests.push({ origin: url.origin, path: url.pathname, method: request.method() });
        try { events.push(...collectionEvents(request.url(), request.postData())); }
        catch (error) { failures.push(error.message); }
      });
      page.on('pageerror', error => errors.push(error.message));
      page.on('response', response => {
        const url = new URL(response.url());
        if (/^(?:[a-z0-9-]+\.)?google-analytics\.com$/.test(url.hostname)
            && url.pathname === '/g/collect') {
          collectionResponses.push({ origin: url.origin, path: url.pathname, status: response.status() });
        }
      });
      const response = await page.goto(`${origin}${path}?private=${privateMarker}#${privateMarker}`,
        { waitUntil: 'networkidle0' });
      assert.equal(response.status(), 200);
      assert.match(response.headers()['x-robots-tag'], /noindex/);
      assert.equal(await page.$eval('#sandbox-consent', node => node.checked), false);
      assert.equal(requests.some(request => request.origin !== origin), false);
      await page.screenshot({ path: join(directory, path === '/' ? 'home-off.png' : 'releases-off.png'), fullPage: true });
      await page.click('#sandbox-consent');
      await page.waitForFunction(() => document.getElementById('sandbox-status').textContent.includes('active'));
      await page.evaluate(() => {
        for (const selector of ['#primary-cta', '#download-footer-cta .button', '[data-download]']) {
          const link = document.querySelector(selector);
          if (!link) continue;
          link.addEventListener('click', event => event.preventDefault());
          link.click(); link.click();
        }
      });
      await page.waitForFunction(() => typeof window.google_tag_manager === 'object');
      // GA4 can batch custom events after the initial page-view request.
      const deadline = Date.now() + 15000;
      const hasCta = await page.$$eval('#primary-cta, #download-footer-cta .button', links => links.length > 0);
      while (Date.now() < deadline && !eventNames.every(name =>
        (name === 'sandbox_primary_cta_click' && !hasCta)
          || events.some(event => event.fields.en === name))) {
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      await new Promise(resolve => setTimeout(resolve, 1000));
      await writeFile(join(directory, path === '/' ? 'home-collection.json' : 'releases-collection.json'),
        JSON.stringify({ path, requests, events: events.map(({ fields, parameterNames }) => ({ fields, parameterNames })),
          collectionResponses, boundary: 'Collection requests/responses only; not authenticated report ingestion.' }, null, 2));
      assert.deepEqual(failures, []);
      assert.deepEqual(errors, []);
      assert.ok(collectionResponses.length > 0, 'No GA4 collection response received.');
      assert.ok(collectionResponses.every(response => response.status >= 200 && response.status < 300),
        'GA4 collection endpoint returned an error.');
      assert.equal(requests.some(request => request.path.startsWith('/api/')), false);
      assert.equal(requests.some(request => request.origin !== origin
        && request.origin !== 'https://www.googletagmanager.com'
        && !/^https:\/\/(?:[a-z0-9-]+\.)?google-analytics\.com$/.test(request.origin)), false);
      for (const name of eventNames) {
        const expected = name === 'sandbox_primary_cta_click'
          ? await page.$$eval('#primary-cta, #download-footer-cta .button', links => links.length > 0 ? 1 : 0)
          : 1;
        assert.equal(events.filter(event => event.fields.en === name).length, expected,
          `Unexpected ${name} count on ${path}.`);
      }
      for (const event of events) {
        assert.equal(event.measurementId, config.GA4_ID);
        if (eventNames.includes(event.fields.en)) {
          assert.equal(event.fields.dl, origin + path);
          assert.ok(!event.fields.dr);
          assert.equal(event.fields.dt, 'Bloomstep sandbox');
        }
      }
      await page.screenshot({ path: join(directory, path === '/' ? 'home-on.png' : 'releases-on.png'), fullPage: true });
      const beforeRevoke = requests.length;
      await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('#sandbox-consent')]);
      await new Promise(resolve => setTimeout(resolve, 1500));
      assert.equal(await page.$eval('#sandbox-consent', node => node.checked), false);
      assert.equal(requests.slice(beforeRevoke).some(request => request.origin !== origin), false);
      reports.push({ path, requests, events: events.map(({ fields, parameterNames }) => ({ fields, parameterNames })),
        collectionResponses, consentOff: true, revoked: true });
      await context.close();
    }
    for (const signal of ['doNotTrack', 'globalPrivacyControl']) {
      const context = await browser.createBrowserContext();
      const page = await context.newPage();
      const external = [];
      await page.evaluateOnNewDocument(name => Object.defineProperty(navigator, name, {
        get: () => name === 'doNotTrack' ? '1' : true,
      }), signal);
      page.on('request', request => {
        if (new URL(request.url()).origin !== origin) external.push(new URL(request.url()).origin);
      });
      await page.goto(origin, { waitUntil: 'networkidle0' });
      await page.click('#sandbox-consent');
      assert.equal(await page.$eval('#sandbox-consent', node => node.checked), false);
      assert.deepEqual(external, []);
      reports.push({ signal, blocked: true });
      await context.close();
    }
    await writeFile(join(directory, 'readback.json'), JSON.stringify({
      checkedAt: new Date().toISOString(), origin, receipt, reports,
      boundary: 'Real GA4 browser collection requests only. Authenticated GA4 receipt must be evidenced separately; no install, account attribution or revenue proof.',
    }, null, 2));
  } finally { await browser.close(); }
  console.log(`GA4 staging browser check passed. Evidence: ${directory}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await checkGa4Staging();
