import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createHandlers, ServiceError } from '../src/backend.mjs';
import { aggregateEvents, previewLimits } from '../src/engagement.mjs';
import { newerSetting } from '../src/contracts.mjs';

const now = '2026-09-01T12:00:00.000Z';
const userId = 'a'.repeat(64);
const teamId = 'b'.repeat(64);
const voice = () => ({ id: randomUUID(), kind: 'Idea', body: 'Private question', rating: null, ts: now });
const payload = (overrides = {}) => ({ habits: [], checkins: [], reflections: [], voice: [], events: [], ...overrides });
const request = (method, data, query = {}, params = {}) => ({
  method, params, query: new URLSearchParams(query), headers: new Headers(),
  text: async () => JSON.stringify(data),
});

function harness({ roles = ['Bloomstep.Admin'], disabled = false, apiDisabled = false, aggregatesDisabled = false, limits = {}, beforeBatch, failAudit = false, beforeQuery } = {}) {
  const documents = new Map();
  const writes = [];
  let revision = 0;
  const key = (id, partition) => `${partition}/${id}`;
  const put = document => {
    const value = structuredClone({ ...document, _etag: String(++revision) });
    documents.set(key(document.id, document.userId), value);
    return structuredClone(value);
  };
  const read = (id, partition) => structuredClone(documents.get(key(id, partition)));
  const store = {
    item: (id, partition) => ({
      read: async () => ({ resource: read(id, partition) }),
      replace: async (document, options) => {
        if (options?.accessCondition?.condition !== read(id, partition)?._etag) throw { code: 412 };
        return { resource: put(document) };
      },
      delete: async () => { documents.delete(key(id, partition)); },
    }),
    items: {
      create: async document => {
        if (failAudit && document.type === 'audit') throw new Error('Audit storage failed');
        if (read(document.id, document.userId)) throw { code: 409 };
        writes.push(document);
        return { resource: put(document) };
      },
      batch: async (operations, partition) => {
        await beforeBatch?.(operations, partition, { put, read });
        for (const operation of operations) {
          const current = read(operation.id ?? operation.resourceBody.id, partition);
          if (operation.operationType === 'Create' ? !!current : !current || operation.operationType !== 'Delete' && current._etag !== operation.ifMatch) return { code: 412 };
        }
        for (const operation of operations) {
          if (operation.operationType === 'Delete') documents.delete(key(operation.id, partition));
          else { writes.push(operation.resourceBody); put(operation.resourceBody); }
        }
        return { code: 200 };
      },
      query: (spec, options = {}) => ({
        fetchAll: async () => {
          await beforeQuery?.(spec, { put, read });
          const parameters = Object.fromEntries((spec.parameters ?? []).map(p => [p.name, p.value]));
          let rows = [...documents.values()].filter(row => !options.partitionKey || row.userId === options.partitionKey);
          if (spec.query.includes('c.type IN')) rows = rows.filter(row => ['habits', 'checkins', 'reflections', 'voice', 'settings'].includes(row.type));
          else if (spec.query.includes('c.type = "voice"')) rows = rows.filter(row => row.type === 'voice');
          else if (spec.query.includes('c.type = "events"')) rows = rows.filter(row => row.type === 'events' && (!parameters['@start'] || row.record.ts >= parameters['@start'] && row.record.ts < parameters['@end']));
          else if (spec.query.includes('c.type = "account"')) rows = rows.filter(row => row.type === 'account');
          else if (spec.query.includes('c.type = "aggregate"')) rows = rows.filter(row => row.type === 'aggregate');
          else if (spec.query.includes('c.type != "account"')) rows = rows.filter(row => row.type !== 'account');
          rows.sort((a, b) => a.userId.localeCompare(b.userId) || a.id.localeCompare(b.id));
          if (parameters['@after']) rows = rows.filter(row => `${row.userId}:${row.id}` > parameters['@after']);
          const top = Number(/TOP (\d+)/.exec(spec.query)?.[1] ?? rows.length);
          return { resources: structuredClone(rows.slice(0, top)) };
        },
      }),
    },
  };
  const handlers = createHandlers({
    container: () => store,
    authenticate: async () => ({ userId: roles.length ? teamId : userId, roles }),
    clock: () => new Date(now), environment: () => ({
      BLOOMSTEP_ENGAGEMENT_DISABLED: String(disabled), BLOOMSTEP_API_DISABLED: String(apiDisabled), BLOOMSTEP_AGGREGATES_DISABLED: String(aggregatesDisabled),
    }),
    limits: { ...previewLimits, ...limits },
  });
  return { ...handlers, put, read, documents, writes, store };
}

