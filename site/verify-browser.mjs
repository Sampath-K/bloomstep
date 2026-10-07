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
    if (output) await page.screenshot({ path: join(output, `customer-default-${width}.png`), fullPage: true });
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
  const unified = await offline.$('[data-universal-download]') !== null;
  assert.equal(links.length, unified ? 3 : 2);
  if (unified) {
    assert.equal(await offline.$eval('[data-universal-download] a', link => link.dataset.download), 'unknown');
    assert.equal(await offline.$eval('[data-universal-download] a', link => link.textContent.trim()), 'Download Bloomstep for Windows');
  }
  assert.ok(links.every(link => link.startsWith('https://github.com/Sampath-K/bloomstep/releases/download/')));
  await offline.click('#primary-cta');
  assert.equal(await offline.evaluate(() => location.hash), '#download');
  assert.equal(await offline.evaluate(() => localStorage.length), 0);
  await offline.close();
  for (const scenario of [
    { name: 'mobile', width: 390, scale: 1, js: true },
    { name: 'desktop', width: 1280, scale: 1, js: true },
    { name: 'narrow', width: 320, scale: 1, js: true },
    { name: 'no-js', width: 390, scale: 1, js: false },
    { name: 'two-times-density', width: 640, scale: 2, js: true },
    { name: 'forced-colors', width: 1280, scale: 1, js: true, forced: true },
    { name: 'dark', width: 1280, scale: 1, js: true, dark: true },
  ]) {
    const page = await browser.newPage();
    await page.setViewport({ width: scenario.width, height: 900, deviceScaleFactor: scenario.scale });
    await page.setJavaScriptEnabled(scenario.js);
    await page.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: scenario.dark ? 'dark' : 'light' },
      { name: 'prefers-reduced-motion', value: 'reduce' },
    ]);
    if (scenario.forced) {
      const session = await page.createCDPSession();
      await session.send('Emulation.setEmulatedMedia', { features: [
        { name: 'forced-colors', value: 'active' },
        { name: 'prefers-reduced-motion', value: 'reduce' },
      ] });
    }
    for (const path of ['/', '/releases/']) {
      await page.goto(origin + path, { waitUntil: 'networkidle0' });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true,
        `${path} must reflow in ${scenario.name}`);
      assert.match(await page.$eval('main', node => node.textContent), /Limited preview — Bloomstep/);
      assert.equal(await page.$$eval('a[href="https://tinyhabits.com/book/"]', links => links.length), 1);
      const images = await page.$$eval('img', images => images.filter(image => image.loading !== 'lazy')
        .map(image => ({ complete: image.complete, width: image.naturalWidth })));
      assert.ok(images.every(image => image.complete && image.width > 0), 'Required educational art loaded');
      if (path === '/') {
        assert.equal(await page.$$eval('#download-help details', details =>
          details.every(detail => !detail.open)), true, 'Browser help starts collapsed');
        assert.equal(await page.$eval('#download-help', detail => !detail.open), true,
          'Main browser help starts collapsed');
        assert.equal(await page.$eval('#windows-install-help', detail => !detail.open), true,
          'Warning FAQ starts collapsed');
        if (output) await page.screenshot({ path: join(output,
          `onboarding-${scenario.name}-home-default.png`), fullPage: true });
        await page.$eval('#download-help', node => {
          node.open = true;
          for (const detail of node.querySelectorAll('details')) detail.open = true;
          node.scrollIntoView();
        });
        for (const image of await page.$$('.browser-capture')) {
          await image.evaluate(node => node.scrollIntoView());
          await page.waitForFunction(node => node.complete && node.naturalWidth > 0,
            { timeout: 10000 }, image);
        }
        await page.$eval('#download-help', node => node.scrollIntoView());
        assert.equal(await page.$$eval('#download-help img[src*="/warning-"]', images =>
          images.length === 5 && images.every(image => image.complete && image.naturalWidth > 0)), true,
          'All five genuine warning assets load after explicit help expansion');
        assert.equal(await page.$$eval('#download-help figcaption', captions => captions.filter(caption =>
          caption.textContent.includes('Real customer-provided preview.8 ARM64 screenshot, not CI')).length), 5);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
        if (scenario.forced) assert.equal(await page.$eval('.teaching-art', node => getComputedStyle(node).display), 'none');
        await page.keyboard.press('Tab');
        assert.equal(await page.evaluate(() => document.activeElement.matches('a,button,input,summary')), true);
      }
      if (output) await page.screenshot({ path: join(output,
        `onboarding-${scenario.name}-${path === '/' ? 'home-help-expanded' : 'releases'}.png`), fullPage: true });
    }
    await page.close();
  }
  console.log('Responsive layout, memory-only observation, DNT/GPC and API-outage download independence verified.');
} finally { await browser.close(); }
