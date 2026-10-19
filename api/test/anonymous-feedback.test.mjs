import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { FileBackedCosmosContainer } from './support/file_backed_cosmos.mjs';
import { createAnonymousFeedbackHandler, feedbackLimits } from '../src/anonymous-feedback.mjs';

const now = new Date('2026-10-19T01:00:00Z');
const settings = { BUDLARK_ANONYMOUS_FEEDBACK: 'enabled',
  ANONYMOUS_FEEDBACK_HASH_SECRET: 'a'.repeat(32), ANONYMOUS_FEEDBACK_TRUSTED_IP_HEADER: 'x-azure-clientip' };
const payload = (overrides = {}) => ({ consent: true, deviceId: randomUUID(),
  requestId: randomUUID(), text: 'A calmer experience', ...overrides });
function cosmosMetadata(store) {
  store.read = async () => ({ resource: { partitionKey: { paths: ['/userId'] }, defaultTtl: -1 } });
  const batch = store.items.batch;
  store.items.batch = async (operations, partition) => {
    const result = await batch(operations, partition);
    return { ...result, ...(result.code === 200 ? { result: operations.map(() => ({ statusCode: 201 })) } : {}) };
  };
  return store;
}
function request(value, headers = {}, raw) {
  return new Request('https://example.invalid/api/feedback/anonymous', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-azure-clientip': '192.0.2.1', ...headers },
    body: raw ?? JSON.stringify(value),
  });
}
async function fixture(t) {
  const directory = resolve('test/.feedback-test', randomUUID());
  await mkdir(directory, { recursive: true });
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = resolve(directory, 'store.json');
  const store = cosmosMetadata(await FileBackedCosmosContainer.openFresh(path));
  const make = (overrides = {}) => createAnonymousFeedbackHandler({
    container: () => store, settings: () => settings, clock: () => now, ...overrides,
  });
  return { store, path, make, handler: make() };
}
const status = (code) => (error) => error.status === code;

test('durable receipt survives restart; duplicate does not spend quotas; conflict rejected', async t => {
  const { handler, path, make } = await fixture(t);
  const body = payload();
  const first = await handler(request(body));
  assert.equal(first.status, 201);
  assert.match(first.jsonBody.receiptId, /^[0-9a-f-]{36}$/);
  const reopened = cosmosMetadata(await FileBackedCosmosContainer.openExisting(path));
  const restarted = make({ container: () => reopened });
  assert.deepEqual((await restarted(request(body))).jsonBody, first.jsonBody);
  await assert.rejects(restarted(request({ ...body, rating: 1 })), status(409));
  for (let i = 1; i < feedbackLimits.devicePerDay; i++) {
    await restarted(request({ ...body, requestId: randomUUID() }));
  }
  await assert.rejects(restarted(request({ ...body, requestId: randomUUID() })), status(429));
  assert.deepEqual((await restarted(request(body))).jsonBody, first.jsonBody);
});

test('exact opt-in shape, scalar bounds, content type, malformed and streamed byte caps', async t => {
  const { handler } = await fixture(t);
  for (const bad of [
    payload({ consent: false }), payload({ text: ' ' }), payload({ text: 'x'.repeat(2001) }),
    payload({ rating: 0 }), payload({ rating: 6 }), payload({ rating: 1.5 }),
    payload({ accountId: 'private' }), payload({ habit: {} }), payload({ token: 'private' }),
    payload({ deviceId: 'stable-account' }), payload({ text: null }), [],
  ]) await assert.rejects(handler(request(bad)), status(400));
  await handler(request(payload({ text: undefined, rating: 5 })));
  await assert.rejects(handler(request(payload(), { 'content-type': 'text/plain' })), status(415));
  await assert.rejects(handler(request(null, {}, '{')), status(400));
  await assert.rejects(handler(request(null, {}, ' '.repeat(feedbackLimits.bodyBytes + 1))), status(413));
  await assert.rejects(handler(request(payload(), { 'content-length': '99999' })), status(413));
  await assert.rejects(handler(request(payload(), {}, '{"text":"\ud800"}')), status(400));
});

