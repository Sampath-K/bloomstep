import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const { release } = JSON.parse(read('customer-config.json'));

test('NEXT is explicitly unavailable and only the configured preview.14 owner-test files are linked', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    const next = /<p id="next-release"[^>]*>([\s\S]*?)<\/p>/.exec(page)?.[1];
    assert.ok(next, `${path}: NEXT status must render without JavaScript`);
    assert.match(next, /Budlark NEXT release: not yet available/);
    assert.match(next, /No Budlark NEXT download is published/);
    assert.doesNotMatch(next, /<a\b|<button\b/);
    assert.ok(page.indexOf('id="next-release"') < page.indexOf('data-universal-download'));
    const links = [...page.matchAll(/data-download="[^"]+" href="([^"]+)"/g)].map(match => match[1]);
    assert.equal(links.length, 3);
    assert.deepEqual(links.sort(), ['universal', 'x64', 'arm64'].map(arch => release[arch].url).sort());
    assert.doesNotMatch(page, /href="[^"]*(?:NEXT|budlark\.com\/downloads)[^"]*\.exe/i);
    assert.match(next, /designated owner testing only/);
  }
});