test('metrics requires explicit admin role and reports four bounded categories', async () => {
  const denied = harness({ roles: [] });
  await assert.rejects(denied.metrics(request('GET')), error => error.status === 403);
  const h = harness();
  const result = await h.metrics(request('GET'));
  assert.equal(result.jsonBody.minimumCohort, 50);
  assert.equal(result.jsonBody.endDay, '2026-09-01');
  assert.equal(result.jsonBody.dashboards.endDay, '2026-08-31');
  assert.equal(result.jsonBody.dashboards.observedThrough, '2026-09-01');
  assert.deepEqual(Object.keys(result.jsonBody.categories), ['activationRetention', 'reminderLearning', 'voiceRatings', 'sharingExperiment']);
  assert.equal(h.writes.filter(row => row.action === 'metrics_read').length, 1);
  await assert.rejects(h.metrics(request('GET', null, { days: '31' })), error => error.status === 400);
  await assert.rejects(h.metrics(request('GET', null, { private: 'yes' })), error => error.status === 400);
});

test('daily aggregates are deterministic, deduplicate IDs and suppress small cohorts without private output', () => {
  const rows = Array.from({ length: 50 }, (_, index) => ({
    userId: String(index), record: { id: randomUUID(), name: 'checkin', ts: now },
  }));
  const aggregate = aggregateEvents([...rows, rows[0]], '2026-09-01', '2026-09-01');
  assert.deepEqual(aggregate, aggregateEvents([...rows].reverse(), '2026-09-01', '2026-09-01'));
  assert.equal(aggregate.daily[0].counts.checkin, 50);
  assert.equal(aggregate.daily[0].users, 50);
  assert.equal(aggregateEvents(rows.slice(0, 49), '2026-09-01', '2026-09-01').daily[0].counts, null);
  assert.equal(JSON.stringify(aggregate).includes('userId'), false);
  assert.equal(aggregate.categories.voiceRatings.ratings, null);
  assert.equal(aggregate.categories.sharingExperiment.experiments, null);
});

test('feedback reads are audited before disclosure and paginate without skipping same-partition records', async () => {
  const h = harness();
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  for (let index = 0; index < 3; index++) h.put({ id: `voice:${index}`, userId, type: 'voice', record: { ...voice(), status: 'received', replies: '[]' } });
  const first = await h.admin(request('GET', null, { limit: '2' }));
  assert.equal(first.jsonBody.feedback.length, 2);
  assert.ok(first.jsonBody.nextCursor);
  const second = await h.admin(request('GET', null, { limit: '2', cursor: first.jsonBody.nextCursor }));
  assert.equal(second.jsonBody.feedback.length, 1);
  assert.equal(second.jsonBody.nextCursor, null);
  assert.equal(h.writes.filter(row => row.action === 'feedback_read').length, 2);
  assert.equal(h.writes.filter(row => row.type === 'audit').some(row => JSON.stringify(row).includes('Private question')), false);
  await assert.rejects(h.admin(request('GET', null, { cursor: 'not-a-cursor' })), error => error.status === 400);
});

