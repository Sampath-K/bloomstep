import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, resolve, extname, relative } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { assertProductionClean, buildSandbox } from './analytics_site_build.mjs';

const puppeteer = createRequire(new URL('../site/package.json', import.meta.url))('puppeteer-core');
const evidence = resolve(process.env.EVIDENCE_DIR || 'analytics-evidence');
await mkdir(evidence, { recursive: true });
execFileSync(process.execPath, [fileURLToPath(new URL('../site/build.mjs', import.meta.url))], { stdio: 'pipe' });
await assertProductionClean();
const candidates = [process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium'].filter(Boolean);
let executablePath;
for (const candidate of candidates) {
  try { await access(candidate); executablePath = candidate; break; }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
if (!executablePath) throw Error('Set CHROME_PATH to an installed Chromium browser.');
const root = fileURLToPath(await buildSandbox({}));
const server = createServer(async (request, response) => {
  try {
    const path = resolve(root, '.' + new URL(request.url, 'http://localhost').pathname);
    if (relative(root, path).startsWith('..')) { response.writeHead(403).end(); return; }
    const target = request.url.split('?')[0].endsWith('/') ? join(path, 'index.html') : path;
    response.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript',
      '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml' })[extname(target)] || 'text/plain');
    response.end(await readFile(target));
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' ? 404 : 500).end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
const reports = [];
try {
  browser = await puppeteer.launch({ executablePath, headless: true, args: ['--disable-gpu'] });
  for (const [name, values, privacy, failLoader] of [
    ['no-keys', {}, false],
    ['fake-eu', { GA4_ID: 'G-TEST123', CLARITY_ID: 'test123', CLOUDFLARE_TOKEN: '00000000-0000-0000-0000-000000000000', POSTHOG_KEY: 'phc_fake', POSTHOG_REGION: 'EU' }, false],
    ['fake-us', { POSTHOG_KEY: 'phc_fake', POSTHOG_REGION: 'US' }, false],
    ['privacy-signal', { GA4_ID: 'G-TEST123', CLARITY_ID: 'test123', POSTHOG_KEY: 'phc_fake' }, 'globalPrivacyControl'],
    ['do-not-track', { GA4_ID: 'G-TEST123' }, 'doNotTrack'],
    ['vendor-load-error', { GA4_ID: 'G-TEST123' }, false, true],
  ]) {
    await buildSandbox(values);
    const context = await browser.createBrowserContext();
    const page = await context.newPage();
    const external = [], errors = [];
    page.on('pageerror', error => errors.push(error.message));
    if (privacy) await page.evaluateOnNewDocument(signal => Object.defineProperty(navigator, signal, {
      value: signal === 'doNotTrack' ? '1' : true,
    }), privacy);
    await page.setRequestInterception(true);
    page.on('request', request => {
      if (new URL(request.url()).origin !== origin) {
        external.push({ url: request.url(), method: request.method() });
        // Offline proof: all external requests are intercepted. No vendor receives data.
        if (failLoader) void request.abort('failed');
        else void request.respond({ status: 200, contentType: 'application/javascript', body: '' });
      } else void request.continue();
    });
    await page.goto(origin + '/?utm_source=linkedin&utm_medium=social&utm_campaign=prelaunch&invite=private', { waitUntil: 'networkidle0' });
    assert.equal(await page.$eval('#sandbox-consent', el => el.checked), false);
    assert.deepEqual(external, [], `${name}: no requests before consent`);
    assert.equal(await page.$eval('meta[name="robots"]', el => el.content), 'noindex,nofollow,noarchive');
    assert.match(await page.$eval('[data-download]', el => el.href), /utm_source=linkedin/);
    const clickFunnel = () => page.evaluate(() => {
      for (const selector of ['#primary-cta', '#download-footer-cta .button', '[data-download]']) {
        const node = document.querySelector(selector);
        node.addEventListener('click', event => event.preventDefault(), { once: true });
        node.click();
      }
    });
    await clickFunnel();
    assert.equal(await page.evaluate(() => window.dataLayer?.length || 0), 0);
    assert.equal(await page.evaluate(() => window.posthog?.length || 0), 0);
    await page.screenshot({ path: join(evidence, `${name}-before.png`), fullPage: true });
    await page.click('#sandbox-consent');
    await new Promise(resolve => setTimeout(resolve, 350));
    const expected = privacy ? [] : [
      values.GA4_ID && `https://www.googletagmanager.com/gtag/js?id=${values.GA4_ID}`,
      values.CLARITY_ID && `https://www.clarity.ms/tag/${values.CLARITY_ID}`,
      values.CLOUDFLARE_TOKEN && 'https://static.cloudflareinsights.com/beacon.min.js',
      values.POSTHOG_KEY && `https://${values.POSTHOG_REGION === 'US' ? 'us' : 'eu'}.i.posthog.com/static/array.js`,
    ].filter(Boolean);
    assert.deepEqual(external.map(item => item.url).sort(), expected.sort());
    if (privacy) assert.equal(await page.$eval('#sandbox-consent', el => el.checked), false);
    if (failLoader) {
      assert.equal(await page.$eval('#sandbox-status', el => el.textContent),
        'A sandbox vendor failed to load. Downloads still work.');
      assert.ok(await page.$eval('[data-download]', el => el.href));
    }
    await clickFunnel();
    await clickFunnel();
    const queues = await page.evaluate(() => ({
      ga: window.dataLayer?.map(args => [...args]),
      clarity: window.clarity?.q?.map(args => [...args]),
      posthog: window.posthog?._i,
      productEvents: window.posthog?.filter(row => row[0] === 'capture'),
    }));
    if (values.GA4_ID && !privacy) {
      assert.equal(queues.ga.find(row => row[0] === 'config')[2].send_page_view, false);
      assert.equal(queues.ga.find(row => row[0] === 'event')[2].page_location, origin + '/');
      const events = queues.ga.filter(row => row[0] === 'event');
      assert.deepEqual(events.map(row => row[1]), ['page_view', 'sandbox_primary_cta_click', 'sandbox_download_click']);
      assert.equal(events[2][2].architecture, 'unknown');
      assert.equal(events[0][2].utm_source, 'linkedin');
      assert.equal(JSON.stringify(events).includes('private'), false);
    }
    if (values.POSTHOG_KEY && !privacy) {
      assert.equal(queues.posthog[0][1].api_host, `https://${values.POSTHOG_REGION === 'US' ? 'us' : 'eu'}.i.posthog.com`);
      assert.equal(queues.posthog[0][1].disable_session_recording, true);
      assert.deepEqual(queues.productEvents.map(row => row[1]),
        ['sandbox_page_view', 'sandbox_primary_cta_click', 'sandbox_download_click']);
    }
    assert.deepEqual(errors, []);
    await page.screenshot({ path: join(evidence, `${name}-after.png`), fullPage: true });
    const count = external.length;
    if (!privacy) {
      await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('#sandbox-consent')]);
      assert.equal(await page.$eval('#sandbox-consent', el => el.checked), false);
      assert.equal(external.length, count, 'Reload revocation loads no vendor scripts');
      await clickFunnel();
      assert.equal(await page.evaluate(() => window.dataLayer?.length || 0), 0);
    }
    await buildSandbox({ GA4_ID: 'G-TEST123' });
    const unsafeContext = await browser.createBrowserContext();
    try {
      const page = await unsafeContext.newPage();
      await page.setRequestInterception(true);
      page.on('request', request => {
        if (new URL(request.url()).origin !== origin) {
          void request.respond({ status: 200, contentType: 'application/javascript', body: '' });
        } else void request.continue();
      });
      await page.goto(origin + '/releases/?utm_source=private_email&utm_source=linkedin&utm_medium=secret&utm_campaign=private&token=private',
        { waitUntil: 'networkidle0' });
      const links = await page.$$eval('[data-download]', nodes => nodes.map(node => node.href));
      assert.equal(links.some(url => url.includes('private')), false);
      await page.click('#sandbox-consent');
      const events = await page.evaluate(() => window.dataLayer.filter(args => args[0] === 'event').map(args => [...args]));
      assert.equal(events[0][2].page_location, origin + '/releases/');
      assert.equal(events[0][2].utm_source, 'sandbox');
      assert.equal(events[0][2].utm_medium, 'test');
      assert.equal(events[0][2].utm_campaign, 'prelaunch');
      assert.equal(JSON.stringify(events).includes('private'), false);
      assert.equal(new URL(page.url()).search, '');
      reports.push({ name: 'unsafe-campaign-release-page', events, links, passed: true });
    } finally { await unsafeContext.close(); }
    reports.push({ name, before: [], after: external, queues, errors, revoked: !privacy,
      loaderErrorReported: Boolean(failLoader) });
    await context.close();
  }
  await assertProductionClean();
  await writeFile(join(evidence, 'network.json'), JSON.stringify({
    mode: 'offline-intercepted-loader-proof', productionClean: true, reports,
    limitations: 'Vendor scripts are intercepted with empty bodies. This proves consent gating, loader URLs and queued initialization, not live vendor ingestion or vendor SDK privacy.',
  }, null, 2));
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
  // Never leave fake test identifiers as the configured staging output.
  await buildSandbox({});
}
console.log(`Analytics sandbox check passed. Evidence: ${evidence}`);
