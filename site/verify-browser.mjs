import puppeteer from 'puppeteer-core';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';

const origin = process.env.PREVIEW_ORIGIN ?? 'http://127.0.0.1:8083';
const output = process.env.EVIDENCE_DIR;
if (output) await mkdir(output, { recursive: true });
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/usr/bin/google-chrome',
  headless: true, args: ['--no-sandbox','--disable-gpu'],
});
try {
  for (const width of [390, 1280]) {
    const page = await browser.newPage();
    await page.setViewport({ width, height: 900, deviceScaleFactor: 1 });
    const posts = [];
    await page.setRequestInterception(true);
    page.on('request', request => {
      if (request.url().endsWith('/api/web/events')) {
        posts.push(JSON.parse(request.postData()));
        void request.respond({ status: 202, contentType: 'application/json', body: '{"accepted":true}' });
      } else void request.continue();
    });
    await page.goto(origin, { waitUntil: 'networkidle0' });
    assert.equal(posts.length, 0, 'New website measurement is default-off');
    if (!await page.$eval('#website-consent', node => node.disabled)) await page.click('#website-consent');
    await page.waitForFunction(() => document.getElementById('website-status').textContent.includes('active'));
    assert.equal(posts[0].event, 'landing_view');
    assert.equal(posts[0].channel, 'web');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    assert.equal(await page.evaluate(() => localStorage.length), 0);
    assert.equal((await page.cookies()).length, 0);
    await page.click('#primary-cta');
    await page.waitForFunction(() => location.hash === '#download');
    assert.equal(posts.some(value => value.event === 'primary_cta_click'), true);
    const jsonLd = await page.$eval('script[type="application/ld+json"]', node => JSON.parse(node.textContent));
    assert.equal(jsonLd['@type'], 'SoftwareApplication');
    if (output) await page.screenshot({ path: join(output, `customer-${width}.png`), fullPage: true });
    await page.close();
  }
  for (const signal of ['dnt','gpc']) {
    const page = await browser.newPage();
    let requests = 0;
    await page.evaluateOnNewDocument(signal => {
      Object.defineProperty(navigator, signal === 'dnt' ? 'doNotTrack' : 'globalPrivacyControl',
        { get: () => signal === 'dnt' ? '1' : true });
    }, signal);
    page.on('request', request => { if (request.url().endsWith('/api/web/events')) requests++; });
    await page.goto(origin, { waitUntil: 'networkidle0' });
    await page.click('#website-consent');
    await page.click('#primary-cta');
    assert.equal(requests, 0);
    assert.match(await page.$eval('#website-status', node => node.textContent), /Privacy signal honoured/);
    await page.close();
  }
  const offline = await browser.newPage();
  await offline.setRequestInterception(true);
  offline.on('request', request => {
    if (request.url().endsWith('/api/web/events')) void request.abort('failed');
    else void request.continue();
  });
  await offline.goto(origin, { waitUntil: 'networkidle0' });
  await offline.click('#website-consent');
  const links = await offline.$$eval('[data-download]', links => links.map(link => link.href));
  assert.equal(links.length, 2);
  assert.ok(links.every(link => link.startsWith('https://github.com/Sampath-K/bloomstep/releases/download/')));
  await offline.click('#primary-cta');
  assert.equal(await offline.evaluate(() => location.hash), '#download');
  assert.equal(await offline.evaluate(() => localStorage.length), 0);
  await offline.close();
  console.log('Responsive layout, memory-only observation, DNT/GPC and API-outage download independence verified.');
} finally { await browser.close(); }