test('reply keeps legacy strings and status, bounded thread, atomic audit and deletion gate', async () => {
  const h = harness();
  const record = voice();
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  h.put({ id: `voice:${record.id}`, userId, type: 'voice', record: { ...record, status: 'received', replies: '[]' } });
  await h.admin(request('POST', { id: record.id, status: 'shipped', reply: 'Fixed privately' }, {}, { userId }));
  const saved = h.read(`voice:${record.id}`, userId).record;
  assert.equal(saved.status, 'shipped');
  assert.deepEqual(JSON.parse(saved.replies), [`${now}: Fixed privately`]);
  assert.equal(h.writes.filter(row => row.action === 'feedback_reply' && row.userId === userId).length, 1);
  h.put({ id: 'account', userId, type: 'account', deleted: true });
  await assert.rejects(h.admin(request('POST', { id: record.id, status: 'planned', reply: 'Again' }, {}, { userId })), error => error.status === 410);
  const capped = harness({ limits: { replies: 1 } });
  capped.put({ id: 'account', userId, type: 'account', deleted: false });
  capped.put({ id: `voice:${record.id}`, userId, type: 'voice', record: saved });
  await assert.rejects(capped.admin(request('POST', { id: record.id, status: 'planned', reply: 'Again' }, {}, { userId })), error => error.status === 429);
});

test('deletion winning between reply read and commit rejects both reply and its audit', async () => {
  const record = voice();
  const h = harness({ beforeBatch: (operations, partition, store) => {
    if (partition === userId && operations.some(op => op.resourceBody?.type === 'voice')) store.put({ id: 'account', userId, type: 'account', deleted: true });
  } });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  h.put({ id: `voice:${record.id}`, userId, type: 'voice', record: { ...record, status: 'received', replies: '[]' } });
  await assert.rejects(h.admin(request('POST', { id: record.id, status: 'shipped', reply: 'Fix' }, {}, { userId })), error => error.status === 409);
  assert.equal(h.read(`voice:${record.id}`, userId).record.status, 'received');
  assert.equal(h.writes.some(row => row.action === 'feedback_reply'), false);
});

test('immutable retries do not replace private feedback or consume account record caps', async () => {
  const h = harness({ roles: [], limits: { records: { ...previewLimits.records, voice: 1 } } });
  const record = voice();
  await h.sync(request('POST', payload({ voice: [record] })));
  await h.sync(request('POST', payload({ voice: [{ ...record, body: 'Changed text' }] })));
  assert.equal(h.read(`voice:${record.id}`, userId).record.body, record.body);
  await assert.rejects(h.sync(request('POST', payload({ voice: [voice()] }))), error => error.status === 429);
  assert.equal(h.read('account', userId).counts.voice, 1);
});

test('telemetry daily account cap is atomic and retry acknowledgement stays compatible', async () => {
  const h = harness({ roles: [], limits: { eventsPerDay: 1 } });
  const event = { id: randomUUID(), name: 'checkin', ts: now };
  const first = await h.sync(request('POST', payload({ events: [event] })));
  assert.deepEqual(first.jsonBody.acknowledgedEvents, [event.id]);
  await h.sync(request('POST', payload({ events: [event] })));
  await assert.rejects(h.sync(request('POST', payload({ events: [{ ...event, id: randomUUID() }] }))), error => error.status === 429);
  await assert.rejects(h.sync(request('POST', payload({ events: [{ ...event, privateText: 'secret' }] }))), error => error.status === 400);
});

test('kill switch blocks engagement, preserves garden sync and account deletion', async () => {
  const h = harness({ disabled: true });
  await assert.rejects(h.metrics(request('GET')), error => error.status === 503);
  await assert.rejects(h.admin(request('GET')), error => error.status === 503);
  const customer = harness({ roles: [], disabled: true });
  await customer.sync(request('POST', payload()));
  await assert.rejects(customer.sync(request('POST', payload({ voice: [voice()] }))), error => error.status === 503);
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  assert.equal((await customer.deleteAccount(deletion)).status, 204);
});

