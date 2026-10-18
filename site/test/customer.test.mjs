import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifySource, architectureHint, createWebObserver } from '../customer.mjs';
import { websitePanels } from '../website-panels.mjs';

test('source classification transmits categories, not hosts or URLs', () => {
  assert.equal(classifySource('', '', 'https://site.test'), 'direct');
  assert.equal(classifySource('https://www.google.com/search?q=private', '', 'https://site.test'), 'search');
  assert.equal(classifySource('https://notgoogle.com/', '', 'https://site.test'), 'referral');
  assert.equal(classifySource('https://site.test/private?q=secret', '', 'https://site.test'), 'unknown');
  assert.equal(classifySource('malformed', '', 'https://site.test'), 'unknown');
  assert.equal(classifySource('', '?utm_source=newsletter', 'https://site.test'), 'campaign');
  assert.equal(classifySource('', '?utm_source=' + 'a'.repeat(49), 'https://site.test'), 'unknown');
});
test('architecture guidance is a hint with unknown fallback', () => {
  assert.equal(architectureHint('arm', 64), 'arm64');
  assert.equal(architectureHint('x86', 64), 'x64');
  assert.equal(architectureHint('', 0), 'unknown');
});
test('no storage, no identifying payload, honour signals, dedup and do not block downloads', async () => {
  const requests = [];
  const observer = createWebObserver({ send: async value => requests.push(value),
    source: 'search', uuid: () => '00000000-0000-4000-8000-000000000001' });
  await observer.record('landing_view');
  await observer.record('landing_view');
  await observer.record('download_click', 'arm64');
  assert.equal(requests.length, 2);
  assert.deepEqual(Object.keys(requests[0]).sort(), ['architecture','channel','event','eventId','source','synthetic','observedAt'].sort());
  for (const signals of [{ dnt: '1' }, { gpc: true }]) {
    const blocked = createWebObserver({ ...signals, send: async () => assert.fail('Must not upload') });
    assert.equal(await blocked.record('landing_view'), false);
  }
  const offline = createWebObserver({ send: async () => { throw Error('offline'); } });
  assert.equal(await offline.record('download_click', 'x64'), false);
});
test('customer and engineering surfaces are separated with honest SEO', () => {
  const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
  const home = read('index.html'), releases = read('releases/index.html'), consolePage = read('console.html');
  assert.doesNotMatch(home, /Growing in public|Product team console|SHA-256:|Windows engineering preview/);
  assert.match(home, /Check preview availability/);
  assert.match(home, /More info/);
  assert.match(home, /Run anyway/);
  assert.match(releases, /SHA-256/);
  assert.match(consolePage, /noindex/);
  assert.doesNotMatch(read('sitemap.xml'), /console|callback/);
  assert.match(read('robots.txt'), /Disallow: \/console/);
  for (const page of [home, releases]) {
    assert.match(page, /rel="canonical"/);
    assert.match(page, /name="description"/);
    assert.match(page, /property="og:image"/);
  }
  assert.match(home, /SoftwareApplication/);
  assert.doesNotMatch(home, /aggregateRating/);
});
test('owner-test downloads match the exact preview.14 release without implying general availability', () => {
  const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
  const config = JSON.parse(read('customer-config.json'));
  const home = read('index.html'), releases = read('releases/index.html');
  const assets = {
    arm64: {
      label: 'ARM64',
      sha256: 'c9750eb5985e97f99282b8bb958235c86d597eefb4e14ba18801795c92eb723d',
    },
    x64: {
      label: 'x64',
      sha256: 'f452014788d88eed80f1609180dc89660fe26dceec5598e843d2ec51a088b9cf',
    },
    universal: {
      label: 'Universal',
      sha256: '7ad56cc3c71a40d78dd7cb043b43aa42ea884cb0484da982cffa386c9384b094',
    },
  };
  assert.equal(config.release.tag, 'v0.1.0-preview.14');
  assert.equal(config.release.universal.bytes, 22261590);
  for (const [architecture, asset] of Object.entries(assets)) {
    const filename = `Bloomstep-0.1.0-preview.14-windows-${architecture}-setup.exe`;
    const url = `https://github.com/Sampath-K/bloomstep/releases/download/v0.1.0-preview.14/${filename}`;
    assert.equal(config.release[architecture].url, url);
    assert.equal(config.release[architecture].sha256, asset.sha256);
    assert.ok(home.includes(url));
    assert.ok(releases.includes(url));
    assert.ok(releases.includes(`${asset.label} SHA-256: ${asset.sha256}`));
  }
  assert.match(home, /id="download-version">0\.1\.0-preview\.14</);
  for (const page of [home, releases]) {
    assert.equal((page.match(/data-universal-download/g) ?? []).length, 1);
    assert.match(page, /22\.26 MB \(22,261,590 bytes\)/);
    assert.match(page, /Version 0\.1\.0-preview\.12 is an older, superseded owner-test build/);
    assert.doesNotMatch(page, /href="[^"]*download\/v0\.1\.0-preview\.12/);
    assert.doesNotMatch(page, /href="[^"]*download\/v0\.1\.0-preview\.9/);
    assert.match(page, /Early preview — not yet verified for general use/);
    assert.match(page, /owner-test candidate, not a general customer release/);
    assert.match(page, /Owner-test download \(designated testers only\)/);
  }
  assert.match(releases, /Launch after installation and the complete app journey have not been verified/);
  assert.match(releases, /Recent preview changes/);
  assert.doesNotMatch(releases, /owner-trial-checklist|docs\/status\.md|launch gates|elevated worker|\bCI\b|worker/i);
});
test('website panel separates event conversion and receipt cohorts, rejects substitute zeros', () => {
  const data = { schemaVersion: 1, channel: 'web', synthetic: false, definition: 'Events, not people.',
    startDay: '2026-09-01', endDay: '2026-09-07',
    stages: { landing_view: 100, primary_cta_click: 50, download_click: null },
    sources: { search: 100, direct: null, referral: null, campaign: null, unknown: null },
    architectures: { arm64: null, x64: null, unknown: null },
    steps: [{ from: 'landing_view', to: 'primary_cta_click', rate: .5, reason: null },
      { from: 'primary_cta_click', to: 'download_click', rate: null, reason: 'events_below_50' }],
    linked: { minimumContributors: 50, definition: 'Linked opt-in accounts.', stages: { install_completed: null }, steps: [] } };
  const panels = websitePanels(data);
  assert.equal(panels.length, 3);
  assert.match(panels[2].rows[0].value, /Unavailable \/ not instrumented/);
  assert.match(panels[0].rows.find(row => row.label.includes('event ratio')).value, /50.0% \(50 \/ 100 events\)/);
  assert.match(panels[1].rows[0].value, /Insufficient data/);
  data.stages.primary_cta_click = 49;
  assert.throws(() => websitePanels(data));
  data.stages.primary_cta_click = 50;
  data.linked.stages.install_completed = 0;
  assert.throws(() => websitePanels(data));
});
