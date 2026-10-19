import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const { release } = JSON.parse(read('customer-config.json'));

test('hosted universal installer is internal dogfood and the legacy architecture installers remain owner-test only', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    const next = /<p id="next-release"[^>]*>([\s\S]*?)<\/p>/.exec(page)?.[1];
    assert.ok(next, `${path}: NEXT status must render without JavaScript`);
    assert.match(next, /Budlark is in internal dogfood/);
    assert.match(next, /hosted installer is unsigned/);
    assert.match(next, /No general release is available/);
    assert.doesNotMatch(next, /<a\b|<button\b/);
    assert.ok(page.indexOf('id="next-release"') < page.indexOf('data-universal-download'));
    const links = [...page.matchAll(/data-download="[^"]+" href="([^"]+)"/g)].map(match => match[1]);
    assert.equal(links.length, 3);
    assert.deepEqual(links.sort(), ['universal', 'x64', 'arm64'].map(arch => release[arch].url).sort());
    assert.equal(links.find(url => url === release.universal.url), 'https://budlark.com/downloads/Budlark-0.1.0-windows-universal-setup.exe');
    assert.equal(release.universal.sha256, 'b53767c405fa9b704fb828d221f883b81d14231e3ebf65dd8820d3812fd42a2c');
    assert.equal(release.universal.bytes, 22392273);
    assert.match(page, /Internal dogfood preview \(unsigned; designated testers only\)/);
    assert.doesNotMatch(page, /href="[^"]*NEXT[^"]*\.exe/i);
    assert.match(next, /legacy owner-test builds/);
  }
});