test('global lifetime operation cap fails closed without disclosing unaudited feedback', async () => {
  const h = harness({ limits: { lifetimeOperations: 1 } });
  await h.admin(request('GET'));
  await assert.rejects(h.admin(request('GET')), error => error.status === 429);
  assert.equal(h.writes.filter(row => row.action === 'feedback_read').length, 1);
  assert.equal(newerSetting({ value: 'true', updated: now }, { value: 'false', updated: now }), true);
  assert.ok(new ServiceError(429, 'cap') instanceof Error);
});

test('audit failure prevents feedback response and deleted targets are not exposed', async () => {
  const failed = harness({ failAudit: true });
  await assert.rejects(failed.admin(request('GET')), /Audit storage failed/);
  const h = harness();
  h.put({ id: 'account', userId, type: 'account', deleted: true });
  h.put({ id: 'voice:orphan', userId, type: 'voice', record: voice() });
  assert.deepEqual((await h.admin(request('GET'))).jsonBody.feedback, []);
});

test('metrics includes microsecond midnight envelopes, excludes deleted and invalid events and fails closed on scan overflow', async () => {
  const h = harness();
  for (let index = 0; index < 50; index++) {
    const partition = index.toString(16).padStart(64, '0');
    h.put({ id: 'account', userId: partition, type: 'account', deleted: false });
    h.put({ id: `events:${index}`, userId: partition, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: '2026-09-01T00:00:00.000000Z' } });
  }
  h.put({ id: 'account', userId, type: 'account', deleted: true });
  h.put({ id: 'events:deleted', userId, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now } });
  h.put({ id: 'events:private', userId: '0'.repeat(64), type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now, body: 'private' } });
  const result = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody;
  assert.equal(result.daily[0].counts.checkin, 50);
  const capped = harness({ limits: { metricRecords: 1 } });
  for (let index = 0; index < 2; index++) capped.put({ id: `events:${index}`, userId, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now } });
  await assert.rejects(capped.metrics(request('GET')), error => error.status === 429);
});

test('daily and per-event suppression does not publish sparse voice or sharing cohorts', () => {
  const rows = Array.from({ length: 50 }, (_, index) => ({ userId: String(index), record: { id: randomUUID(), name: 'checkin', ts: now } }));
  rows.push({ userId: '0', record: { id: randomUUID(), name: 'feedback_submitted', ts: now } });
  const result = aggregateEvents(rows, '2026-09-01', '2026-09-01');
  assert.equal(result.daily[0].counts.feedback_submitted, null);
  assert.equal(result.categories.voiceRatings.feedbackSubmitted, null);
  assert.equal(result.daily[0].counts.share_initiated, null);
});

test('reply retries with requestId are idempotent and conflicting key reuse rejects', async () => {
  const h = harness();
  const record = voice();
  const input = { id: record.id, status: 'under review', reply: 'We are looking.', requestId: randomUUID() };
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  h.put({ id: `voice:${record.id}`, userId, type: 'voice', record: { ...record, status: 'received', replies: '[]' } });
  await h.admin(request('POST', input, {}, { userId }));
  await h.admin(request('POST', input, {}, { userId }));
  assert.equal(JSON.parse(h.read(`voice:${record.id}`, userId).record.replies).length, 1);
  assert.equal(h.writes.filter(row => row.action === 'feedback_reply').length, 1);
  await assert.rejects(h.admin(request('POST', { ...input, reply: 'Different' }, {}, { userId })), error => error.status === 409);
});

test('legacy reply retries are coalesced and concurrent replies cannot overwrite each other', async () => {
  const record = voice();
  const input = { id: record.id, status: 'planned', reply: 'Queued' };
  const h = harness();
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  h.put({ id: `voice:${record.id}`, userId, type: 'voice', record: { ...record, status: 'received', replies: '[]' } });
  await h.admin(request('POST', input, {}, { userId }));
  await h.admin(request('POST', input, {}, { userId }));
  assert.equal(JSON.parse(h.read(`voice:${record.id}`, userId).record.replies).length, 1);
  const raced = harness({ beforeBatch: (operations, partition, store) => {
    if (partition === userId && operations.some(op => op.resourceBody?.type === 'voice')) {
      const current = store.read(`voice:${record.id}`, userId);
      store.put({ ...current, record: { ...current.record, status: 'shipped' } });
    }
  } });
  raced.put({ id: 'account', userId, type: 'account', deleted: false });
  raced.put({ id: `voice:${record.id}`, userId, type: 'voice', record: { ...record, status: 'received', replies: '[]' } });
  await assert.rejects(raced.admin(request('POST', input, {}, { userId })), error => error.status === 409);
  assert.equal(raced.read(`voice:${record.id}`, userId).record.status, 'shipped');
  assert.equal(raced.writes.some(row => row.type === 'audit'), false);
});