test('IP and global budgets hold independently under concurrent submissions', async t => {
  const { handler } = await fixture(t);
  const results = await Promise.allSettled(Array.from({ length: 18 }, () => handler(request(payload()))));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, feedbackLimits.ipPerDay);
  for (const r of results.filter(r => r.status === 'rejected')) assert.equal(r.reason.status, 429);
  for (let i = feedbackLimits.ipPerDay; i < feedbackLimits.globalPerDay; i++) {
    await handler(request(payload(), { 'x-azure-clientip': `198.51.100.${i}` }));
  }
  await assert.rejects(handler(request(payload(), { 'x-azure-clientip': '203.0.113.1' })), status(429));
});

test('concurrent identical retries save once; Unicode and equivalent IP forms obey bounds', async t => {
  const { handler } = await fixture(t);
  const body = payload({ text: '🌱'.repeat(2000) });
  const results = await Promise.all(Array.from({ length: 8 }, () => handler(request(body))));
  assert.equal(new Set(results.map(r => r.jsonBody.receiptId)).size, 1);
  assert.equal(results.filter(r => r.status === 201).length, 1);
  const upper = { ...body, deviceId: body.deviceId.toUpperCase(), requestId: body.requestId.toUpperCase() };
  assert.deepEqual((await handler(request(upper))).jsonBody, results[0].jsonBody);
  await assert.rejects(handler(request(payload({ text: '🌱'.repeat(2001) }))), status(400));
  for (let i = 0; i < feedbackLimits.ipPerDay; i++) {
    await handler(request(payload(), { 'x-azure-clientip': i % 2 ? '2001:db8::1' : '2001:0db8:0:0:0:0:0:1' }));
  }
  await assert.rejects(handler(request(payload(), { 'x-azure-clientip': '2001:db8::1' })), status(429));
});

test('retention is enforced logically and UTC-day quotas reset without losing receipts', async t => {
  const { make } = await fixture(t);
  let time = now;
  const handler = make({ clock: () => time });
  const body = payload();
  const saved = await handler(request(body));
  for (let i = 1; i < feedbackLimits.devicePerDay; i++) {
    await handler(request({ ...body, requestId: randomUUID() }));
  }
  time = new Date(now.getTime() + 86400000);
  await handler(request({ ...body, requestId: randomUUID() }));
  assert.deepEqual((await handler(request(body))).jsonBody, saved.jsonBody);
  time = new Date(now.getTime() + feedbackLimits.retentionSeconds * 1000);
  await assert.rejects(handler(request(body)), status(410));
});

test('absent enablement/secret/trusted IP/TTL/partition fail closed; failures never return receipt', async t => {
  const { make, store } = await fixture(t);
  for (const key of Object.keys(settings)) {
    await assert.rejects(make({ settings: () => ({ ...settings, [key]: undefined }) })(request(payload())), status(503));
  }
  for (const ip of ['', 'unknown', '192.0.2.1, 192.0.2.2']) {
    await assert.rejects(make()(request(payload(), { 'x-azure-clientip': ip })), status(503));
  }
  for (const metadata of [{}, { defaultTtl: 0 }, { defaultTtl: -1, partitionKey: { paths: ['/wrong'] } }]) {
    store.read = async () => ({ resource: metadata });
    await assert.rejects(make()(request(payload())), status(503));
  }
  store.read = async () => ({ resource: { defaultTtl: -1, partitionKey: { paths: ['/userId'] } } });
  store.items.batch = async () => ({});
  await assert.rejects(make()(request(payload())), status(503));
  for (const invalid of [
    { code: 200 }, { code: 202, result: Array(4).fill({ statusCode: 201 }) },
    { code: 200, result: [{ statusCode: 201 }] },
    { code: 207, result: Array(4).fill({ statusCode: 500 }) },
  ]) {
    store.items.batch = async () => invalid;
    await assert.rejects(make()(request(payload())), status(503));
  }
  store.items.batch = async () => { throw new Error('private failure'); };
  await assert.rejects(make()(request(payload())), status(503));
});

test('stored records contain only bounded feedback, keyed hashes, and expiring budgets', async t => {
  const { handler, path } = await fixture(t);
  const body = payload();
  await handler(request(body));
  const { readFile } = await import('node:fs/promises');
  const text = await readFile(path, 'utf8');
  assert.equal(text.includes(body.deviceId), false);
  assert.equal(text.includes('192.0.2.1'), false);
  const documents = JSON.parse(text).documents;
  assert.equal(documents.length, 4);
  assert.ok(documents.every(d => d.ttl > 0 && d.ttl <= feedbackLimits.retentionSeconds));
});
