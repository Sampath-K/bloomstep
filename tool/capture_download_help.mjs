import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const output = process.env.EVIDENCE_DIR;
const require = createRequire(new URL('../site/package.json', import.meta.url));
const { default: puppeteer } = await import(pathToFileURL(require.resolve('puppeteer-core')).href);
assert.ok(output, 'An isolated evidence directory is required.');
await mkdir(output, { recursive: true });
const run = await mkdtemp(join(output, 'isolated-'));
const sampleName = 'bloomstep-download-help-sample.txt';
const sample = 'Harmless download-help sample. Not an installer. Do not run or install anything.';
const server = createServer((request, response) => {
  if (request.url === '/sample') {
    response.writeHead(200, { 'Content-Type': 'text/plain',
      'Content-Disposition': `attachment; filename="${sampleName}"` });
    response.end(sample);
  } else {
    response.writeHead(200, { 'Content-Type': 'text/html' });
    response.end('<!doctype html><html lang="en"><title>Isolated download example</title><a href="/sample">Download harmless text example</a></html>');
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const provenance = [];
try {
  for (const [name, executablePath, nativeUrl] of [
    ['edge', process.env.EDGE_PATH, 'edge://downloads/'],
    ['chrome', process.env.CHROME_PATH, 'chrome://downloads/'],
  ]) {
    assert.ok(executablePath, `${name} executable is required; no Chromium substitute.`);
    const downloads = join(run, `${name}-sample`);
    await mkdir(downloads, { recursive: true });
    const browser = await puppeteer.launch({ executablePath, headless: true,
      userDataDir: join(run, `${name}-isolated-profile`),
      args: ['--no-first-run', '--no-default-browser-check', '--lang=en-US'] });
    try {
      const page = await browser.newPage();
      await page.setViewport({ width: 1000, height: 640, deviceScaleFactor: 1 });
      const session = await page.createCDPSession();
      await session.send('Browser.setDownloadBehavior', { behavior: 'allow',
        downloadPath: downloads, eventsEnabled: true });
      const completed = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(Error(`${name} sample download timed out`)), 15000);
        session.on('Browser.downloadProgress', event => {
          if (event.state === 'completed') { clearTimeout(timeout); resolve(); }
          if (event.state === 'canceled') { clearTimeout(timeout); reject(Error('Sample download canceled; no override.')); }
        });
      });
      await page.goto(origin);
      await page.click('a');
      await completed;
      assert.equal(await readFile(join(downloads, sampleName), 'utf8'), sample);
      await page.goto(nativeUrl);
      await page.waitForFunction(name => {
        const text = node => [...node.childNodes].map(child =>
          child.nodeType === Node.TEXT_NODE ? child.textContent :
            text(child) + (child.shadowRoot ? text(child.shadowRoot) : '')).join('');
        return text(document).includes(name);
      }, {}, sampleName);
      await page.screenshot({ path: fileURLToPath(new URL(`../site/assets/${name}-downloads.png`, import.meta.url)), fullPage: false });
      const product = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command',
        `(Get-Item -LiteralPath '${executablePath.replaceAll("'", "''")}').VersionInfo | Select-Object ProductName,ProductVersion | ConvertTo-Json -Compress`], { encoding: 'utf8' }));
      assert.ok(product.ProductName.includes(name === 'edge' ? 'Edge' : 'Chrome'));
      provenance.push({ browser: name, version: product.ProductVersion,
        product: product.ProductName, engineVersion: await browser.version(), nativeUrl,
        capturedAt: new Date().toISOString(), viewport: '1000x640',
        context: 'Clean isolated Windows profile, benign loopback text sample only; not an installer or security-warning validation.' });
    } finally { await browser.close(); }
  }
  await writeFile(new URL('../site/assets/download-capture-provenance.json', import.meta.url),
    JSON.stringify({ schemaVersion: 1, sampleName, captures: provenance }, null, 2) + '\n');
  console.log('Captured real native download views without opening files or overriding security.');
} finally {
  await new Promise(resolve => server.close(resolve));
  await rm(run, { recursive: true });
}
