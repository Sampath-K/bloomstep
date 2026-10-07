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
test('universal rendering fixture never changes the public preview9 config', () => {
  assert.equal(current.release.tag, 'v0.1.0-preview.9');
  assert.equal(current.release.universal, undefined);
});
test('both download surfaces render a single primary with collapsed support links and are idempotent', () => {
  for (const name of ['index.html', 'releases/index.html']) {
    const original = readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
    assert.equal(renderDownloads(original, current.release), original);
    const unified = renderDownloads(original, fixture);
    assert.equal(renderDownloads(unified, fixture), unified);
    assert.equal((unified.match(/data-universal-download/g) ?? []).length, 1);
    assert.match(unified, /data-download="unknown"/);
    assert.match(unified, /<details><summary>Secondary architecture-specific downloads/);
    assert.doesNotMatch(unified, /<details open><summary>Secondary/);
    assert.match(unified, /Both payloads are included/);
    assert.match(unified, /Unsupported 32-bit Windows cannot install/);
    if (name.startsWith('releases/')) {
      assert.match(unified, /Universal SHA-256: a{64}/);
      assert.match(unified, /Secondary installer checksums/);
    }
  }
});
test('malformed unified entry cannot silently fall back to architecture downloads', () => {
  for (const universal of [null, {}, { ...fixture.universal, sha256: '' }, { ...fixture.universal, url: fixture.x64.url }]) {
    assert.throws(() => validateRelease({ ...fixture, universal }), /Verified release/);
  }
});
