import test from 'node:test';
import assert from 'node:assert/strict';
import { createWebsiteHandlers, validateWebPayload, summarizeWebCounts, linkedWebFunnel, attributedActivationJourneys } from '../src/website-funnel.mjs';

const payload = { channel: 'web', event: 'landing_view', source: 'search', architecture: 'unknown',
  eventId: '00000000-0000-4000-8000-000000000001', synthetic: false };
const request = (value = payload, headers = {}) => ({
  headers: new Headers({ 'content-type': 'application/json', ...headers }),
  url: 'https://site.test/api/web/events', text: async () => typeof value === 'string' ? value : JSON.stringify(value),
});
function fixture({ clock = () => new Date('2026-10-05T23:59:59Z'), operationalEnabled = async () => {} } = {}) {
  const documents = new Map();
  let reads = 0;
  const store = {
    item: (id, partition) => ({ read: async () => { reads++; return { resource: documents.get(`${partition}:${id}`) }; } }),
    items: { batch: async operations => {
      for (const operation of operations) {
        const doc = operation.resourceBody;
        documents.set(`${doc.userId}:${doc.id}`, { ...structuredClone(doc), _etag: 'one' });
      }
      return { code: 200 };
    }, query: () => ({ fetchAll: async () => ({ resources: [] }) }) },
  };
  const handlers = createWebsiteHandlers({ container: () => store, authenticate: async () => ({ roles: ['Bloomstep.Admin'] }),
    clock, operationalEnabled });
  return { handlers, saved: () => {
    const values = [...documents.values()];
    const budget = values.find(doc => doc.type === 'website_budget');
    return budget ? { ...budget, days: Object.fromEntries(values.filter(doc => doc.type === 'website_daily').map(doc => [doc.day, doc])) } : null;
  }, reads: () => reads };
}
test('strict bounded schema rejects empty, malformed, abusive and reserved Store payloads', () => {
  for (const value of [null, {}, { ...payload, channel: 'store' }, { ...payload, ip: 'private' },
    { ...payload, event: 'install_completed' }, { ...payload, source: 'google.com' },
    { ...payload, architecture: 'other' }, { ...payload, eventId: 'bad' },
    { ...payload, utm: { utm_term: 'private' } }, { ...payload, utm: { utm_source: 'a'.repeat(49) } },
    { ...payload, utm: { utm_source: 'https://private' } }]) assert.throws(() => validateWebPayload(value));
  assert.equal(validateWebPayload(payload).channel, 'web');
});
test('DNT and GPC do not read store; malformed and oversized body never counted', async () => {
  const f = fixture();
  for (const header of [{ dnt: '1' }, { 'sec-gpc': '1' }]) {
    assert.equal((await f.handlers.ingest(request(payload, header))).status, 204);
  }
  assert.equal(f.reads(), 0);
  for (const value of ['', '{', 'a'.repeat(2049)]) {
    await assert.rejects(f.handlers.ingest(request(value)), error => [400, 413].includes(error.status));
  }
  await assert.rejects(f.handlers.ingest(request(payload, { 'content-length': '999999' })), e => e.status === 413);
  assert.equal(f.saved(), null);
});
test('stores UTC daily aggregate only; retry IDs and UTM values never persist', async () => {
  const f = fixture();
  const value = { ...payload, utm: { utm_source: 'newsletter' } };
  assert.equal((await f.handlers.ingest(request(value))).status, 202);
  assert.equal((await f.handlers.ingest(request(value))).status, 204);
  await assert.rejects(f.handlers.ingest(request({ ...value, event: 'download_click', architecture: 'x64' })), e => e.status === 400);
  const saved = JSON.stringify(f.saved());
  assert.match(saved, /2026-10-05/);
  assert.doesNotMatch(saved, /eventId|00000000|newsletter|utm_|site\.test|referrer/);
  assert.equal(f.saved().accepted, 1);
});
test('anonymous rates require 50 events in both stages, never imply unique people or missing zeros', () => {
  const data = summarizeWebCounts(null, '2026-10-05', '2026-10-05');
  assert.equal(data.stages.landing_view, null);
  assert.ok(data.steps.every(step => step.rate === null && step.reason === 'events_below_50'));
  assert.equal(data.channel, 'web');
  assert.equal(linkedWebFunnel([], '2026-10-05', '2026-10-05').stages.install_completed, null);
});
test('anonymous event conversion publishes at the exact threshold without low-day drilldown', () => {
  const document = { days: {
    '2026-10-04': { counts: { 'landing_view:search:unknown': 50, 'primary_cta_click:search:unknown': 49 }, accepted: 99 },
    '2026-10-05': { counts: { 'primary_cta_click:search:unknown': 1, 'download_click:search:x64': 50 }, accepted: 51 },
  } };
  const data = summarizeWebCounts(document, '2026-10-04', '2026-10-05');
  assert.equal(data.steps[0].rate, 1);
  assert.equal(data.steps[1].rate, 1);
  assert.equal(data.daily[0].counts, null);
  assert.equal(data.daily[1].counts, null);
  assert.match(data.definition, /not unique visitors/);
});
test('small subtractable source or architecture cells suppress the entire breakdown, never clamp ratios', () => {
  const data = summarizeWebCounts({ days: { '2026-10-05': { counts: {
    'landing_view:search:unknown': 50, 'landing_view:referral:unknown': 1,
    'primary_cta_click:search:unknown': 100,
    'download_click:search:arm64': 50, 'download_click:search:x64': 1,
  } } } }, '2026-10-05', '2026-10-05');
  assert.ok(Object.values(data.sources).every(value => value === null));
  assert.ok(Object.values(data.architectures).every(value => value === null));
  assert.equal(data.steps[0].rate, 100 / 51);
  assert.match(data.definition, /exceed 100%/);
});
test('bot/burst and unauthorized operator reads fail closed; synthetic cannot enter real document', async () => {
  const f = fixture();
  await assert.rejects(f.handlers.ingest(request(payload, { 'user-agent': 'Googlebot' })), e => e.status === 429);
  await f.handlers.ingest(request({ ...payload, synthetic: true }));
  assert.equal(f.saved().userId, '__website_synthetic');
  const unauthorized = createWebsiteHandlers({ container: () => assert.fail('Must not read'),
    authenticate: async () => ({ roles: [] }) });
  await assert.rejects(unauthorized.metrics(request()), e => e.status === 403);
});
test('source and global minute caps reject burst events; malformed retries never increment counts', async () => {
  let time = Date.parse('2026-10-05T10:00:00Z');
  const f = fixture({ clock: () => new Date(time) });
  for (let i = 1; i <= 100; i++) {
    time += 60000;
    const eventId = `00000000-0000-4000-8000-${i.toString(16).padStart(12, '0')}`;
    await f.handlers.ingest(request({ ...payload, eventId }));
  }
  time += 60000;
  await assert.rejects(f.handlers.ingest(request({ ...payload, eventId: '00000000-0000-4000-8000-000000000101' })), e => e.status === 429);
  assert.equal(f.saved().accepted, 100);
  const burst = fixture();
  for (let i = 1; i <= 30; i++) {
    await burst.handlers.ingest(request({ ...payload, eventId: `00000000-0000-4000-8000-${i.toString(16).padStart(12, '0')}` }));
  }
  await assert.rejects(burst.handlers.ingest(request({ ...payload, eventId: '00000000-0000-4000-8000-000000000031' })), e => e.status === 429);
  assert.equal(burst.saved().accepted, 30);
});
test('day boundary uses server UTC, daily TTL expires without future traffic, spending pause blocks writes', async () => {
  let time = Date.parse('2026-10-05T23:59:59Z');
  const f = fixture({ clock: () => new Date(time) });
  await f.handlers.ingest(request());
  time += 2000;
  await f.handlers.ingest(request({ ...payload, eventId: '00000000-0000-4000-8000-000000000002' }));
  assert.deepEqual(Object.keys(f.saved().days), ['2026-10-05','2026-10-06']);
  const day = f.saved().days['2026-10-05'];
  assert.equal(day.ttl, 89 * 86400 + 1);
  assert.equal(f.saved().ttl, -1);
  const paused = fixture({ operationalEnabled: async () => { throw Object.assign(Error('Paused'), { status: 503 }); } });
  await assert.rejects(paused.handlers.ingest(request()), e => e.status === 503);
  assert.equal(paused.saved(), null);
});
test('CAS conflicts fail closed, oversize chunked streams cancel before persistence', async () => {
  const conflict = createWebsiteHandlers({
    container: () => ({ item: () => ({ read: async () => ({ resource: null }) }),
      items: { batch: async () => { throw { code: 409 }; } } }),
    authenticate: async () => ({ roles: ['Bloomstep.Admin'] }),
  });
  await assert.rejects(conflict.ingest(request()), e => e.status === 429);
  const f = fixture();
  let cancelled = false;
  const body = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(2049)); },
    cancel() { cancelled = true; } });
  await assert.rejects(f.handlers.ingest({ ...request(), body }), e => e.status === 413);
  assert.equal(cancelled, true);
  assert.equal(f.saved(), null);
});
test('linked web cohorts require correct receipt origins, ordered stages and 50 distinct accounts', () => {
  const rows = [];
  const names = ['landing_view', 'download_click', 'install_completed', 'first_launch', 'signin_succeeded', 'first_checkin'];
  for (let user = 1; user <= 50; user++) {
    for (const [index, name] of names.entries()) {
      const properties = index < 2 ? { measurementSource: 'website_receipt', channel: 'website', platform: 'web' } :
        index < 4 ? { measurementSource: 'installer_receipt', platform: 'windows', channel: 'direct' } :
          index === 5 ? { result: 'did', localDay: '2026-10-05' } : {};
      rows.push({ userId: `user-${user}`, record: { id: `00000000-0000-4000-8000-${(user * 10 + index).toString(16).padStart(12, '0')}`,
        name, ts: `2026-10-05T10:0${index}:00.000Z`, properties } });
    }
  }
  const linked = linkedWebFunnel(rows, '2026-10-05', '2026-10-05');
  assert.equal(linked.stages.install_completed, 50);
  assert.equal(linked.steps[4].rate, 1);
  const smaller = linkedWebFunnel(rows.filter(row => row.userId !== 'user-50'), '2026-10-05', '2026-10-05');
  assert.equal(smaller.stages.first_checkin, null);
  assert.ok(smaller.steps.every(step => step.rate === null));
  const missingReceipt = linkedWebFunnel(rows.map(row => ({ ...row,
    record: { ...row.record, properties: { ...row.record.properties, measurementSource: undefined } } })), '2026-10-05', '2026-10-05');
  assert.equal(missingReceipt.stages.landing_view, null);
});
test('website-attributed activation reaches planted habit and same-habit completion without installer receipts', () => {
  const rows = [];
  const id = (user, index) => `00000000-0000-4000-8000-${(user * 10 + index).toString(16).padStart(12, '0')}`;
  const web = { measurementSource: 'website_receipt', channel: 'website', platform: 'web' };
  for (let user = 1; user <= 51; user++) {
    const habitId = `10000000-0000-4000-8000-${user.toString(16).padStart(12, '0')}`;
    rows.push({ userId: `user-${user}`, record: { id: id(user, 0), name: 'landing_view', ts: '2026-10-05T09:00:00.000Z', properties: web } });
    rows.push({ userId: `user-${user}`, record: { id: id(user, 1), name: 'download_click', ts: '2026-10-05T09:01:00.000Z', properties: web } });
    rows.push({ userId: `user-${user}`, record: { id: id(user, 2), name: 'recipe_created', ts: '2026-10-05T10:00:00.000Z',
      properties: { habitId, localDay: '2026-10-05', platform: 'windows' } } });
    // A first skip must not hide a later real completion; a different habit's completion never counts.
    rows.push({ userId: `user-${user}`, record: { id: id(user, 3), name: 'checkin', ts: '2026-10-05T10:30:00.000Z',
      properties: { habitId, result: 'skip', localDay: '2026-10-05', platform: 'windows' } } });
    if (user <= 50) rows.push({ userId: `user-${user}`, record: { id: id(user, 4), name: 'checkin', ts: '2026-10-05T11:00:00.000Z',
      properties: { habitId: user === 50 ? id(user, 9) : habitId, result: 'did', localDay: '2026-10-05', platform: 'windows' } } });
  }
  // Recipe before the website download is not attributable to that download.
  rows.push({ userId: 'early', record: { id: id(70, 1), name: 'download_click', ts: '2026-10-05T12:00:00.000Z', properties: web } });
  rows.push({ userId: 'early', record: { id: id(70, 2), name: 'recipe_created', ts: '2026-10-05T08:00:00.000Z',
    properties: { habitId: id(70, 5), localDay: '2026-10-05', platform: 'windows' } } });
  const linked = linkedWebFunnel(rows, '2026-10-05', '2026-10-05');
  assert.equal(linked.stages.install_completed, null, 'Old installer-ordered contract stays unchanged.');
  const activation = linked.activation;
  assert.equal(activation.schemaVersion, 1);
  assert.equal(activation.minimumContributors, 50);
  assert.deepEqual(Object.keys(activation.stages), ['website_receipt_download', 'recipe_created', 'first_completion']);
  assert.deepEqual(activation.stages, { website_receipt_download: 52, recipe_created: 51, first_completion: null });
  assert.deepEqual(activation.steps.map(step => step.rate), [51 / 52, null]);
  assert.deepEqual(activation.unobservable, ['download_completed', 'install_completed', 'first_launch_time', 'signin_succeeded']);
  const journeys = attributedActivationJourneys(rows, '2026-10-05', '2026-10-05');
  assert.equal(journeys.get('user-1').firstCompletion, '2026-10-05T11:00:00.000Z');
  assert.equal(journeys.get('user-50').firstCompletion, null);
  assert.equal(journeys.get('early').recipeCreated, null);
  const unlinked = linkedWebFunnel(rows.map(row => ({ ...row, record: { ...row.record,
    properties: { ...row.record.properties, measurementSource: undefined } } })), '2026-10-05', '2026-10-05');
  assert.deepEqual(unlinked.activation.stages, { website_receipt_download: null, recipe_created: null, first_completion: null });
});
test('production synthetic proof is aggregate-worker-only and does not expose real daily cells', async () => {
  const f = fixture();
  await assert.rejects(f.handlers.proof(request()), e => e.status === 403);
  const worker = createWebsiteHandlers({
    container: () => ({ item: (_id, partition) => ({
      read: async () => ({ resource: partition === '__website_synthetic' ? { accepted: 3 } : { accepted: 7 } }),
    }) }),
    authenticate: async () => ({ roles: [] }),
    authenticateProof: async () => ({ roles: ['Bloomstep.AggregateWriter'] }),
  });
  const result = await worker.proof(request());
  assert.deepEqual(result.jsonBody, { schemaVersion: 1, syntheticAccepted: 3, realAccepted: 7,
    definition: 'Lifetime accepted event counts only; synthetic and real partitions are isolated. No visitor identifiers or raw observations are stored.' });
});
