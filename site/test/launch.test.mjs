import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyAttribution } from '../customer.mjs';

const home = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const releases = readFileSync(new URL('../releases/index.html', import.meta.url), 'utf8');
test('launch path discloses prerequisites and a public support/privacy contact without collecting contact details', () => {
  const download = /<section id="download"[\s\S]*?<\/section>/.exec(home)[0];
  assert.match(download, /id="download-prerequisites"[\s\S]*64-bit Windows[\s\S]*sign-in[\s\S]*ages 16[\s\S]*unsigned/);
  assert.match(download, /id="website-measurement"/);
  assert.equal((home.match(/id="website-consent"/g) ?? []).length, 1);
  assert.doesNotMatch(home, /id="website-consent"[^>]*checked/);
  assert.match(home, /href="#website-measurement">Optional website measurement/);
  assert.match(home, /data-primary-cta="footer" href="#download"/);
  assert.match(home, /id="feedback-help"/);
  assert.doesNotMatch(home, /type="email"|<form/);
  assert.match(home, /id="privacy-notice"/);
  const privacyNotice = /<details id="privacy-notice">[\s\S]*?<\/details>/.exec(home)[0];
  assert.match(privacyNotice, /href="mailto:store-developer@outlook\.com">store-developer@outlook\.com<\/a>/);
  assert.match(privacyNotice, /For support or a request about access, correction or deletion/);
  assert.match(privacyNotice, /not guaranteed within a stated period/);
  assert.doesNotMatch(privacyNotice, /private contact accessible without signing in is prepared for owner review but is not published/);
  assert.equal((releases.match(/href="mailto:store-developer@outlook\.com">store-developer@outlook\.com<\/a>/g) ?? []).length, 2);
  assert.match(releases, /href="\/#privacy-notice"/);
  assert.match(home, /Sampath Kumar's personal independent project/);
  assert.match(home, /not operated by Microsoft/);
  assert.match(home, /periodic backups every four hours with an eight-hour retention setting/);
  assert.match(home, /396 days/);
  assert.match(home, /30-day lifetime/);
  assert.doesNotMatch(home, /hotmail\.com|microsoft\.com">[^<]*support|GDPR compliant|certified safe/);
});
test('initial demand link uses fixed allowlisted labels and never treats interest as an identified lead', () => {
  const touch = classifyAttribution('https://www.linkedin.com/feed/',
    '?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits', 'https://site.test');
  assert.deepEqual(touch, { source: 'campaign', referrerDomain: 'linkedin.com',
    campaignSource: 'linkedin', campaignMedium: 'social', campaignName: 'tiny_habits' });
  assert.equal(classifyAttribution('', '?utm_source=person@example.com', 'https://site.test').campaignSource, 'unknown');
});