test('full API kill switch blocks garden work but never blocks existing-account deletion', async () => {
  const h = harness({ roles: [], apiDisabled: true });
  await assert.rejects(h.sync(request('POST', payload())), error => error.status === 503);
  assert.equal(h.documents.size, 0);
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  assert.equal((await h.deleteAccount(deletion)).status, 204);
});

test('metrics has a conservative dedicated read-volume ceiling', async () => {
  const h = harness({ limits: { adminActions: { ...previewLimits.adminActions, metrics_read: { daily: 1, lifetime: 1 } } } });
  await h.metrics(request('GET'));
  await assert.rejects(h.metrics(request('GET')), error => error.status === 429);
});

test('customer feedback sync → private team reply → customer sync preserves client record shape', async () => {
  const customer = harness({ roles: [] });
  const team = createHandlers({
    container: () => customer.store,
    authenticate: async () => ({ userId: teamId, roles: ['Bloomstep.Admin'] }),
    clock: () => new Date(now),
  });
  const record = voice();
  await customer.sync(request('POST', payload({ voice: [record] })));
  await team.admin(request('POST', { id: record.id, status: 'not planned', reply: 'Reason supplied privately', requestId: randomUUID() }, {}, { userId }));
  const retried = await customer.sync(request('POST', payload({ voice: [record] })));
  assert.equal(retried.jsonBody.voice[0].status, 'not planned');
  assert.deepEqual(JSON.parse(retried.jsonBody.voice[0].replies), [`${now}: Reason supplied privately`]);
  assert.equal('replyRequests' in retried.jsonBody.voice[0], false);
  const garden = (await customer.sync(request('GET'))).jsonBody;
  assert.deepEqual(Object.keys(garden), ['habits', 'checkins', 'reflections', 'voice', 'settings']);
});

test('recipe/settings ties, attained stage and immutable events survive backend retries', async () => {
  const h = harness({ roles: [] });
  const habit = { id: randomUUID(), aspiration: 'Calm', anchor: 'Coffee', behavior: 'Breathe', celebration: 'Smile', species: 'Fern', stage: 2, status: 'active', updated: now };
  const first = { key: 'quietStart', value: '1200', updated: now };
  const event = { id: randomUUID(), habitId: habit.id, day: '2026-09-01', result: 'did', reason: null, ts: now };
  await h.sync(request('POST', payload({ habits: [habit], settings: [first], checkins: [event] })));
  await h.sync(request('POST', payload({
    habits: [{ ...habit, anchor: 'Zebra', stage: 1 }],
    settings: [{ ...first, value: '1300' }],
    checkins: [{ ...event, result: 'notToday' }],
  })));
  let garden = (await h.sync(request('GET'))).jsonBody;
  assert.equal(garden.habits[0].anchor, 'Zebra');
  assert.equal(garden.habits[0].stage, 2);
  assert.equal(garden.settings[0].value, '1300');
  assert.equal(garden.checkins[0].result, 'did');
  await h.sync(request('POST', payload({ habits: [{ ...habit, anchor: 'Alpha', updated: '2026-09-01T12:00:00.000001Z', stage: 3 }] })));
  garden = (await h.sync(request('GET'))).jsonBody;
  assert.equal(garden.habits[0].anchor, 'Alpha');
  assert.equal(garden.habits[0].stage, 3);
  await assert.rejects(h.sync(request('POST', payload({ settings: [{ key: 'reminders', value: 'true', updated: now }] }))), error => error.status === 400);
});

