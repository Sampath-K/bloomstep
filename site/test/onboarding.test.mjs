import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const limited = 'Limited preview — Bloomstep is an early, unsigned Windows app for trying tiny, routine-linked habits, check-ins, and a personal growing garden. Sign-in is required; some features and sign-in options are still being refined. This is not the complete verified MVP, and it is not medical advice. There is no Microsoft Store version yet. If you use the app, private feedback is available in-app after sign-in.';

test('both customer entry paths disclose the exact limited scope, independence and official learning', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    assert.ok(page.includes(limited), path);
    assert.match(page, /independent app inspired by the Tiny Habits method/);
    assert.match(page, /not affiliated with or endorsed by BJ Fogg or Tiny Habits/);
    assert.match(page, /href="https:\/\/tinyhabits.com"/);
    assert.match(page, /href="https:\/\/tinyhabits.com\/book\/"/);
    assert.doesNotMatch(page, /join (?:our|the) (?:preview|cohort|waitlist)|verified safe|(?:please|you can|you should) disable (?:SmartScreen|Safe Browsing|antivirus)/i);
  }
});

test('download help is static, browser-specific, conditional and honest about illustrations', () => {
  const page = read('index.html');
  for (const browser of ['Microsoft Edge', 'Google Chrome']) {
    assert.ok(page.includes(browser));
  }
  assert.match(page, /Ctrl\+J/);
  assert.match(page, /Illustrative download flow, not a browser screenshot/);
  assert.match(page, /Browser wording and controls vary by version and managed policy/);
  assert.match(page, /does not prove the file is safe or digitally signed/);
  assert.match(page, /If verification fails, stop/);
  assert.match(page, /malware or policy block/);
  assert.match(page, /More info/);
  assert.match(page, /Run anyway/);
  for (const name of ['edge', 'chrome']) {
    assert.match(page, new RegExp(`src="/assets/${name}-downloads\\.png"[^>]+alt="[^"]+"`));
    assert.ok(readFileSync(new URL(`../assets/${name}-downloads.png`, import.meta.url))
      .subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')));
  }
  assert.match(page, /benign sample text file, not a Bloomstep installer/);
  assert.equal((page.match(/Example download view; installer\/security warnings may differ/g) ?? []).length, 2);
  const provenance = JSON.parse(read('assets/download-capture-provenance.json'));
  assert.equal(provenance.sampleName, 'bloomstep-download-help-sample.txt');
  assert.deepEqual(provenance.captures.map(value => value.browser), ['edge','chrome']);
  for (const capture of provenance.captures) {
    assert.ok(page.includes(`${capture.product} ${capture.version}`));
    assert.match(capture.context, /not an installer or security-warning validation/);
    assert.match(capture.version, /^\d+\.\d+\.\d+\.\d+$/);
  }
  assert.match(page, /We have not captured Firefox's download UI/);
  assert.match(read('releases/index.html'), /href="\/#download-help"/);
  assert.match(page, /prefers-reduced-motion/);
  assert.match(page, /forced-colors: active/);
});

test('original teaching illustrations have text alternatives, self-contained vectors and no scripts', () => {
  const home = read('index.html');
  for (const name of ['anchor', 'tiny', 'celebrate']) {
    assert.match(home, new RegExp(`src="/assets/habit-${name}\\.svg"[^>]+alt="[^"]+"`));
    const svg = read(`assets/habit-${name}.svg`);
    assert.match(svg, /<svg[^>]+viewBox=/);
    assert.match(svg, /<title>/);
    assert.doesNotMatch(svg, /<script|<image|href=|https?:\/\/(?!www.w3.org)/);
  }
  assert.doesNotMatch(home, /<iframe|<video|autoplay/);
  assert.match(home, /id="website-consent" type="checkbox">/);
  assert.match(home, /id="receipt-consent" type="checkbox">/);
});
