import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { createRequire } from 'node:module';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { get } from 'node:http';
import { startConsolePreview } from './console_preview.mjs';
import { createPrimaryAuthenticator } from '../api/src/primary-auth.mjs';
import { createHandlers } from '../api/src/backend.mjs';
import { createWebsiteHandlers } from '../api/src/website-funnel.mjs';
import { createExperimentHandlers } from '../api/src/experiments.mjs';

test('loopback-only synthetic preview: actual console buttons, production auth isolation and screenshots', { timeout: 180000 }, async () => {
  const preview = await startConsolePreview({ port: 0 });
  let browser;
  try {
    assert.equal(preview.address.address, '127.0.0.1');
    assert.equal(preview.address.family, 'IPv4');
    const origin = new URL(preview.url).origin;
    for (const headers of [{ Host: 'attacker.invalid' }, { Origin: 'https://attacker.invalid' }]) {
      const status = await new Promise((resolve, reject) => {
        get(origin + '/__preview/session', { headers }, response => {
          response.resume(); resolve(response.statusCode);
        }).on('error', reject);
      });
      assert.equal(status, 403);
    }
    for (const path of ['/api/team/metrics', '/api/team/website', '/api/team/experiments']) {
      assert.equal((await fetch(origin + path)).status, 401, `${path} needs the isolated token`);
    }
    const { token } = await (await fetch(origin + '/__preview/session')).json();
    assert.equal((await fetch(origin + '/api/sync', { method: 'POST',
      headers: { 'X-Bloomstep-Authorization': `Bearer ${token}` }, body: '{}' })).status, 403);
    const { publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const authenticate = createPrimaryAuthenticator({ issuer: 'https://production.invalid', audience: 'production',
      keys: publicKey, databaseConfigured: () => true });
    const container = () => { throw Error('Production storage must not be reached'); };
    const request = { headers: new Headers({ 'X-Bloomstep-Authorization': `Bearer ${token}` }),
      query: new URLSearchParams('days=14') };
    for (const handler of [
      createHandlers({ container, authenticate }).metrics,
      createWebsiteHandlers({ container, authenticate }).metrics,
      createExperimentHandlers({ container, authenticate, environment: 'production' }).report,
    ]) {
      await assert.rejects(handler(request), error => error.status === 401, 'production rejects preview HS256 token');
    }
    const normalBundle = await readFile(new URL('../site/assets/console.js', import.meta.url), 'utf8');
    assert.ok(!normalBundle.includes('/__preview/session'), 'normal site build has no preview auth');
    const functions = await readFile(new URL('../api/src/functions.mjs', import.meta.url), 'utf8');
    assert.ok(!functions.includes('console_preview') && !functions.includes('__preview/session'), 'Functions do not register preview');

    const require = createRequire(new URL('../site/package.json', import.meta.url));
    const { default: puppeteer } = await import(pathToFileURL(require.resolve('puppeteer-core')));
    browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH ??
      'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', headless: true,
      args: ['--no-sandbox'] });
    const page = await browser.newPage();
    const errors = [], apiStatuses = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {
      if (response.url().includes('/api/team/')) apiStatuses.push({ url: new URL(response.url()).pathname, status: response.status() });
    });
    await page.setViewport({ width: 1440, height: 1050, deviceScaleFactor: 1 });
    await page.goto(preview.url, { waitUntil: 'networkidle0' });
    assert.match(await page.$eval('aside', node => node.textContent), /Local synthetic preview — not customers/);
    for (const [button, output] of [['#metrics', '#aarrr-report .aarrr-stage'],
      ['#website-metrics', '#website-funnel article'], ['#experiment-status', '#experiment-report .experiment-card']]) {
      await page.click(button);
      await page.waitForSelector(output, { timeout: 20000 });
      await page.waitForFunction(selector => !document.querySelector(selector).disabled, {}, button);
    }
    assert.deepEqual(await page.$$eval('.aarrr-stage strong', nodes => nodes.map(node => node.textContent)), ['150', '100', '50']);
    assert.match(await page.$eval('#admin-status', node => node.textContent), /2026-09-01 through 2026-09-14/);
    const acquisition = await page.$eval('#website-funnel', node => node.textContent);
    for (const expected of ['landing_view: 50', 'primary_cta_click: 50', 'download_click: 50',
      'google.com', 'newsletter', 'tiny_habits']) assert.ok(acquisition.includes(expected), expected);
    for (const summary of await page.$$('#website-funnel details summary')) {
      await summary.focus(); await page.keyboard.press('Space');
    }
    const history = await page.$eval('#experiment-report', node => node.textContent);
    for (const expected of ['Candidate promoted', 'Rolled back', 'Engaged', 'isolated_acceptance_only']) assert.ok(history.includes(expected), expected);
    const audit = await page.$('#experiment-report details summary');
    await audit.focus(); await page.keyboard.press('Space');
    assert.equal(await page.$eval('#experiment-report details', node => node.open), true);
    assert.deepEqual(errors, []);
    assert.deepEqual(apiStatuses.map(row => row.status), [200, 200, 200]);
    const out = resolve(process.env.PREVIEW_EVIDENCE_DIR ?? join(tmpdir(), 'bloomstep-console-preview-evidence'));
    await mkdir(out, { recursive: true });
    const screenshots = {};
    for (const [name, selector] of [['console-preview-all', null], ['console-preview-aarrr', '#aarrr-report'],
      ['console-preview-acquisition', 'section[aria-labelledby="web-title"]'],
      ['console-preview-experiments', 'section[aria-labelledby="experiment-title"]']]) {
      const path = join(out, `${name}.png`);
      if (selector) await (await page.$(selector)).screenshot({ path });
      else await page.screenshot({ path, fullPage: true });
      screenshots[name] = createHash('sha256').update(await readFile(path)).digest('hex');
    }
    await page.setViewport({ width: 390, height: 900, deviceScaleFactor: 1 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth), 0);
    const mobile = join(out, 'console-preview-mobile.png');
    await page.screenshot({ path: mobile, fullPage: true });
    screenshots['console-preview-mobile'] = createHash('sha256').update(await readFile(mobile)).digest('hex');
    await page.click('#clear-console');
    assert.equal(await page.$eval('#experiment-report', node => node.childElementCount), 0);
    await page.click('#experiment-status');
    await page.waitForSelector('#experiment-report .experiment-card');
    assert.deepEqual(errors, [], 'clear and reload work without authentication errors');
    const sources = {};
    for (const file of ['tool/console_preview.mjs', 'tool/console_preview.test.mjs', 'api/test/support/aarrr-fixture.mjs',
      'site/console.html', 'site/console.mjs', 'site/console.css']) {
      sources[file] = createHash('sha256').update(await readFile(new URL('../' + file, import.meta.url))).digest('hex');
    }
    await writeFile(join(out, 'receipt.json'), JSON.stringify({ passed: true, syntheticOnly: true,
      sourceRevision: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
      sourceDirty: !!execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim(),
      productionAuthRejected: true, loopbackOnly: true, apiStatuses, pageErrors: errors, sources, screenshots }, null, 2));
    console.log(`Preview browser evidence: ${out}`);
  } finally {
    if (browser) await browser.close();
    await preview.close();
    await assert.rejects(access(preview.databasePath), error => error.code === 'ENOENT', 'disposable store removed on close');
  }
});