test('account cap is protected by the gate ETag against a competing record creation', async () => {
  const record = voice();
  const h = harness({ roles: [], limits: { records: { ...previewLimits.records, voice: 1 } }, beforeBatch: (operations, partition, store) => {
    if (partition === userId && operations.some(op => op.resourceBody?.type === 'voice')) {
      const gate = store.read('account', userId);
      store.put({ ...gate, counts: { ...gate.counts, voice: 1 } });
    }
  } });
  await assert.rejects(h.sync(request('POST', payload({ voice: [record] }))), error => error.status === 409);
  assert.equal(h.read(`voice:${record.id}`, userId), undefined);
  await assert.rejects(h.sync(request('POST', payload({ voice: [record] }))), error => error.status === 429);
});

test('global record and account ceilings do not recycle after deletion', async () => {
  const h = harness({ roles: [], limits: { lifetimeRecords: 1 } });
  await h.sync(request('POST', payload()));
  await assert.rejects(h.sync(request('POST', payload({ voice: [voice()] }))), error => error.status === 429);
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  await h.deleteAccount(deletion);
  await assert.rejects(h.sync(request('POST', payload())), error => error.status === 410);
  const noAccounts = harness({ roles: [], limits: { accounts: 0 } });
  await assert.rejects(noAccounts.sync(request('POST', payload())), error => error.status === 429);
  assert.equal(noAccounts.read('account', userId), undefined);
});

test('legacy telemetry counts are bootstrapped within the cap before new records are allowed', async () => {
  const h = harness({ roles: [], limits: { records: { ...previewLimits.records, events: 1 } } });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  h.put({ id: 'events:legacy', userId, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now } });
  await assert.rejects(h.sync(request('POST', payload({ events: [{ id: randomUUID(), name: 'checkin', ts: now }] }))), error => error.status === 429);
});

test('expired event envelopes cannot refresh raw retention and raw TTL follows event time', async () => {
  const h = harness({ roles: [] });
  const event = { id: randomUUID(), name: 'checkin', ts: '2026-08-31T12:00:00Z' };
  await h.sync(request('POST', payload({ events: [event] })));
  assert.equal(h.read(`events:${event.id}`, userId).ttl, 34214400 - 86400);
  await assert.rejects(h.sync(request('POST', payload({ events: [{ ...event, id: randomUUID(), ts: '2025-01-01T00:00:00Z' }] }))), error => error.status === 400);
});

test('metrics filters account deletion that wins during the event scan', async () => {
  const h = harness({ beforeQuery: (spec, store) => {
    if (spec.query.includes('c.type = "events"')) store.put({ id: 'account', userId, type: 'account', deleted: true });
  } });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  // Forty-nine other users should not become a publishable cohort with the
  // just-deleted account's contribution.
  for (let index = 0; index < 49; index++) {
    const partition = index.toString(16).padStart(64, '0');
    h.put({ id: 'account', userId: partition, type: 'account', deleted: false });
    h.put({ id: `events:${index}`, userId: partition, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now } });
  }
  h.put({ id: 'events:deleted', userId, type: 'events', record: { id: randomUUID(), name: 'checkin', ts: now } });
  assert.equal((await h.metrics(request('GET', null, { days: '1' }))).jsonBody.daily[0].counts, null);
});

test('aggregate order never selects a different envelope for a duplicate account/client key', () => {
  const rows = Array.from({ length: 50 }, (_, index) => ({ userId: String(index), record: { id: randomUUID(), name: 'checkin', ts: now } }));
  const conflicting = { userId: rows[0].userId, record: { ...rows[0].record, name: 'signin_succeeded' } };
  assert.deepEqual(
    aggregateEvents([conflicting, ...rows], '2026-09-01', '2026-09-01'),
    aggregateEvents([...rows, conflicting], '2026-09-01', '2026-09-01'),
  );
});

