import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createWebsiteHandlers, validateWebPayload, summarizeWebCounts } from '../src/website-funnel.mjs';
import { FileBackedCosmosContainer } from './support/file_backed_cosmos.mjs';

const touch = { source: 'campaign', referrerDomain: 'google.com', campaignSource: 'newsletter',
  campaignMedium: 'email', campaignName: 'launch' };
const payload = () => ({ channel: 'web', event: 'landing_view', source: 'campaign', architecture: 'unknown',
  eventId: randomUUID(), synthetic: true, observedAt: '2026-10-09T04:00:00.000Z',
  attribution: { firstTouch: touch, lastTouch: touch } });
const request = value => ({ headers: new Headers({ 'content-type': 'application/json' }),
  text: async () => JSON.stringify(value) });

test('strict bounded attribution rejects arbitrary strings, mismatched source, extras and URL data', () => {
  assert.equal(validateWebPayload(payload()).attribution.firstTouch.campaignName, 'launch');
  for (const mutation of [{ referrerDomain: 'private.example' }, { campaignName: 'alice' }, { url: 'secret' }]) {
    const value = payload();
    value.attribution.firstTouch = { ...touch, ...mutation };
    assert.throws(() => validateWebPayload(value));
  }
  assert.throws(() => validateWebPayload({ ...payload(), source: 'direct' }));
});

test('persisted dedup survives restart, changed retries conflict, UTC timing fails closed', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'bloomstep-it-attribution-'));
  const path = join(dir, 'collector.json');
  let store = await FileBackedCosmosContainer.openFresh(path);
  let time = Date.parse('2026-10-09T04:00:00Z');
  const handlers = () => createWebsiteHandlers({ container: () => store,
    authenticate: async () => ({ roles: ['Bloomstep.Admin'] }), clock: () => new Date(time) });
  try {
    const value = payload();
    assert.equal((await handlers().ingest(request(value))).status, 202);
    await store.close();
    store = await FileBackedCosmosContainer.openExisting(path);
    assert.equal((await handlers().ingest(request(value))).status, 204);
    await assert.rejects(handlers().ingest(request({ ...value, event: 'download_click' })), e => e.status === 400);
    const saved = JSON.parse(await readFile(path, 'utf8')).documents;
    assert.equal(saved.find(doc => doc.type === 'website_daily').accepted, 1);
    assert.equal(saved.find(doc => doc.type === 'website_daily').attributionCounts['firstTouch:landing_view:campaignSource:newsletter'], 1);
    assert.doesNotMatch(JSON.stringify(saved), new RegExp(value.eventId));
    time += 300000;
    await assert.rejects(handlers().ingest(request(value)), e => e.status === 400);
    await assert.rejects(handlers().ingest(request({ ...payload(), observedAt: '2026-10-10T04:00:00Z' })), e => e.status === 400);
  } finally { await store.close(); await rm(dir, { recursive: true }); }
});

test('attribute vectors suppress whole marginal dimensions, never expose daily cells', () => {
  const counts = { 'landing_view:campaign:unknown': 100 };
  const attributionCounts = { 'firstTouch:landing_view:campaignSource:newsletter': 99,
    'firstTouch:landing_view:campaignSource:unknown': 1,
    'lastTouch:landing_view:referrerDomain:google.com': 100 };
  const summary = summarizeWebCounts({ days: { '2026-10-09': { counts, attributionCounts, accepted: 100 } } }, '2026-10-09', '2026-10-09');
  assert.ok(Object.values(summary.acquisition.firstTouch.landing_view.campaignSource).every(value => value === null));
  assert.equal(summary.acquisition.lastTouch.landing_view.referrerDomain['google.com'], 100);
  assert.equal(summary.daily[0].counts, null);
});

test('two collectors racing the same timestamped retry commit at most one event', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'bloomstep-it-attribution-'));
  const store = await FileBackedCosmosContainer.openFresh(join(dir, 'collector.json'));
  const create = () => createWebsiteHandlers({ container: () => store,
    authenticate: async () => ({ roles: [] }), clock: () => new Date('2026-10-09T04:00:00Z') });
  try {
    const value = payload(), a = create(), b = create();
    const results = await Promise.allSettled([a.ingest(request(value)), b.ingest(request(value))]);
    assert.equal(results.filter(result => result.status === 'fulfilled' && result.value.status === 202).length, 1);
    assert.ok(results.every(result => result.status === 'fulfilled' || result.reason.status === 429));
    assert.equal((await create().ingest(request(value))).status, 204);
    const reopened = await FileBackedCosmosContainer.openExisting(store.path);
    assert.equal((await reopened.item('2026-10-09', '__website_synthetic').read()).resource.accepted, 1);
    await reopened.close();
  } finally { await store.close(); await rm(dir, { recursive: true }); }
});
