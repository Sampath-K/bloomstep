import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, extname } from 'node:path';
import { chromium } from 'playwright';
import { createExperimentHandlers } from '../api/src/experiments.mjs';
import { assignArm, policyHash } from '../api/src/experiment-policy.mjs';
import { FileBackedCosmosContainer } from '../api/test/support/file_backed_cosmos.mjs';
import { ServiceError } from '../api/src/backend.mjs';

const out = process.env.EVIDENCE_DIR || join(tmpdir(), 'bloomstep-one-viewport');
await mkdir(out, { recursive: true });
const publicOrigin = JSON.parse(await readFile(new URL('./customer-config.json', import.meta.url), 'utf8')).origin;
assert.equal(publicOrigin, 'https://budlark.com');
for (const [path, route] of [['index.html', '/'], ['releases/index.html', '/releases/']]) {
  const html = await readFile(new URL(`./${path}`, import.meta.url), 'utf8');
  assert.match(html, new RegExp(`<link rel="canonical" href="${publicOrigin.replaceAll('.', '\\.')}${route.replaceAll('/', '\\/')}"`));
  assert.match(html, new RegExp(`<meta property="og:url" content="${publicOrigin.replaceAll('.', '\\.')}${route.replaceAll('/', '\\/')}"`));
  assert.doesNotMatch(html, /brave-plant-02c10e800\.5\.azurestaticapps\.net/);
}
assert.match(await readFile(new URL('./robots.txt', import.meta.url), 'utf8'), /Sitemap: https:\/\/budlark\.com\/sitemap\.xml/);
assert.match(await readFile(new URL('./sitemap.xml', import.meta.url), 'utf8'), /<loc>https:\/\/budlark\.com\/releases\/<\/loc>/);
const work = await mkdtemp(join(tmpdir(), 'bloomstep-it-copy-'));
const store = await FileBackedCosmosContainer.openFresh(join(work, 'store.json'));
let now = Date.parse('2026-10-01T00:00:00.000Z');
const workerRequest = { headers: new Headers() };
const handlers = createExperimentHandlers({
  container: () => store, environment: 'isolated', clock: () => new Date(now),
  authenticate: async () => ({ roles: ['Bloomstep.Admin'] }),
  authenticateWorker: async () => ({ roles: ['Bloomstep.AggregateWriter'] }),
  stageSummary: async () => ({ steps: [
    { from: 'landing_view', to: 'primary_cta_click', rate: .5 },
    { from: 'primary_cta_click', to: 'download_click', rate: .5 },
  ] }),
});
let exposed = [], outcomes = [], privacyCounts = [], apiRequests = 0;
const routes = {
  'GET /api/web/experiments': () => handlers.config(),
  'POST /api/web/experiments/exposure': request => handlers.exposure(request),
  'POST /api/web/experiments/outcome': request => handlers.outcome(request),
  'POST /api/web/experiments/forget': request => handlers.forget(request),
};
const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost'), key = `${req.method} ${url.pathname}`;
  if (url.pathname.startsWith('/api/')) {
    apiRequests++;
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks).toString();
    const request = { headers: new Headers(req.headers), text: async () => body };
    try {
      now += 1000;
      if (url.pathname === '/api/web/events') {
        privacyCounts.push(JSON.parse(body));
        res.writeHead(204).end();
        return;
      }
      if (!routes[key]) { res.writeHead(404).end(); return; }
      const result = await routes[key](request);
      if (key.endsWith('/exposure')) exposed.push(JSON.parse(body));
      if (key.endsWith('/outcome')) outcomes.push(JSON.parse(body));
      res.writeHead(result.status || 200, { 'Content-Type': 'application/json' }).end(JSON.stringify(result.jsonBody));
    } catch (error) {
      res.writeHead(error instanceof ServiceError ? error.status : 500, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: error.message }));
    }
    return;
  }
  const path = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
  if (path.includes('..')) { res.writeHead(400).end(); return; }
  try {
    const data = await readFile(new URL(path, import.meta.url));
    const type = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.svg': 'image/svg+xml', '.css': 'text/css' }[extname(path)] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': type }).end(data);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