test('all seven safe settings persist and cadence events aggregate without private data', async () => {
  const h = harness({ roles: [] });
  const settings = [
    { key: 'reducedMotion', value: 'true', updated: now },
    { key: 'fewerReminders', value: 'false', updated: now },
    ...['reminderMinute', 'quietStart', 'quietEnd'].map(key => ({ key, value: '1200', updated: now })),
    ...['weeklyLast', 'ratingPromptedAt'].map(key => ({ key, value: now, updated: now })),
  ];
  await h.sync(request('POST', payload({ settings })));
  assert.equal((await h.sync(request('GET'))).jsonBody.settings.length, 7);
  const rows = Array.from({ length: 50 }, (_, index) => ['weekly_reflection', 'rating_prompted'].map(name => ({
    userId: String(index), record: { id: randomUUID(), name, ts: now },
  }))).flat();
  const data = aggregateEvents(rows, '2026-09-01', '2026-09-01');
  assert.equal(data.daily[0].counts.weekly_reflection, 50);
  assert.equal(data.categories.reminderLearning.weeklyReflections, 50);
  assert.equal(data.categories.voiceRatings.ratingPrompts, 50);
  assert.equal(data.categories.voiceRatings.ratings, null);
});

test('textless rating survives private feedback sync without becoming telemetry', async () => {
  const h = harness({ roles: [] });
  const record = { ...voice(), kind: 'Rating', body: '', rating: 4 };
  const result = await h.sync(request('POST', payload({ voice: [record] })));
  assert.equal(result.jsonBody.voice[0].body, '');
  assert.equal(result.jsonBody.voice[0].rating, 4);
  assert.equal(result.jsonBody.voice[0].status, 'received');
  assert.equal([...h.documents.values()].some(row => row.type === 'events'), false);
});

