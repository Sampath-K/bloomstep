import puppeteer from 'puppeteer-core';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { renderDownloads } from './release-downloads.mjs';

const origin = process.env.PREVIEW_ORIGIN ?? 'http://127.0.0.1:8083';
const tag = 'v0.0.0-universal-render-test';
const fixture = {
  tag,
  ...Object.fromEntries(['x64', 'arm64', 'universal'].map(arch => [arch, {
    url: `https://github.com/Sampath-K/bloomstep/releases/download/${tag}/Bloomstep-${tag.slice(1)}-windows-${arch}-setup.exe`,
    sha256: 'a'.repeat(64),
  }])),
};
const html = renderDownloads(await readFile(new URL('./index.html', import.meta.url), 'utf8'), fixture);
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/usr/bin/google-chrome',
  headless: true, args: ['--no-sandbox', '--disable-gpu'],
});
try {
  for (const scenario of [
    { name: 'desktop', width: 1280 }, { name: 'mobile', width: 390 },
    { name: 'narrow', width: 320 }, { name: 'noJS', width: 390, noJS: true },
    { name: 'dark', width: 390, dark: true }, { name: 'forcedColors', width: 390, forced: true },
    { name: 'DNT', width: 390, signal: 'dnt' }, { name: 'GPC', width: 390, signal: 'gpc' },
    { name: 'outage', width: 390, outage: true },
  ]) {
    const page = await browser.newPage();
    const posts = [];
    await page.setViewport({ width: scenario.width, height: 900 });
    await page.setJavaScriptEnabled(!scenario.noJS);
    await page.evaluateOnNewDocument(signal => {
      window.architectureQueries = 0;
      Object.defineProperty(navigator, 'userAgentData', { get: () => ({
        getHighEntropyValues: () => { window.architectureQueries++; return Promise.reject(Error('Not allowed for unified rendering')); },
      }) });
      if (signal) Object.defineProperty(navigator, signal === 'dnt' ? 'doNotTrack' : 'globalPrivacyControl',
        { get: () => signal === 'dnt' ? '1' : true });
    }, scenario.signal);
    if (scenario.dark) await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }]);
    if (scenario.forced) {
      const session = await page.createCDPSession();
      await session.send('Emulation.setEmulatedMedia', { features: [{ name: 'forced-colors', value: 'active' }] });
    }
    await page.setRequestInterception(true);
    page.on('request', request => {
      if (request.isNavigationRequest() && request.url() === `${origin}/`) {
        void request.respond({ status: 200, contentType: 'text/html', body: html });
      } else if (request.url().endsWith('/api/web/events')) {
        posts.push(JSON.parse(request.postData()));
        if (scenario.outage) void request.abort('failed');
        else void request.respond({ status: 202, contentType: 'application/json', body: '{"accepted":true}' });
      } else if (request.url().startsWith('https://github.com/')) {
        throw Error('Rendering contract must never download a synthetic release fixture.');
      } else void request.continue();
    });
    await page.goto(origin, { waitUntil: 'networkidle0' });
    assert.equal(await page.$$eval('[data-universal-download] a', links => links.length), 1, scenario.name);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, scenario.name);
    assert.equal(await page.$eval('[data-universal-download] a', link => link.textContent), 'Download Bloomstep for Windows');
    assert.equal(await page.$eval('[data-universal-download] + details', node => node.open), false);
    assert.equal(posts.length, 0);
    if (!scenario.noJS) {
      assert.equal(await page.evaluate(() => window.architectureQueries), 0);
      await page.click('#website-consent');
      await page.$eval('[data-universal-download] a', link => { link.addEventListener('click', event => event.preventDefault()); link.click(); });
      await new Promise(resolve => setTimeout(resolve, 100));
      if (scenario.signal) assert.equal(posts.length, 0);
      else if (!scenario.outage) {
        assert.equal(posts.find(post => post.event === 'download_click')?.architecture, 'unknown');
      }
      assert.equal(await page.evaluate(() => localStorage.length), 0);
    }
    await page.close();
  }
  console.log('Unified static rendering contracts passed: synthetic URLs/hashes only; no published-asset or installer evidence inferred.');
} finally { await browser.close(); }
