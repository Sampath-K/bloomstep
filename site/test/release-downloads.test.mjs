import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { renderDownloads, validateRelease } from '../release-downloads.mjs';

const current = JSON.parse(readFileSync(new URL('../customer-config.json', import.meta.url)));
const fixtureTag = 'v0.0.0-universal-render-test';
const fixture = {
  tag: fixtureTag,
  ...Object.fromEntries(['x64', 'arm64', 'universal'].map(arch => [arch, {
    url: `https://github.com/Sampath-K/bloomstep/releases/download/${fixtureTag}/Bloomstep-${fixtureTag.slice(1)}-windows-${arch}-setup.exe`,
    sha256: 'a'.repeat(64),
  }])),
};
test('universal rendering fixture never changes the verified preview12 config', () => {
  assert.equal(current.release.tag, 'v0.1.0-preview.12');
  assert.equal(current.release.universal.sha256, 'fe115a7ada87858a55ba2610f778888079ee01a242f9ff74e18120a359292858');
  assert.equal(current.release.universal.bytes, 21542145);
});
test('both customer pages mark the current downloads as owner-test only and preserve the verified pointers', () => {
  for (const name of ['index.html', 'releases/index.html']) {
    const original = readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
    assert.equal(renderDownloads(original, current.release), original);
    const unified = renderDownloads(original, fixture);
    assert.equal(renderDownloads(unified, fixture), unified);
    assert.equal((unified.match(/data-universal-download/g) ?? []).length, 1);
    assert.match(unified, /data-download="unknown"/);
    assert.match(unified, /Owner-test download \(designated testers only\)/);
    assert.match(unified, /<details><summary>Other files \(owner testing only\)/);
    assert.doesNotMatch(unified, /<details open><summary>Other files/);
    assert.match(unified, /designated testers/);
    assert.match(unified, /32-bit Windows is not supported/);
    if (name.startsWith('releases/')) {
      assert.match(unified, /Universal SHA-256: a{64}/);
      assert.match(unified, /Other owner-test file fingerprints/);
      assert.doesNotMatch(unified, /href="https:\/\/github\.com\/Sampath-K\/bloomstep\/releases\/tag\//);
    }
  }
});
test('malformed unified entry cannot silently fall back to architecture downloads', () => {
  for (const universal of [null, {}, { ...fixture.universal, sha256: '' }, { ...fixture.universal, url: fixture.x64.url }]) {
    assert.throws(() => validateRelease({ ...fixture, universal }), /Verified release/);
  }
});
test('published universal size is rendered exactly and malformed sizes fail closed', () => {
  const original = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(renderDownloads(original, current.release), /21\.54 MB \(21,542,145 bytes\)/);
  for (const bytes of [0, -1, 1.5, '21542145', null]) {
    assert.throws(() => validateRelease({
      ...current.release, universal: { ...current.release.universal, bytes },
    }), /Verified release size/);
  }
});
test('download pointers are labeled for owner testing, with platform details in closed troubleshooting', () => {
  const original = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const html = renderDownloads(original, current.release);
  const intro = /<p id="architecture-guidance">([^<]+)<\/p>/.exec(html)[1];
  assert.match(intro, /chooses the right version for your PC/);
  assert.doesNotMatch(intro, /x64|ARM64|emulation|32-bit|bytes/);
  assert.match(html, /Download size: 21\.54 MB\.<\/p>/);
  assert.match(html, /Owner-test download \(designated testers only\)/);
  assert.match(html, /<details><summary>Other files \(owner testing only\)[\s\S]*?32-bit Windows is not supported[\s\S]*?21,542,145 bytes/);
});
