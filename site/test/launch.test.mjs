import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyAttribution } from '../customer.mjs';

const home = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
test('launch path discloses prerequisites and optional consent without collecting contact details', () => {
  const download = /<section id="download"[\s\S]*?<\/section>/.exec(home)[0];
  assert.match(download, /id="download-prerequisites"[\s\S]*64-bit Windows[\s\S]*sign-in[\s\S]*ages 16[\s\S]*unsigned/);
  assert.match(download, /id="website-measurement"/);
  assert.equal((home.match(/id="website-consent"/g) ?? []).length, 1);
  assert.doesNotMatch(home, /id="website-consent"[^>]*checked/);
  assert.match(home, /href="#website-measurement">Optional website measurement/);
  assert.match(home, /data-download-intent href="#download"/);
  assert.match(home, /id="feedback-help"/);
  assert.doesNotMatch(home, /type="email"|mailto:|<form/);
  assert.match(home, /Privacy notice details still to be supplied/);
});
test('initial demand link uses fixed allowlisted labels and never treats interest as an identified lead', () => {
  const touch = classifyAttribution('https://www.linkedin.com/feed/',
    '?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits', 'https://site.test');
  assert.deepEqual(touch, { source: 'campaign', referrerDomain: 'linkedin.com',
    campaignSource: 'linkedin', campaignMedium: 'social', campaignName: 'tiny_habits' });
  assert.equal(classifyAttribution('', '?utm_source=person@example.com', 'https://site.test').campaignSource, 'unknown');
});
