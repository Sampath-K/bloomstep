import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { websiteConfig } from '../tool/analytics_config.mjs';
import { assertProductionClean } from '../tool/analytics_site_build.mjs';
import { snapshot } from '../tool/acquisition_snapshot.mjs';

test('production site is free of vendor code and domains', assertProductionClean);
test('missing keys disable each vendor and invalid IDs fail explicitly', () => {
  assert.equal(websiteConfig({}).GA4_ID, '');
  assert.equal(websiteConfig({}).POSTHOG_REGION, 'EU');
  assert.throws(() => websiteConfig({ POSTHOG_REGION: 'elsewhere' }));
  assert.throws(() => websiteConfig({ GA4_ID: '</script>' }));
});
test('release snapshot preserves unknown traffic instead of inventing zeros', async () => {
  const data = await snapshot({ repo: 'Sampath-K/bloomstep', token: 'fake',
    request: async url => url.includes('/releases?')
      ? { ok: true, json: async () => [{ tag_name: 'v1', published_at: '2026-10-09', assets: [{ id: 1, name: 'test.exe', download_count: 7 }] }] }
      : { ok: false, status: 403 } });
  assert.equal(data.releases[0].assets[0].downloads, 7);
  assert.equal(data.traffic.views.available, false);
  assert.equal(data.traffic.views.status, 403);
});
test('unexpected GitHub failures stop the snapshot', async () => {
  await assert.rejects(snapshot({ repo: 'Sampath-K/bloomstep', token: 'fake',
    request: async () => ({ ok: false, status: 500 }) }), /HTTP 500/);
});
test('release builds cannot enable sandbox even with compile-time flag', async () => {
  const source = await readFile(new URL('../lib/services/analytics_sandbox.dart', import.meta.url), 'utf8');
  assert.match(source, /!kReleaseMode && bool\.fromEnvironment\('BLOOMSTEP_ANALYTICS_SANDBOX'\)/);
});
