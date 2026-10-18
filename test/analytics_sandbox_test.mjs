import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { websiteConfig } from '../tool/analytics_config.mjs';
import { assertProductionClean, assertProductionSourceClean } from '../tool/analytics_site_build.mjs';
import { snapshot } from '../tool/acquisition_snapshot.mjs';
import { browserLaunchOptions, collectionEvents } from '../tool/analytics_ga4_staging_check.mjs';
import { initializeSandbox } from '../tool/analytics_browser.mjs';

test('GA4 withdrawal disables transport synchronously before consent update and unload', () => {
  const calls = [];
  let change;
  const consent = { checked: false, addEventListener: (_, handler) => { change = handler; } };
  const status = {};
  const win = {
    navigator: {}, location: { search: '?private=secret', pathname: '/', origin: 'https://example.test',
      reload: () => {
        assert.equal(win['ga-disable-G-TEST123'], true);
        calls.push('reload');
      } },
    history: { replaceState() {} },
  };
  const doc = {
    getElementById: id => id === 'sandbox-consent' ? consent : status,
    querySelectorAll: () => [],
    createElement: () => ({ setAttribute() {} }),
    head: { append() {} },
  };
  initializeSandbox({ GA4_ID: 'G-TEST123' }, win, doc);
  consent.checked = true;
  change();
  const commands = win.dataLayer.map(args => [...args]);
  assert.deepEqual(commands.map(args => args[0]), ['consent', 'js', 'config', 'event']);
  assert.deepEqual(commands[0], ['consent', 'default', {
    analytics_storage: 'granted', ad_storage: 'denied',
    ad_user_data: 'denied', ad_personalization: 'denied',
  }]);
  const settings = [...win.dataLayer.find(args => args[0] === 'config')][2];
  assert.equal(settings.page_title, 'Budlark sandbox');
  assert.equal(settings.page_location, 'https://example.test/');
  assert.equal(settings.page_referrer, '');
  win.gtag = (...args) => {
    assert.equal(win['ga-disable-G-TEST123'], true);
    calls.push(args);
  };
  consent.checked = false;
  change();
  assert.equal(calls[0][0], 'consent');
  assert.equal(calls[0][2].analytics_storage, 'denied');
  assert.equal(calls[1], 'reload');
});

