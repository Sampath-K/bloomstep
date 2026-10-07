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
  assert.deepEqual(Object.keys(requests[0]).sort(), ['architecture','channel','event','eventId','source','synthetic'].sort());
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
  assert.match(home, /Get Bloomstep for Windows/);
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
test('public Windows downloads match the verified preview.12 universal release', () => {
  const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
  const config = JSON.parse(read('customer-config.json'));
  const home = read('index.html'), releases = read('releases/index.html');
  const assets = {
    arm64: {
      label: 'ARM64',
      sha256: '31652169df65a9e7decdc9d6418d06f6f6ce3448dffa4e186835dcf7375f8370',
    },
    x64: {
      label: 'x64',
      sha256: '398d493157a4456c85cd6432707f0fe1a9e7c43c84da6cd1e25981bb9d9051db',
    },
    universal: {
      label: 'Universal',
      sha256: 'fe115a7ada87858a55ba2610f778888079ee01a242f9ff74e18120a359292858',
    },
  };
  assert.equal(config.release.tag, 'v0.1.0-preview.12');
  assert.equal(config.release.universal.bytes, 21542145);
  for (const [architecture, asset] of Object.entries(assets)) {
    const filename = `Bloomstep-0.1.0-preview.12-windows-${architecture}-setup.exe`;
    const url = `https://github.com/Sampath-K/bloomstep/releases/download/v0.1.0-preview.12/${filename}`;
    assert.equal(config.release[architecture].url, url);
    assert.equal(config.release[architecture].sha256, asset.sha256);
    assert.ok(home.includes(url));
    assert.ok(releases.includes(url));
    assert.ok(releases.includes(`${asset.label} SHA-256: ${asset.sha256}`));
  }
  assert.match(home, /id="download-version">0\.1\.0-preview\.12</);
  for (const page of [home, releases]) {
    assert.equal((page.match(/data-universal-download/g) ?? []).length, 1);
    assert.match(page, /21\.54 MB \(21,542,145 bytes\)/);
    assert.doesNotMatch(page, /href="[^"]*download\/v0\.1\.0-preview\.9/);
  }
  assert.match(releases, /Launch after Finish remains unverified/);
  assert.match(releases, /0\.1\.0-preview\.8 - fresh-consent app reminder observations/);
});
test('website panel separates event conversion and receipt cohorts, rejects substitute zeros', () => {
  const data = { schemaVersion: 1, channel: 'web', synthetic: false, definition: 'Events, not people.',
    stages: { landing_view: 100, primary_cta_click: 50, download_click: null },
    sources: { search: 100, direct: null }, architectures: { x64: null },
    steps: [{ from: 'landing_view', to: 'primary_cta_click', rate: .5, reason: null }],
    linked: { minimumContributors: 50, definition: 'Linked opt-in accounts.', stages: { install_completed: null }, steps: [] } };
  const panels = websitePanels(data);
  assert.equal(panels.length, 2);
  assert.match(panels[0].rows.find(row => row.label.includes('event conversion')).value, /50.0%/);
  assert.match(panels[1].rows[0].value, /Insufficient data/);
  data.stages.primary_cta_click = 49;
  assert.throws(() => websitePanels(data));
  data.stages.primary_cta_click = 50;
  data.linked.stages.install_completed = 0;
  assert.throws(() => websitePanels(data));
});
