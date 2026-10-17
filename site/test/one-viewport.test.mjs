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