test('production site is free of vendor code and domains', assertProductionClean);
test('production scanner permits the factual production-off and staging-only privacy disclosure', async () => {
  const html = await readFile(new URL('../site/index.html', import.meta.url), 'utf8');
  const disclosure = html.match(/<p>No third-party product analytics tools are enabled on the public website\.[\s\S]*?<\/p>/)?.[0];
  assert.ok(disclosure, 'The production privacy disclosure must remain present');
  assert.match(disclosure, /No third-party product analytics tools are enabled on the public website/);
  assert.match(disclosure, /separate testing website uses Google Analytics only after a tester opts in/);
  assert.match(disclosure, /test visits have been received there/);
  assert.match(disclosure, /does not mean customer activity or analytics are enabled on the public site/);
  assert.doesNotThrow(() => assertProductionSourceClean(disclosure, 'disclosure.html'));
});
test('production scanner rejects vendor resources, domains and executable SDK markers', () => {
  const examples = [
    ['script.html', '<script src="https://www.googletagmanager.com/gtag/js?id=G-TEST"></script>'],
    ['script.html', '<script src="/assets/posthog.js"></script>'],
    ['link.html', '<link rel="preconnect" href="https://eu.i.posthog.com">'],
    ['img.html', '<img src="https://www.google-analytics.com/collect">'],
    ['iframe.html', '<iframe src="https://www.clarity.ms/tag/test"></iframe>'],
    ['fetch.html', '<script>fetch("https://static.cloudflareinsights.com/beacon.min.js")</script>'],
    ['domain.html', '<p>https://eu.i.posthog.com</p>'],
    ['domain.html', '<p>https://api.aptabase.com</p>'],
    ['domain.html', '<p>https://ingest.sentry.io</p>'],
    ['domain.html', '<p>https://browser.sentry-cdn.com</p>'],
    ['inline.html', '<script>gtag("config", "G-TEST");</script>'],
    ['inline.html', '<script>posthog.init("phc_test");</script>'],
    ['inline.html', '<script>clarity("start");</script>'],
    ['inline.html', '<script>window["posthog"] = [];</script>'],
    ['inline.html', '<script>window.dataLayer = [];</script>'],
    ['attribute.html', '<button onclick="gtag(\'event\', \'click\')">Click</button>'],
    ['style.html', '<style>body { background: url("/assets/posthog.png"); }</style>'],
    ['quoted-attribute.html', '<img alt=">" src="https://eu.i.posthog.com/pixel">'],
    ['unclosed.html', '<script>window.posthog = [];'],
    ['vendor.mjs', 'import * as Sentry from "@sentry/browser";'],
    ['vendor.js', 'window.gtag = function () {};'],
    ['vendor.js', 'window.clarity = function () {};'],
    ['vendor.json', '{"sdk":"aptabase"}'],
    ['sandbox.html', '<input id="sandbox-consent">'],
  ];
  for (const [path, source] of examples) {
    assert.throws(() => assertProductionSourceClean(source, path),
      /Production contains third-party analytics/, `${path}: ${source}`);
  }
});
test('missing keys disable each vendor and invalid IDs fail explicitly', () => {
  assert.equal(websiteConfig({}).GA4_ID, '');
  assert.equal(websiteConfig({}).POSTHOG_REGION, 'EU');
  assert.throws(() => websiteConfig({ POSTHOG_REGION: 'elsewhere' }));
  assert.throws(() => websiteConfig({ GA4_ID: '</script>' }));
});
test('release snapshot preserves unknown traffic instead of inventing zeros', async () => {
  const data = await snapshot({ repo: 'Sampath-K/budlark', token: 'fake',
    request: async url => url.includes('/releases?')
      ? { ok: true, json: async () => [{ tag_name: 'v1', published_at: '2026-10-09', assets: [{ id: 1, name: 'test.exe', download_count: 7 }] }] }
      : { ok: false, status: 403 } });
  assert.equal(data.releases[0].assets[0].downloads, 7);
  assert.equal(data.traffic.views.available, false);
  assert.equal(data.traffic.views.status, 403);
});
test('unexpected GitHub failures stop the snapshot', async () => {
  await assert.rejects(snapshot({ repo: 'Sampath-K/budlark', token: 'fake',
    request: async () => ({ ok: false, status: 500 }) }), /HTTP 500/);
});
test('release builds cannot enable sandbox even with compile-time flag', async () => {
  const source = await readFile(new URL('../lib/services/analytics_sandbox.dart', import.meta.url), 'utf8');
  assert.match(source, /!kReleaseMode && bool\.fromEnvironment\('BUDLARK_ANALYTICS_SANDBOX'\)/);
});
test('live GA4 evidence excludes identifiers and parses batched event bodies', () => {
  const events = collectionEvents('https://region1.google-analytics.com/g/collect?tid=G-TEST&cid=private-client&sid=private-session&gcs=G101',
    'en=page_view&dl=https%3A%2F%2Fexample.test%2F\nen=sandbox_download_click&ep.architecture=x64');
  assert.equal(events.length, 2);
  assert.equal(events[1].fields.en, 'sandbox_download_click');
  assert.equal(events[1].fields['ep.architecture'], 'x64');
  assert.equal(events[0].fields.gcs, 'G101');
  assert.equal(JSON.stringify(events).includes('private-client'), false);
  assert.equal(JSON.stringify(events).includes('private-session'), false);
  assert.deepEqual(collectionEvents('https://example.test/g/collect?en=page_view'), []);
  assert.throws(() => collectionEvents('https://www.google-analytics.com/g/collect?dl=PRIVATE_SANDBOX_SENTINEL'),
    /Private query/);
});
test('live GA4 evidence rejects report-excluded debug and internal traffic parameters', () => {
  for (const parameter of ['_dbg=1', 'ep.debug_mode=1', 'tt=internal', 'ep.traffic_type=internal']) {
    assert.throws(() => collectionEvents(`https://www.google-analytics.com/g/collect?tid=G-TEST&${parameter}`,
      'en=page_view'), /report-excluded/);
  }
});
test('live GA4 check is headless by default and headed only by explicit opt-in', () => {
  assert.equal(browserLaunchOptions({}).headless, true);
  assert.equal(browserLaunchOptions({ ANALYTICS_HEADED: '1' }).headless, false);
  assert.equal(browserLaunchOptions({ ANALYTICS_HEADED: 'yes' }).headless, true);
  assert.equal(browserLaunchOptions({ CHROME_PATH: 'C:\\edge.exe' }).executablePath, 'C:\\edge.exe');
});
