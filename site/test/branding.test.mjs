import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { renderDownloads } from '../release-downloads.mjs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const { release } = JSON.parse(read('customer-config.json'));

test('customer entry pages use exact Budlark branding without renaming compatibility URLs', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    assert.match(page, /<title>Budlark\b/);
    assert.match(page, /<header>[\s\S]*?href="\/"[^>]*>Budlark<\/a>/);
    assert.match(page, /<footer[\s\S]*?Budlark/);
    for (const property of ['og:title', 'twitter:title']) {
      assert.match(page, new RegExp(`(?:property|name)="${property}" content="Budlark\\b`));
    }
    assert.match(page, /name="description" content="[^"]*Budlark/);
    assert.match(page, /assets\/bloomstep-social\.png/);
    assert.doesNotMatch(page, /Budlock|Bud Lark/);
    assert.equal(renderDownloads(page, release), page, 'Build must preserve the branded source');
  }
  const home = read('index.html');
  const structured = JSON.parse(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/.exec(home)[1]);
  assert.equal(structured.name, 'Budlark');
  assert.match(home, /sample garden from before the Budlark rename/);
  assert.match(home, /alt="Earlier Bloomstep preview/);
});

test('NEXT is explicitly unavailable and all downloadable files remain legacy owner tests', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    const next = /<p id="next-release"[^>]*>([\s\S]*?)<\/p>/.exec(page)?.[1];
    assert.ok(next, 'NEXT status must exist without JavaScript');
    assert.match(next, /Budlark NEXT release: not yet available/);
    assert.match(next, /No Budlark NEXT download is published/);
    assert.match(next, /legacy Bloomstep/);
    assert.doesNotMatch(next, /<a\b|<button\b/);
    assert.ok(page.indexOf('id="next-release"') < page.indexOf('data-universal-download'));
    assert.match(page, />Legacy Bloomstep x64<\/a>/);
    assert.match(page, />Legacy Bloomstep ARM64<\/a>/);
    const urls = [...page.matchAll(/href="([^"]+)"[^>]*data-download=|data-download="[^"]+" href="([^"]+)"/g)]
      .map(match => match[1] ?? match[2]);
    assert.deepEqual(urls.sort(), Object.values(release).filter(value => value?.url).map(value => value.url).sort());
    assert.doesNotMatch(page, /href="[^"]*(?:Budlark-|NEXT)[^"]*\.exe/i);
    assert.match(page, /installer is unsigned/);
    assert.match(page, /Owner-test download \(designated testers only\)/);
  }
});

test('approved Budlark wordmark and social artwork are imported byte-for-byte', () => {
  for (const [name, sha256] of [
    ['wordmark', '427d77788df7504e00a7a48296173d47f4e1a5db91c737e000523e1e8af3ed5d'],
    ['social', '1826cb5e602110f9296319f3c831bc3a808eb59c6e96aac8eef1e08d0aa72a86'],
  ]) {
    const bytes = readFileSync(new URL(`../assets/bloomstep-${name}.png`, import.meta.url));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), sha256);
  }
});

test('invitation and operator display names change without changing protocol or authorization roles', () => {
  assert.match(read('customer.mjs'), /Open invitation in Budlark/);
  assert.match(read('invitation-landing.mjs'), /Open invitation in Budlark/);
  assert.match(read('console.html'), /<title>Budlark private operator console<\/title>/);
  assert.match(read('console.html'), /server-assigned Bloomstep\.Admin/);
  assert.match(read('operator-callback.html'), /<title>Budlark operator sign-in<\/title>/);
  assert.match(read('console.mjs'), /Opening secure Budlark operator sign-in/);
  assert.match(read('invitation-landing.mjs'), /bloomstep:\/\//);
  assert.equal(JSON.parse(read('config.json')).experiment.enabled, false);
  assert.deepEqual(JSON.parse(read('experiment-promotions.json')).promotions, []);
});
