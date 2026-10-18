import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { classifyAttribution } from '../customer.mjs';

const home = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const releases = readFileSync(new URL('../releases/index.html', import.meta.url), 'utf8');
const launchVerifier = readFileSync(new URL('../verify-launch.mjs', import.meta.url), 'utf8');
test('launch path discloses prerequisites and support/privacy limits without collecting contact details', () => {
  const download = /<section id="download"[\s\S]*?<\/section>/.exec(home)[0];
  assert.match(download, /id="download-prerequisites"[\s\S]*64-bit Windows[\s\S]*ages 16[\s\S]*unsigned/);
  assert.match(download, /local device garden without signing in; sign in is needed for an account garden and sync/);
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
  assert.match(privacyNotice, /For support or a request to access, correct or delete/);
  assert.match(privacyNotice, /A response time is not guaranteed/);
  assert.match(privacyNotice, /You do not need to sign in to email/);
  assert.match(launchVerifier, /mailto:store-developer@outlook\.com/);
  assert.match(launchVerifier, /counts are on/);
  assert.doesNotMatch(launchVerifier, /textContent\.includes\('active'\)/);
  assert.match(launchVerifier, /renderedLinkReview/);
  assert.match(readFileSync(new URL('../verify-browser.mjs', import.meta.url), 'utf8'), /counts are on/);
  assert.ok(releases.includes(contactLink));
  assert.ok(/<details id="feedback-help">[\s\S]*?<\/details>/.exec(home)[0].includes(contactLink));
  for (const page of [home, releases]) {
    assert.doesNotMatch(page, /private contact route without sign-in is (?:not currently|currently not) published|No verified private contact route/);
    assert.deepEqual([...page.matchAll(/href="mailto:([^"]+)"/g)].map(match => match[1]),
      Array((page.match(/href="mailto:/g) ?? []).length).fill('store-developer@outlook.com'));
  }
  assert.match(releases, /budlark\/issues/);
  assert.match(releases, /href="\/#privacy-notice"/);
  assert.match(home, /Sampath Kumar's personal independent project/);
  assert.match(home, /not operated by Microsoft/);
  assert.match(privacyNotice, /No third-party product analytics tools are enabled on the public website/);
  assert.match(privacyNotice, /A separate testing website uses Google Analytics only after a tester opts in/);
  assert.match(privacyNotice, /test visits have been received there/);
  assert.match(privacyNotice, /does not mean customer activity or analytics are enabled on the public site/);
  assert.match(privacyNotice, /do not expire because you stop using the app/);
  assert.match(privacyNotice, /This preview does not promise a recovery service or a recovery deadline/);
  assert.match(privacyNotice, /we do not know exactly when providers delete backup copies/);
  assert.match(privacyNotice, /restoring from Azure backups and keeping those markers after a restore have not been tested/);
  assert.match(privacyNotice, /We do not know whether restoring a backup could bring back deleted information/);
  assert.match(privacyNotice, /backups every four hours, an eight-hour retention setting and storage in more than one geographic region/);
  assert.match(privacyNotice, /396 days from when the activity originally happened/);
  assert.match(home, /used for up to five minutes to avoid duplicate counts, then removed during subsequent service activity/);
  assert.match(home, /Review history is limited to 500 entries and 50 completed comparisons/);
  assert.match(home, /not a promise that every record is deleted within 90 days/);
  assert.match(home, /daily summaries are kept for 30 days/);
  assert.doesNotMatch(home, /hotmail\.com|microsoft\.com">[^<]*support|GDPR compliant|certified safe/);
});
test('initial demand link uses fixed allowlisted labels and never treats interest as an identified lead', () => {
  const touch = classifyAttribution('https://www.linkedin.com/feed/',
    '?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits', 'https://site.test');
  assert.deepEqual(touch, { source: 'campaign', referrerDomain: 'linkedin.com',
    campaignSource: 'linkedin', campaignMedium: 'social', campaignName: 'tiny_habits' });
  assert.equal(classifyAttribution('', '?utm_source=person@example.com', 'https://site.test').campaignSource, 'unknown');
});
test('customer copy distinguishes local guest use from sign-in for an account garden and sync', () => {
  assert.match(home, /Plant locally without signing in; sign in to sync an account garden/);
  assert.match(home, /You can plant in a local device garden without signing in; sign in is needed for an account garden and sync/);
  assert.match(home, /No account is needed to plant in a local device garden\. Sign in to use an account garden and sync/);
  assert.match(home, /local device garden without signing in; account gardens and sync require sign-in/);
  assert.doesNotMatch(home, /Sign-in required|Sign-in is required, and some features|You need to sign in to get started|Sign-in is needed to use the app/);
  assert.match(releases, /You can plant in a local device garden without signing in; account gardens and sync require sign-in/);
  assert.match(releases, /Your local device garden stays on that device; signing in and syncing an account garden require an internet connection/);
  assert.doesNotMatch(releases, /Sign-in is required, and some features/);
});
test('Grove graduation is an app milestone, not a claim of automaticity or permanence', () => {
  assert.match(releases, /recorded practice and your report that a habit feels natural meet the app's criteria/);
  assert.match(releases, /This is an app milestone, not proof that the habit became automatic or permanent/);
  assert.doesNotMatch(releases, /automatic habits graduate/);
});
test('launch documentation matches the configured preview14 pointer and keeps contact facts bounded', () => {
  const config = JSON.parse(readFileSync(new URL('../customer-config.json', import.meta.url), 'utf8'));
  const launch = readFileSync(new URL('../../docs/website-launch.md', import.meta.url), 'utf8');
  const funnel = readFileSync(new URL('../../docs/website-funnel.md', import.meta.url), 'utf8');
  const normalizedFunnel = funnel.replace(/\s+/g, ' ');
  const universal = config.release.universal;
  for (const documentation of [launch, funnel]) {
    assert.ok(documentation.includes(config.release.tag));
    assert.ok(documentation.includes(universal.url));
    assert.ok(documentation.includes(universal.sha256));
    assert.ok(documentation.includes('22,261,590 bytes'));
    assert.doesNotMatch(documentation, /current(?: website)? download(?: pointer)?[^\n]*preview\.12|21,542,145/);
  }
  assert.match(normalizedFunnel, /Preview\.8 warning screenshots are historical evidence only/);
  assert.match(normalizedFunnel, /not a newer owner-test candidate or approval to upgrade the website pointer/);
  assert.match(launch, /not a general release or an upgrade to the newer owner-test candidate/);
  assert.match(launch, /owner manual verification of that newer exact installer is pending/);
  assert.match(normalizedFunnel, /owner-approved public support\/privacy contact/);
  assert.match(normalizedFunnel, /Mailbox delivery has not been tested/);
  assert.match(normalizedFunnel, /does not resolve the formal controller\/legal identity, applicable jurisdiction-specific legal bases, provider logging or identity retention, or processor and backup deletion\/recovery behavior/);
  assert.doesNotMatch(normalizedFunnel, /TODO\(owner\): supply controller identity, privacy contact/);
});
test('customer navigation and linked local destinations resolve to real sections and files', () => {
  const siteRoot = fileURLToPath(new URL('../', import.meta.url));
  const homeIds = new Set([...home.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]));
  const releasesIds = new Set([...releases.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]));
  for (const [page, html, ids] of [['index.html', home, homeIds], ['releases/index.html', releases, releasesIds]]) {
    for (const [, href] of html.matchAll(/href="([^"]+)"/g)) {
      if (href.startsWith('#')) {
        assert.ok(ids.has(href.slice(1)), `${page} link ${href} has a matching section`);
      } else if (href.startsWith('/#')) {
        assert.ok(homeIds.has(href.slice(2)), `${page} link ${href} has a matching home section`);
      } else if (href === '/' || href === '/releases/') {
        assert.ok(existsSync(join(siteRoot, href === '/' ? 'index.html' : 'releases', ...(href === '/' ? [] : ['index.html']))),
          `${page} route ${href} exists`);
      } else if (href.startsWith('/assets/')) {
        assert.ok(existsSync(join(siteRoot, href.slice(1))), `${page} asset ${href} exists`);
      } else if (href.startsWith('mailto:')) {
        assert.equal(href, 'mailto:store-developer@outlook.com');
      } else {
        const url = new URL(href);
        assert.equal(url.protocol, 'https:', `${page} external link ${href} uses HTTPS`);
        assert.ok(url.hostname, `${page} external link ${href} has a destination`);
      }
    }
  }
  assert.doesNotMatch(releases, /owner-trial-checklist|docs\/status\.md|\bCI\b|elevated worker|launch gates|support receipts|stale-device|API audit/i);
});
