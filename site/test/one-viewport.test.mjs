import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('approved baseline is production HTML, not a proposal selector, with unchanged preview boundaries', () => {
  const home = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(home, /<h1 id="intro">Build a habit small enough to start today\.<\/h1>/);
  assert.match(home, /id="primary-cta-copy">Download Windows preview</);
  assert.doesNotMatch(home, /id="variant"|PROPOSAL ONLY|Copy concept/);
  assert.match(home, /class="first-screen"/);
  assert.match(home, /Owner-test preview only/);
  assert.match(home, /Unsigned installer; full app journey not yet verified/);
  assert.match(home, /id="method"/);
  for (const url of ['https://behaviormodel.org/', 'https://tinyhabits.com/', 'https://doi.org/10.1002/ejsp.674']) assert.ok(home.includes(url));
  assert.match(home, /Research on habits is not evidence of this app/);
  assert.equal((home.match(/id="website-consent"/g) ?? []).length, 1);
  assert.equal((home.match(/data-universal-download/g) ?? []).length, 1);
  assert.doesNotMatch(home, /preview\.15/);
  assert.match(readFileSync(new URL('../verify-browser.mjs', import.meta.url), 'utf8'), /import\('\.\/verify-one-viewport\.mjs'\)/,
    'the unchanged customer-quality workflow reaches real staged-copy checks through its existing browser verifier');
});

test('public canonical, share, sitemap, robots and internal customer links use the custom HTTPS origin', () => {
  const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
  const origin = JSON.parse(read('customer-config.json')).origin;
  assert.equal(origin, 'https://budlark.com');
  const home = read('index.html'), releases = read('releases/index.html');
  for (const [page, path] of [[home, '/'], [releases, '/releases/']]) {
    assert.match(page, new RegExp(`<link rel="canonical" href="${origin}${path.replaceAll('/', '\\/')}"`));
    assert.match(page, new RegExp(`<meta property="og:url" content="${origin}${path.replaceAll('/', '\\/')}"`));
    assert.match(page, new RegExp(`<meta property="og:image" content="${origin.replaceAll('.', '\\.')}/assets/bloomstep-social\\.png"`));
    assert.match(page, new RegExp(`<meta name="twitter:image" content="${origin.replaceAll('.', '\\.')}/assets/bloomstep-social\\.png"`));
    assert.doesNotMatch(page, /brave-plant-02c10e800\.5\.azurestaticapps\.net/);
  }
  assert.match(home, new RegExp(`"url":"${origin.replaceAll('.', '\\.')}/"`));
  assert.match(read('sitemap.xml'), new RegExp(`<loc>${origin.replaceAll('.', '\\.')}/</loc>`));
  assert.match(read('sitemap.xml'), new RegExp(`<loc>${origin.replaceAll('.', '\\.')}/releases/</loc>`));
  assert.match(read('robots.txt'), new RegExp(`Sitemap: ${origin.replaceAll('.', '\\.')}/sitemap\\.xml`));
  assert.match(home, /href="#privacy"/);
  assert.match(releases, /href="\/#privacy"/);
  assert.match(releases, /href="\/#feedback-help"/);
  assert.match(releases, /github\.com\/Sampath-K\/bloomstep\/releases\/download\/v0\.1\.0-preview\.14/);

  const aggregation = readFileSync(new URL('../../infra/configure-aggregate-worker.ps1', import.meta.url), 'utf8');
  const consoleIdentity = readFileSync(new URL('../../infra/configure-console-identity.ps1', import.meta.url), 'utf8');
  const spendGuard = readFileSync(new URL('../../infra/configure-spend-guard.ps1', import.meta.url), 'utf8');
  assert.match(aggregation, /\$swa\.defaultHostname/);
  assert.match(aggregation, /Existing repository API_ORIGIN must match the selected SWA/);
  assert.match(consoleIdentity, /\$swa\.defaultHostname/);
  assert.match(consoleIdentity, /API_ORIGIN must match the selected Free SWA/);
  assert.match(consoleIdentity, /operator-callback\.html/);
  assert.match(spendGuard, /\$swa\.defaultHostname/);
  assert.match(spendGuard, /API_ORIGIN must match selected SWA/);
});