const errors = [], evidence = [];
const control = { headline: 'Build a habit small enough to start today.', cta: 'Download Windows preview' };
async function copy(page) {
  return { headline: await page.locator('#intro').textContent(), cta: await page.locator('#primary-cta-copy').textContent() };
}
async function newPage(size, theme = 'light', subjectId = randomUUID(), signal = null) {
  const page = await browser.newPage({ viewport: size, reducedMotion: 'reduce' });
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(({ subjectId, signal }) => {
    crypto.randomUUID = () => subjectId;
    if (signal === 'dnt') Object.defineProperty(navigator, 'doNotTrack', { get: () => '1' });
    if (signal === 'gpc') Object.defineProperty(navigator, 'globalPrivacyControl', { get: () => true });
  }, { subjectId, signal });
  await page.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
  await page.goto(`${origin}/?scoutTheme=${theme}`, { waitUntil: 'networkidle' });
  assert.deepEqual(await copy(page), control);
  return page;
}
async function geometry(page, size) {
  const result = await page.evaluate(() => {
    const targets = ['#intro', '#primary-cta', '.preview-note', '.product', '.learn-link', '#website-consent', '.fold-footer'];
    return targets.map(selector => {
      const r = document.querySelector(selector).getBoundingClientRect();
      return { selector, top: r.top, bottom: r.bottom, left: r.left, right: r.right };
    });
  });
  for (const r of result) {
    assert(r.top >= 0 && r.bottom <= size.height && r.left >= 0 && r.right <= size.width, `${size.width}x${size.height}: ${r.selector} outside viewport: ${JSON.stringify(r)}`);
  }
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'No horizontal overflow');
  return result;
}
try {
  for (const theme of ['light', 'dark']) {
    for (const size of [{ width: 1920, height: 1080 }, { width: 1366, height: 768 }]) {
      const before = apiRequests, page = await newPage(size, theme);
      const layout = await geometry(page, size);
      assert.equal(apiRequests, before, 'No API or experiment requests without consent');
      await page.keyboard.press('Tab');
      assert.equal(await page.locator(':focus').getAttribute('class'), 'skip');
      await page.keyboard.press('Enter');
      await page.locator('#primary-cta').focus();
      await page.keyboard.press('Enter');
      assert.equal(new URL(page.url()).hash, '#download');
      assert.match(await page.locator('#download-prerequisites').textContent(), /unsigned/);
      await page.goto(`${origin}/?scoutTheme=${theme}`);
      await page.screenshot({ path: join(out, `baseline-a-${theme}-${size.width}x${size.height}.png`) });
      evidence.push({ baseline: true, theme, ...size, layout, noConsentRequests: 0 });
      await page.close();
    }
  }
  for (const key of ['hero-pair-b-v1', 'hero-pair-c-v1']) {
    const tick = await handlers.tick(workerRequest);
    const instance = (await handlers.config()).jsonBody.active;
    assert.equal(instance.key, key);
    for (const arm of ['control', 'candidate']) {
      let subjectId;
      do { subjectId = randomUUID(); } while (await assignArm(instance, subjectId) !== arm);
      for (const theme of ['light', 'dark']) {
        for (const size of [{ width: 1920, height: 1080 }, { width: 1366, height: 768 }]) {
          const page = await newPage(size, theme, subjectId);
          exposed = []; outcomes = [];
          await page.locator('#website-consent').check();
          await page.waitForFunction(() => document.documentElement.dataset.experimentArm === 'control' || document.documentElement.dataset.experimentArm === 'candidate');
          assert.deepEqual(await copy(page), instance.arms[arm].value);
          assert.equal(exposed.at(-1).arm, arm);
          assert.equal(exposed.at(-1).applied, true);
          const layout = await geometry(page, size);
          await page.screenshot({ path: join(out, `${key}-${arm}-${theme}-${size.width}x${size.height}.png`) });
          await page.locator('#primary-cta').click();
          await page.locator('[data-universal-download] a').evaluate(node => node.addEventListener('click', event => event.preventDefault()));
          await Promise.all([
            page.waitForResponse(response => response.url().endsWith('/api/web/experiments/outcome') && response.status() === 201 &&
              JSON.parse(response.request().postData()).event === 'download_click'),
            page.locator('[data-universal-download] a').click(),
          ]);
          await page.waitForTimeout(100);
          assert(outcomes.some(row => row.event === 'download_click'));
          assert.equal(await page.locator('#website-consent').isChecked(), true);
          await page.locator('#website-consent').uncheck();
          await page.waitForFunction(() => document.getElementById('website-status').textContent.includes('record was deleted'));
          assert.deepEqual(await copy(page), control);
          assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0);
          assert.equal((await page.context().cookies()).length, 0);
          evidence.push({ key, arm, theme, ...size, layout, persistedExposure: true, outcomesAfterExposure: true, withdrawalRestoresA: true });
          await page.close();
          do { subjectId = randomUUID(); } while (await assignArm(instance, subjectId) !== arm);
        }
      }
    }
    now = Date.parse(instance.endAt) + 1000;
    if (key === 'hero-pair-b-v1') {
      const result = await handlers.tick(workerRequest);
      assert.equal(result.jsonBody.actions[0].decision.status, 'no_data', 'withdrawn synthetic visits do not contribute');
    }
  }
  for (const signal of ['dnt', 'gpc']) {
    const before = apiRequests, page = await newPage({ width: 1366, height: 768 }, 'light', randomUUID(), signal);
    assert.equal(await page.locator('#website-consent').isDisabled(), true);
    assert.equal(apiRequests, before);
    await page.close();
    evidence.push({ privacySignal: signal, apiRequests: 0 });
  }
  for (const width of [320, 390, 683]) {
    const page = await newPage({ width, height: width === 683 ? 384 : 844 });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Reflow ${width}`);
    if (width === 390) await page.screenshot({ path: join(out, 'baseline-a-mobile-390.png'), fullPage: true });
    await page.close();
  }
  const noJs = await browser.newPage({ javaScriptEnabled: false, viewport: { width: 1366, height: 768 } });
  await noJs.goto(origin);
  await noJs.locator('#primary-cta').click();
  assert.equal(new URL(noJs.url()).hash, '#download');
  assert.match(await noJs.locator('[data-universal-download] a').getAttribute('href'), /preview\.14/);
  await noJs.close();
  assert.deepEqual(errors, []);
  const sources = {};
  for (const file of ['site/index.html', 'site/customer.mjs', 'site/experiment-client.mjs', 'api/src/experiment-policy.mjs']) {
    sources[file] = createHash('sha256').update(await readFile(new URL('../' + file, import.meta.url))).digest('hex');
  }
  await writeFile(join(out, 'one-viewport-receipt.json'), JSON.stringify({
    passed: true, syntheticOnly: true, sourceRevision: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
    sourceDirty: !!execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim(),
    policyHash: await policyHash(), sources, evidence, errors,
    installOrEfficacyEvidence: false, realCustomersOrCloudSettingsChanged: false,
  }, null, 2));
  console.log(`PASS: approved baseline and real isolated staged-copy rendering, privacy and reflow: ${out}`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
  await store.close();
  await rm(work, { recursive: true, force: true });
}