test('dedicated aggregate role cannot access garden, feedback or admin metrics', async () => {
  const h = harness({ roles: ['Bloomstep.AggregateWriter'] });
  for (const handler of [h.sync, h.admin, h.metrics, h.deleteAccount]) {
    await assert.rejects(handler(request('GET')), error => error.status === 403);
  }
  assert.equal(h.documents.size, 0);
});
test('aggregate endpoint validates completed UTC-day backfills and stores bounded snapshots idempotently', async () => {
  const h = harness({ roles: ['Bloomstep.AggregateWriter'] });
  const body = { endDay: '2026-08-31', days: 2 };
  const first = await h.aggregates(request('POST', body));
  assert.equal(first.jsonBody.snapshots.length, 2);
  assert.equal(first.jsonBody.snapshots[1].day, '2026-08-31');
  await h.aggregates(request('POST', body));
  assert.equal([...h.documents.values()].filter(row => row.type === 'aggregate').length, 2);
  assert.equal(h.writes.filter(row => row.action === 'aggregates_write').length, 2);
  for (const invalid of [{ endDay: '2026-09-01' }, { days: 31 }, { days: 0 }, { userId }, { endDay: '2025-01-01' }]) {
    await assert.rejects(h.aggregates(request('POST', invalid)), error => error.status === 400);
  }
  await assert.rejects(harness({ roles: [] }).aggregates(request('POST', {})), error => error.status === 403);
  await assert.rejects(harness({ disabled: true }).aggregates(request('POST', {})), error => error.status === 503);
});
test('deletion invalidates persisted snapshots and worker writes race through generation ETag', async () => {
  const h = harness({ roles: [] });
  const worker = createHandlers({ container: () => h.store, authenticate: async () => ({ userId: teamId, roles: ['Bloomstep.AggregateWriter'] }), clock: () => new Date(now) });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  await worker.aggregates(request('POST', {}));
  assert.equal([...h.documents.values()].filter(row => row.type === 'aggregate').length, 1);
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  await h.deleteAccount(deletion);
  assert.equal([...h.documents.values()].filter(row => row.type === 'aggregate').length, 0);
});
test('snapshot writers fail closed if deletion changes generation after the scan begins', async () => {
  const h = harness({ roles: ['Bloomstep.AggregateWriter'], beforeQuery: (spec, store) => {
    if (spec.query.includes('c.type = "events"')) {
      const gate = store.read('generation', '__daily_aggregates');
      store.put({ ...gate, revision: 'deletion won' });
      store.put({ id: 'account', userId, type: 'account', deleted: true });
    }
  } });
  await assert.rejects(h.aggregates(request('POST', {})), error => error.status === 409);
  assert.equal([...h.documents.values()].some(row => row.type === 'aggregate'), false);
});
test('snapshot aggregate kill switch, audit failure and action budget deny before snapshots', async () => {
  for (const h of [
    harness({ roles: ['Bloomstep.AggregateWriter'], aggregatesDisabled: true }),
    harness({ roles: ['Bloomstep.AggregateWriter'], apiDisabled: true }),
  ]) {
    await assert.rejects(h.aggregates(request('POST', {})), error => error.status === 503);
    assert.equal(h.documents.size, 0);
  }
  const failed = harness({ roles: ['Bloomstep.AggregateWriter'], failAudit: true });
  await assert.rejects(failed.aggregates(request('POST', {})), /Audit storage failed/);
  assert.equal([...failed.documents.values()].some(row => row.type === 'aggregate'), false);
  const limited = harness({ roles: ['Bloomstep.AggregateWriter'], limits: { adminActions: { ...previewLimits.adminActions, aggregates_write: { daily: 1, lifetime: 1 } } } });
  await limited.aggregates(request('POST', {}));
  await assert.rejects(limited.aggregates(request('POST', {})), error => error.status === 429);
});
test('snapshot store strips account/event IDs and unchanged retries consume no extra snapshot records', async () => {
  const h = harness({ roles: ['Bloomstep.AggregateWriter'] });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  const clientId = randomUUID();
  h.put({ id: `events:${clientId}`, userId, type: 'events', record: { id: clientId, name: 'first_launch', ts: '2026-08-31T12:00:00Z' } });
  await h.aggregates(request('POST', {}));
  const first = h.read('budget', '__preview_budget').records;
  const retried = await h.aggregates(request('POST', {}));
  assert.equal(retried.jsonBody.snapshots[0].updated, false);
  // Each retry intentionally retains one read/write-attempt audit.
  assert.equal(h.read('budget', '__preview_budget').records, first + 1);
  const serialized = JSON.stringify([...h.documents.values()].filter(row => row.type === 'aggregate'));
  assert.equal(serialized.includes(clientId), false);
  assert.equal(serialized.includes(userId), false);
});
test('maximum 30-day backfill is bounded and prunes expired dates atomically', async () => {
  const h = harness({ roles: ['Bloomstep.AggregateWriter'] });
  h.put({ id: 'daily:2026-07-01', userId: '__daily_aggregates', type: 'aggregate', day: '2026-07-01', digest: 'old', record: {}, ttl: 2592000 });
  const result = await h.aggregates(request('POST', { days: 30 }));
  assert.equal(result.jsonBody.snapshots.length, 30);
  assert.equal([...h.documents.values()].filter(row => row.type === 'aggregate').length, 30);
  assert.equal(h.read('daily:2026-07-01', '__daily_aggregates'), undefined);
});
test('alternate authenticator is invoked only for the internal aggregate route', async () => {
  const h = harness();
  let alternateCalls = 0;
  const handlers = createHandlers({
    container: () => h.store,
    authenticate: async () => { throw new ServiceError(401, 'Customer issuer only.'); },
    authenticateAggregate: async () => { alternateCalls++; return { userId: teamId, roles: ['Bloomstep.AggregateWriter'] }; },
    clock: () => new Date(now),
  });
  for (const handler of [handlers.sync, handlers.admin, handlers.metrics, handlers.deleteAccount]) {
    await assert.rejects(handler(request('GET')), error => error.status === 401);
  }
  assert.equal(alternateCalls, 0);
  await handlers.aggregates(request('POST', {}));
  assert.equal(alternateCalls, 1);
});
