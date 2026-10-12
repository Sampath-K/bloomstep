import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyAttribution } from '../customer.mjs';

const home = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const releases = readFileSync(new URL('../releases/index.html', import.meta.url), 'utf8');
const launchVerifier = readFileSync(new URL('../verify-launch.mjs', import.meta.url), 'utf8');
test('launch path discloses prerequisites and support/privacy limits without collecting contact details', () => {
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
  const contactLink = '<a href="mailto:store-developer@outlook.com">store-developer@outlook.com</a>';
  assert.ok(privacyNotice.includes(contactLink));
  assert.match(privacyNotice, /For support or a request about access, correction or deletion/);
  assert.match(privacyNotice, /not guaranteed within a stated period/);
  assert.match(privacyNotice, /You do not need to sign in to email/);
  assert.match(launchVerifier, /mailto:store-developer@outlook\.com/);
  assert.ok(releases.includes(contactLink));
  assert.ok(/<details id="feedback-help">[\s\S]*?<\/details>/.exec(home)[0].includes(contactLink));
  for (const page of [home, releases]) {
    assert.doesNotMatch(page, /private contact route without sign-in is (?:not currently|currently not) published|No verified private contact route/);
    assert.deepEqual([...page.matchAll(/href="mailto:([^"]+)"/g)].map(match => match[1]),
      Array((page.match(/href="mailto:/g) ?? []).length).fill('store-developer@outlook.com'));
  }
  assert.match(releases, /bloomstep\/issues/);
  assert.match(releases, /href="\/#privacy-notice"/);
  assert.match(home, /Sampath Kumar's personal independent project/);
  assert.match(home, /not operated by Microsoft/);
  assert.match(privacyNotice, /production vendor analytics are off/);
  assert.match(privacyNotice, /staging sandbox loads GA4 only after an affirmative opt-in/);
  assert.match(privacyNotice, /GA4 ingestion from test visits has been verified/);
  assert.match(privacyNotice, /does not establish production collection, customer adoption, attribution to an installed artifact or conversions/);
  assert.match(privacyNotice, /Garden records, feedback and settings are kept until you use the applicable deletion control/);
  assert.match(privacyNotice, /they do not automatically expire due to inactivity/);
  assert.match(privacyNotice, /V1 has no guaranteed recovery service or recovery deadline/);
  assert.match(privacyNotice, /deletion timing in provider backups is unknown/);
  assert.match(privacyNotice, /configured Azure backup restore and marker preservation through restore have not been tested/);
  assert.match(privacyNotice, /Whether a restore could reintroduce deleted content is unknown/);
  assert.match(privacyNotice, /periodic backups every four hours, an eight-hour retention setting and geo-redundant backup storage/);
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
