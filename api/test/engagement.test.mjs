import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createHash } from 'node:crypto';
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

function harness({ roles = ['Bloomstep.Admin'], scopes = ['Garden.ReadWrite'], actorUserId, disabled = false, apiDisabled = false, aggregatesDisabled = false, invitationsDisabled = false, limits = {}, beforeBatch, failAudit = false, beforeQuery } = {}) {
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
          else if (spec.query.includes('c.type = "invitation_receipt"')) rows = rows.filter(row => row.type === 'invitation_receipt');
          else if (spec.query.includes('c.type = "referral_reward"')) rows = rows.filter(row => row.type === 'referral_reward');
          else if (spec.query.includes('c.type = "invitation_secret"')) rows = rows.filter(row => row.type === 'invitation_secret');
          else if (spec.query.includes('c.type != "account"')) rows = rows.filter(row => row.type !== 'account');
          if (parameters['@target']) rows = rows.filter(row =>
            row.type === parameters['@targetType'] && row.record?.id === parameters['@target'] ||
            parameters['@targetType'] === 'habits' && (row.record?.habitId === parameters['@target'] || row.record?.properties?.habitId === parameters['@target']) ||
            parameters['@targetType'] === 'voice' && row.type === 'audit' && row.targetId === parameters['@target']);
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
    authenticate: async () => ({ userId: actorUserId ?? (roles.length ? teamId : userId), roles, scopes }),
    clock: () => new Date(now), environment: () => ({
      BLOOMSTEP_ENGAGEMENT_DISABLED: String(disabled), BLOOMSTEP_API_DISABLED: String(apiDisabled), BLOOMSTEP_AGGREGATES_DISABLED: String(aggregatesDisabled),
      BLOOMSTEP_INVITATIONS_DISABLED: String(invitationsDisabled),
    }),
    limits: { ...previewLimits, ...limits },
  });
  return { ...handlers, put, read, documents, writes, store };
}

const friendId = 'c'.repeat(64);
const friendHandlers = (h, id = friendId, roles = [], scopes = ['Garden.ReadWrite']) => createHandlers({
  container: () => h.store, authenticate: async () => ({ userId: id, roles, scopes }),
  clock: () => new Date(now),
});
const recipe = () => ({ id: randomUUID(), aspiration: 'Private aspiration', anchor: 'Private anchor',
  behavior: 'Private behavior', celebration: 'Private celebration', species: 'Fern', stage: 0, status: 'active', updated: now });
const practice = (habitId, result = 'did') => ({ id: randomUUID(), habitId, day: '2026-09-01', result, reason: null, ts: now });

test('garden read rechecks deletion ledger after rows are fetched', async () => {
  const habit = recipe();
  let armed = false;
  const deletion = { id: randomUUID(), type: 'habits', recordId: habit.id, ts: now };
  const h = harness({ roles: [], beforeQuery: async (spec, { put, read }) => {
    if (armed && spec.query.includes('c.type IN')) {
      armed = false;
      put({ ...read('account', userId), deletedRecords: { [`habits:${habit.id}`]: deletion } });
    }
  } });
  await h.sync(request('POST', payload({ habits: [habit] })));
  armed = true;
  const result = (await h.sync(request('GET'))).jsonBody;
  assert.deepEqual(result.habits, []);
  assert.deepEqual(result.deletions, [deletion]);
});

test('delete racing a recipe edit, child insert or admin reply rejects stale CAS and retries without resurrection', async () => {
  for (const type of ['habits', 'checkins', 'voice']) {
    const habit = recipe(), note = voice();
    let armed = false;
    const deletion = { id: randomUUID(), type: type === 'voice' ? 'voice' : 'habits',
      recordId: type === 'voice' ? note.id : habit.id, ts: now };
    const h = harness({ roles: [], beforeBatch: async (ops, partition, { put, read }) => {
      if (armed && partition === userId && ops.some(op => op.resourceBody?.type === type)) {
        armed = false;
        put({ ...read('account', userId), deletedRecords: { [`${deletion.type}:${deletion.recordId}`]: deletion },
          pendingRecordCleanup: [`${deletion.type}:${deletion.recordId}`] });
      }
    } });
    await h.sync(request('POST', payload({ habits: [habit], voice: [note] })));
    armed = true;
    const write = type === 'voice'
      ? () => friendHandlers(h, teamId, ['Bloomstep.Admin']).admin(request('POST', { id: note.id, status: 'received', reply: 'Synthetic reply' }, {}, { userId }))
      : () => h.sync(request('POST', payload(type === 'habits'
        ? { habits: [{ ...habit, anchor: 'Edited', updated: '2026-09-01T12:00:01.000Z' }] }
        : { checkins: [practice(habit.id)] })));
    await assert.rejects(write(), e => e.status === 409);
    await h.sync(request('GET'));
    assert.equal(h.read(`${deletion.type}:${deletion.recordId}`, userId), undefined);
    if (type === 'voice') await assert.rejects(write(), e => e.status === 410 || e.status === 404);
    else assert.deepEqual((await write()).jsonBody.habits, []);
  }
});

test('permanent ledger cap is explicit and retry IDs cannot change timestamp', async () => {
  const h = harness({ roles: [] });
  await h.sync(request('GET'));
  const deletions = Array.from({ length: 1000 }, () =>
    ({ id: randomUUID(), type: 'habits', recordId: randomUUID(), ts: now }));
  h.put({ ...h.read('account', userId),
    deletedRecords: Object.fromEntries(deletions.map(row => [`habits:${row.recordId}`, row])) });
  const next = { id: randomUUID(), type: 'habits', recordId: randomUUID(), ts: now };
  await assert.rejects(h.sync(request('POST', payload({ deletions: [next] }))), e => e.status === 429);
  assert.equal((await h.sync(request('GET'))).jsonBody.deletions.length, 1000);
  await assert.rejects(h.sync(request('POST', payload({ deletions: [{ ...deletions[0], ts: '2026-09-01T11:59:00.000Z' }] }))), e => e.status === 409);
});

test('cleanup at the exact 10000-row request cap resumes rather than acknowledging residual private content', async () => {
  const h = harness({ roles: [] });
  const habit = recipe();
  await h.sync(request('POST', payload({ habits: [habit] })));
  for (let index = 0; index < 10000; index++) {
    const row = practice(habit.id);
    h.put({ id: `checkins:${row.id}`, userId, type: 'checkins', record: row, ttl: -1 });
  }
  const deletion = { id: randomUUID(), type: 'habits', recordId: habit.id, ts: now };
  await assert.rejects(h.sync(request('POST', payload({ deletions: [deletion] }))), e => e.status === 429 && /cleanup scan cap/.test(e.message));
  assert.deepEqual(h.read('account', userId).pendingRecordCleanup, [`habits:${habit.id}`]);
  assert.equal([...h.documents.values()].filter(row => row.userId === userId && row.type === 'checkins').length, 0);
  const readback = (await h.sync(request('GET'))).jsonBody;
  assert.deepEqual(readback.habits, []);
  assert.deepEqual(readback.deletions, [deletion]);
  assert.equal(h.read(`habits:${habit.id}`, userId), undefined);
  assert.deepEqual(h.read('account', userId).pendingRecordCleanup, []);
});

test('owner record tombstones purge dependent content, survive stale devices and never touch foreign IDs', async () => {
  const h = harness({ roles: [] });
  const habit = recipe(), note = voice(), check = practice(habit.id);
  const reflection = { id: randomUUID(), habitId: habit.id, items: '[4,4,4,4]', score: 4, ts: now };
  const event = { id: randomUUID(), name: 'automaticity_score', ts: now,
    properties: { habitId: habit.id, score: 4, localDay: '2026-09-01', platform: 'windows' } };
  await h.sync(request('POST', payload({ habits: [habit], checkins: [check], reflections: [reflection], voice: [note], events: [event] })));
  await friendHandlers(h, teamId, ['Bloomstep.Admin']).admin(request('POST',
    { id: note.id, status: 'received', reply: 'Synthetic private reply' }, {}, { userId }));
  const deletion = { id: randomUUID(), type: 'habits', recordId: habit.id, ts: now };
  const removal = { id: randomUUID(), type: 'voice', recordId: note.id, ts: now };
  const result = (await h.sync(request('POST', payload({ deletions: [deletion, removal] })))).jsonBody;
  assert.deepEqual(result.habits, []);
  assert.deepEqual(result.checkins, []);
  assert.deepEqual(result.voice, []);
  assert.deepEqual(result.reflections, []);
  assert.equal(result.deletions.length, 2);
  assert.equal(h.read(`habits:${habit.id}`, userId), undefined);
  assert.equal(h.read(`checkins:${check.id}`, userId), undefined);
  assert.equal(h.read(`voice:${note.id}`, userId), undefined);
  assert.equal(h.read(`reflections:${reflection.id}`, userId), undefined);
  assert.equal(h.read(`events:${event.id}`, userId), undefined);
  assert.equal([...h.documents.values()].some(row => row.userId === userId && row.type === 'audit' && row.targetId === note.id), false);
  const stale = (await h.sync(request('POST', payload({ habits: [habit], checkins: [check], reflections: [reflection], voice: [note], events: [event] })))).jsonBody;
  assert.deepEqual(stale.habits, []);
  assert.deepEqual(stale.voice, []);
  await h.sync(request('POST', payload({ deletions: [deletion, removal] })));
  const friend = friendHandlers(h);
  await friend.sync(request('POST', payload({ habits: [habit] })));
  await h.sync(request('POST', payload({ deletions: [deletion] })));
  assert.equal(h.read(`habits:${habit.id}`, friendId).record.anchor, habit.anchor);
  await assert.rejects(h.sync(request('POST', payload({ deletions: [{ ...deletion, recordId: randomUUID() }] }))), e => e.status === 409);
  assert.ok(!JSON.stringify(h.read('account', userId).deletedRecords).includes('Private'));
});

test('deleted feedback is absent from team pagination and cannot receive a reply; explicit customer scope required', async () => {
  const h = harness({ roles: [] });
  const note = voice();
  await h.sync(request('POST', payload({ voice: [note] })));
  await h.sync(request('POST', payload({ deletions: [{ id: randomUUID(), type: 'voice', recordId: note.id, ts: now }] })));
  const admin = friendHandlers(h, teamId, ['Bloomstep.Admin']);
  assert.deepEqual((await admin.admin(request('GET', null))).jsonBody.feedback, []);
  await assert.rejects(admin.admin(request('POST', { id: note.id, status: 'received', reply: 'not retained' }, {}, { userId })), e => e.status === 404 || e.status === 410);
  const noScope = friendHandlers(h, userId, ['Bloomstep.Admin'], []);
  await assert.rejects(noScope.sync(request('POST', payload({ deletions: [{ id: randomUUID(), type: 'habits', recordId: randomUUID(), ts: now }] }))), e => e.status === 403);
});

test('partial cleanup stays hidden, retries drain multiple pages, and concurrent edits cannot cross deletion gate', async () => {
  let fail = true;
  const h = harness({ roles: [], beforeBatch: async (operations) => {
    if (fail && operations.some(op => op.operationType === 'Delete' && op.id.startsWith('checkins:'))) {
      fail = false;
      throw new Error('Synthetic cleanup interruption');
    }
  } });
  const habit = recipe();
  await h.sync(request('POST', payload({ habits: [habit] })));
  for (let index = 0; index < 205; index++) {
    const row = practice(habit.id);
    h.put({ id: `checkins:${row.id}`, userId, type: 'checkins', record: row, ttl: -1 });
  }
  const deletion = { id: randomUUID(), type: 'habits', recordId: habit.id, ts: now };
  await assert.rejects(h.sync(request('POST', payload({ deletions: [deletion] }))), /Synthetic cleanup interruption/);
  const hidden = (await h.sync(request('GET'))).jsonBody;
  assert.deepEqual(hidden.habits, []);
  assert.deepEqual(hidden.checkins, []);
  assert.equal(hidden.deletions.length, 1);
  await h.sync(request('POST', payload({ deletions: [deletion] })));
  assert.equal([...h.documents.values()].filter(row => row.userId === userId && row.type === 'checkins').length, 0);
  const stale = { ...habit, updated: '2026-09-01T12:01:00.000Z', anchor: 'later edit' };
  assert.deepEqual((await h.sync(request('POST', payload({ habits: [stale] })))).jsonBody.habits, []);
});

test('record deletion remains available under API/operational/engagement pause without accepting unrelated writes', async () => {
  const h = harness({ roles: [] });
  const note = voice();
  await h.sync(request('POST', payload({ voice: [note] })));
  const paused = createHandlers({ container: () => h.store, authenticate: async () => ({ userId, roles: [], scopes: ['Garden.ReadWrite'] }),
    environment: () => ({ BLOOMSTEP_API_DISABLED: 'true', BLOOMSTEP_ENGAGEMENT_DISABLED: 'true' }), clock: () => new Date(now) });
  const deletion = { id: randomUUID(), type: 'voice', recordId: note.id, ts: now };
  assert.deepEqual((await paused.sync(request('POST', payload({ deletions: [deletion] })))).jsonBody.voice, []);
  await assert.rejects(paused.sync(request('POST', payload({ deletions: [deletion], habits: [recipe()] }))), e => e.status === 503);
  await assert.rejects(h.sync(request('POST', payload({ deletions: [{ ...deletion, body: 'not retained' }] }))), e => e.status === 400);
});

test('native invitation channels qr/native preserve the canonical 32-byte opaque token contract', async () => {
  const h = harness();
  for (const channel of ['qr', 'native']) {
    const created = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel }))).jsonBody;
    assert.equal(created.channel, channel);
    assert.match(created.token, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(Buffer.from(created.token, 'base64url').length, 32);
    assert.equal(Buffer.from(created.token, 'base64url').toString('base64url'), created.token);
    const friend = friendHandlers(h, channel === 'qr' ? friendId : 'd'.repeat(64));
    const accepted = (await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token }))).jsonBody;
    assert.equal(accepted.channel, channel);
    assert.equal(accepted.recipeCard, null);
  }
});

test('spend pause is isolated, bounded, one-way and idempotent; garden/team pause but export/deletion/ops remain', async () => {
  const h = harness();
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  const guard = createHandlers({
    container: () => h.store, authenticate: async () => ({ userId, roles: [], scopes: ['Garden.ReadWrite'] }),
    authenticateSpend: async () => ({ userId: teamId, roles: ['Bloomstep.SpendGuard'] }), clock: () => new Date(now),
  });
  const data = { requestId: randomUUID(), reason: 'paid_sku' };
  const paused = (await guard.operationalPause(request('POST', data))).jsonBody;
  assert.equal(paused.paused, true);
  assert.deepEqual((await guard.operationalPause(request('POST', data))).jsonBody, paused);
  await assert.rejects(guard.operationalPause(request('POST', { ...data, reason: 'positive_cost' })), e => e.status === 409);
  await assert.rejects(guard.operationalPause(request('POST', { ...data, paused: false })), e => e.status === 400);
  await assert.rejects(guard.sync(request('POST', payload())), e => e.status === 503);
  await assert.rejects(h.metrics(request('GET')), e => e.status === 503);
  assert.deepEqual((await guard.sync(request('GET'))).jsonBody.habits, []);
  const worker = createHandlers({ container: () => h.store,
    authenticate: async () => ({ userId: teamId, roles: ['Bloomstep.AggregateWriter'] }), clock: () => new Date(now) });
  await worker.aggregates(request('POST', {}));
  await assert.rejects(worker.operationalPause(request('POST', data)), e => e.status === 503);
  const wrong = createHandlers({ container: () => h.store,
    authenticate: async () => ({ userId: teamId, roles: ['Bloomstep.Admin'] }),
    authenticateSpend: async () => ({ userId: teamId, roles: ['Bloomstep.AggregateWriter'] }), clock: () => new Date(now) });
  await assert.rejects(wrong.operationalPause(request('POST', data)), e => e.status === 403);
  const deletion = request('DELETE'); deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  assert.equal((await guard.deleteAccount(deletion)).status, 204);
  assert.equal((await guard.operationalPause(request('POST', { requestId: randomUUID(), reason: 'spending_limit_off' }))).jsonBody.paused, true);
  await assert.rejects(guard.operationalResume(request('POST', {})), e => e.status === 403);
  await assert.rejects(h.operationalResume(request('POST', { requestId: randomUUID(), reviewedPauseRequestId: data.requestId })), e => e.status === 400);
  const review = { requestId: randomUUID(), reviewedPauseRequestId: data.requestId, confirmation: 'reviewed-free-tier-and-spending-limit' };
  assert.equal((await h.operationalResume(request('POST', review))).jsonBody.paused, false);
  assert.equal((await h.operationalResume(request('POST', review))).jsonBody.paused, false);
  await h.metrics(request('GET'));
  const newPause = { requestId: randomUUID(), reason: 'positive_cost' };
  await guard.operationalPause(request('POST', newPause));
  await assert.rejects(h.operationalResume(request('POST', review)), e => e.status === 409);
  h.put({ ...h.read('budget', '__preview_budget'), operations: previewLimits.lifetimeOperations });
  assert.equal((await guard.operationalPause(request('POST', newPause))).jsonBody.paused, true);
  assert.equal(h.read('budget', '__preview_budget').pauseOperations, 2);
});

test('SpendGuard never obtains primary garden/team privileges even if a malformed primary actor includes it', async () => {
  const h = harness({ roles: ['Bloomstep.SpendGuard'] });
  await assert.rejects(h.sync(request('GET')), e => e.status === 403);
  await assert.rejects(h.metrics(request('GET')), e => e.status === 403);
  await assert.rejects(h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 403);
  await assert.rejects(h.aggregates(request('POST', {})), e => e.status === 403);
});

test('invitations require customer Garden scope, reject worker/admin-only and strict unknown/private defaults', async () => {
  const h = harness();
  for (const actor of [friendHandlers(h, friendId, ['Bloomstep.Admin'], []),
    friendHandlers(h, friendId, ['Bloomstep.AggregateWriter']), friendHandlers(h, friendId, [], [])]) {
    await assert.rejects(actor.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 403);
    await assert.rejects(actor.redeemInvitation(request('POST', { requestId: randomUUID(), token: 'ignored' })), e => e.status === 403);
    await assert.rejects(actor.invitationStatus(request('GET')), e => e.status === 403);
  }
  for (const data of [
    { requestId: randomUUID(), channel: 'link', inviter: teamId },
    { requestId: randomUUID(), channel: 'link', habitText: 'private' },
    { requestId: randomUUID(), channel: 'sms' },
    { requestId: randomUUID(), channel: 'link', recipeCard: { explicitChoice: false, behavior: 'private' } },
  ]) await assert.rejects(h.createInvitation(request('POST', data)), e => e.status === 400);
  await assert.rejects(h.invitationStatus(request('GET', null, { userId: friendId })), e => e.status === 400);
});

test('opaque invitation creation is immutable/idempotent, defaults no habit text and is finitely capped', async () => {
  const h = harness();
  const data = { requestId: randomUUID(), channel: 'link' };
  const first = (await h.createInvitation(request('POST', data))).jsonBody;
  assert.match(first.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(first.recipeCard, null);
  assert.equal(first.expiresAt, '2026-09-08T12:00:00.000Z');
  assert.equal(JSON.stringify(first).includes(teamId), false);
  assert.deepEqual((await h.createInvitation(request('POST', data))).jsonBody, first);
  await assert.rejects(h.createInvitation(request('POST', { ...data, channel: 'email' })), e => e.status === 409);
  for (let i = 1; i < 10; i++) {
    h.put({ ...h.read('account', teamId), invitationDaily: 0 });
    await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }));
  }
  await assert.rejects(h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 429);
  assert.equal(h.read('account', teamId).invitationCreated, 10);
});

test('recipe-card sharing is explicit and exact; no contacts or attributed identities in recipient response', async () => {
  const h = harness();
  const card = { explicitChoice: true, templateCategory: 'calm', aspiration: 'Calm', anchor: 'After tea',
    behavior: 'One breath', celebration: 'Smile', species: 'Fern' };
  const created = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'email', recipeCard: card }))).jsonBody;
  const friend = friendHandlers(h);
  const accepted = (await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token }))).jsonBody;
  assert.deepEqual(accepted.recipeCard, card);
  assert.equal(accepted.channel, 'email');
  assert.equal(JSON.stringify(accepted).includes(teamId), false);
  assert.equal(JSON.stringify(accepted).includes(friendId), false);
  assert.deepEqual((await h.invitationStatus(request('GET', null, { export: 'true' }))).jsonBody.sharedRecipes[0].recipeCard, card);
  assert.equal((await friend.invitationStatus(request('GET', null, { export: 'true' }))).jsonBody.sharedRecipes.length, 0);
  await assert.rejects(h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link', recipeCard: { ...card, email: 'private' } })), e => e.status === 400);
});

test('invitation daily/global budgets and kill switches are explicit; deletion remains possible', async () => {
  for (const options of [{ disabled: true }, { apiDisabled: true }, { invitationsDisabled: true }]) {
    const h = harness(options);
    await assert.rejects(h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 503);
    assert.equal(h.documents.size, 0);
  }
  const h = harness();
  for (let i = 0; i < 2; i++) await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }));
  await assert.rejects(h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 429);
  const limited = harness({ limits: { lifetimeRecords: 1 } });
  await assert.rejects(limited.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' })), e => e.status === 429);
  assert.equal([...limited.documents.values()].some(row => row.type === 'invitation_code'), false);
});

test('acceptance resumes after a partition interruption with the identical request and never doubles acceptance', async () => {
  let fail = true;
  const h = harness({ beforeBatch: (operations, partition) => {
    if (fail && partition === friendId && operations.some(op => op.resourceBody?.id === 'invitation:incoming')) {
      fail = false; throw Error('Offline interrupted acceptance');
    }
  } });
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  const data = { requestId: randomUUID(), token: invitation.token };
  await assert.rejects(friend.redeemInvitation(request('POST', data)), /Offline interrupted acceptance/);
  assert.equal(h.read('invitation:incoming', friendId), undefined);
  assert.equal((await friend.redeemInvitation(request('POST', data))).jsonBody.status, 'accepted');
  assert.equal((await friend.redeemInvitation(request('POST', data))).jsonBody.status, 'accepted');
  assert.equal([...h.documents.values()].filter(row => row.type === 'invitation_receipt').length, 2);
});

test('latest undo/rest and future-day checkins cannot establish an invited first practice', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  const positive = practice(habit.id);
  const undo = { ...practice(habit.id, null), ts: '2026-09-01T12:00:00.001Z' };
  const future = { ...practice(habit.id), day: '2026-09-02' };
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [positive, undo, future] })));
  assert.equal(h.read('account', friendId).firstPracticeAt, undefined);
  assert.equal((await friend.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  const later = createHandlers({ container: () => h.store, authenticate: async () => ({ userId: friendId, roles: [], scopes: ['Garden.ReadWrite'] }),
    clock: () => new Date('2026-09-02T12:00:00.000Z') });
  await later.sync(request('POST', payload()));
  assert.equal((await later.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  await assert.rejects(friend.sync(request('POST', payload({ checkins: [{ ...practice(habit.id), referralEligible: true }] }))), e => e.status === 400);
});

test('deletion winning a reward account gate cannot be rewarded and retries clean the partial grant', async () => {
  let deleting = false;
  const h = harness({ beforeBatch: (operations, partition, store) => {
    if (deleting && partition === teamId && operations.some(op => op.resourceBody?.type === 'referral_reward')) {
      deleting = false;
      store.put({ ...store.read('account', teamId), deleted: true });
    }
  } });
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  deleting = true;
  await assert.rejects(friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id)] }))), e => e.status === 409);
  assert.equal([...h.documents.values()].filter(row => row.type === 'referral_reward' && row.userId === teamId).length, 0);
  assert.equal((await friend.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  assert.equal([...h.documents.values()].some(row => row.type === 'invitation_code'), false);
});

test('redemption rejects self/malformed/expired, binds immutable retry and only one invited-account acceptance', async () => {
  const h = harness();
  const created = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await assert.rejects(h.redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token })), e => e.status === 400);
  await assert.rejects(friendHandlers(h).redeemInvitation(request('POST', { requestId: randomUUID(), token: 'bad' })), e => e.status === 400);
  const expired = createHandlers({ container: () => h.store, authenticate: async () => ({ userId: friendId, roles: [], scopes: ['Garden.ReadWrite'] }), clock: () => new Date('2026-09-09T12:00:00.000Z') });
  await assert.rejects(expired.redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token })), e => e.status === 410);
  const friend = friendHandlers(h);
  const data = { requestId: randomUUID(), token: created.token };
  const first = (await friend.redeemInvitation(request('POST', data))).jsonBody;
  assert.deepEqual((await friend.redeemInvitation(request('POST', data))).jsonBody, first);
  await assert.rejects(friend.redeemInvitation(request('POST', { ...data, requestId: randomUUID() })), e => e.status === 409);
  await assert.rejects(friendHandlers(h, 'd'.repeat(64)).redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token })), e => e.status === 409);
  const other = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await assert.rejects(friend.redeemInvitation(request('POST', { ...data, token: other.token })), e => e.status === 409);
});

test('mutual rare flower is granted only from first stored positive garden checkin, never telemetry/settings/rest/undo', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const created = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: created.token }));
  assert.equal((await friend.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  const habit = recipe();
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id, 'notToday'), practice(habit.id, null)],
    events: [{ id: randomUUID(), name: 'first_checkin', ts: now }] })));
  assert.equal((await friend.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  await assert.rejects(friend.sync(request('POST', payload({ settings: [{ key: 'rareFlower', value: 'true', updated: now }] }))), e => e.status === 400);
  const checkin = practice(habit.id, 'didMore');
  checkin.ts = '2026-09-01T12:00:00.001Z';
  const synced = await friend.sync(request('POST', payload({ checkins: [checkin] })));
  assert.equal(Object.hasOwn(synced.jsonBody, 'rewards'), false);
  const first = (await friend.invitationStatus(request('GET'))).jsonBody;
  const inviter = (await h.invitationStatus(request('GET'))).jsonBody;
  assert.equal(first.rewards.length, 1);
  assert.equal(inviter.rewards.length, 1);
  const granted = [...h.documents.values()].filter(row => row.type === 'referral_reward');
  assert.notEqual(granted[0].id, granted[1].id);
  assert.equal(granted.every(row => !Object.hasOwn(row, 'peer') && !Object.hasOwn(row, 'invitationId') && !Object.hasOwn(row, 'hash')), true);
  assert.equal(first.rewards[0].cosmetic, 'rare_flower');
  await friend.sync(request('POST', payload({ checkins: [checkin] })));
  assert.deepEqual((await friend.invitationStatus(request('GET'))).jsonBody.rewards, first.rewards);
  assert.equal(JSON.stringify(first).includes(teamId), false);
  assert.equal(JSON.stringify(inviter).includes(friendId), false);
});

test('practice before acceptance cannot be retroactively attributed or rewarded', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const habit = recipe();
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id)] })));
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await assert.rejects(friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token })), e => e.status === 409);
});

test('partial mutual grant is a durable retryable saga, not claimed cross-partition atomicity', async () => {
  let fail = false;
  const h = harness({ beforeBatch: (operations, partition) => {
    if (fail && partition === teamId && operations.some(op => op.resourceBody?.type === 'referral_reward')) {
      fail = false;
      throw Error('Offline interruption');
    }
  } });
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  fail = true;
  await assert.rejects(friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id)] }))), /Offline interruption/);
  assert.equal([...h.documents.values()].filter(row => row.type === 'referral_reward').length, 1);
  await friend.invitationStatus(request('GET'));
  assert.equal([...h.documents.values()].filter(row => row.type === 'referral_reward').length, 2);
  await friend.invitationStatus(request('GET'));
  assert.equal([...h.documents.values()].filter(row => row.type === 'referral_reward').length, 2);
});

test('deletion cleans codes, reciprocal attribution/rewards, denies retries and exports only owner data', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id)] })));
  const exported = (await friend.invitationStatus(request('GET', null, { export: 'true' }))).jsonBody;
  assert.equal(exported.rewards.length, 1);
  assert.equal(JSON.stringify(exported).includes(teamId), false);
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  await friend.deleteAccount(deletion);
  assert.equal((await h.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
  assert.equal([...h.documents.values()].some(row => row.type === 'invitation_code'), false);
  assert.equal([...h.documents.values()].some(row => row.type === 'invitation_receipt'), false);
  await assert.rejects(friend.invitationStatus(request('GET')), e => e.status === 410);
});

test('expired invitation IDs cannot allocate replacement codes after TTL removes receipts/secrets', async () => {
  const h = harness();
  const data = { requestId: randomUUID(), channel: 'link' };
  await h.createInvitation(request('POST', data));
  h.documents.delete(`${teamId}/invitation:secret:${data.requestId}`);
  h.documents.delete(`${teamId}/invitation:receipt:${data.requestId}`);
  await assert.rejects(h.createInvitation(request('POST', data)), e => e.status === 410);
  await assert.rejects(h.createInvitation(request('POST', { ...data, channel: 'email' })), e => e.status === 409);
  assert.equal(h.read('account', teamId).invitationCreated, 1);
});

test('referral deletion is not blocked by an exhausted preview ledger and leaves a minimal non-linking tombstone', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [practice(habit.id)] })));
  h.put({ ...h.read('budget', '__preview_budget'), operations: previewLimits.lifetimeOperations });
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  assert.equal((await friend.deleteAccount(deletion)).status, 204);
  assert.equal([...h.documents.values()].some(row => ['invitation_code', 'invitation_receipt', 'referral_reward'].includes(row.type)), false);
  const tombstone = h.read('account', friendId);
  assert.equal(tombstone.deleted, true);
  assert.equal(Object.hasOwn(tombstone, 'firstPracticeCheckin'), false);
  assert.equal(Object.hasOwn(tombstone, 'invitationRequests'), false);
});

test('deleting one referral never removes an unrelated outgoing code with a colliding client request UUID', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const id = randomUUID();
  const invite = (await h.createInvitation(request('POST', { requestId: id, channel: 'link' }))).jsonBody;
  const unrelated = (await friend.createInvitation(request('POST', { requestId: id, channel: 'email' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invite.token }));
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  await h.deleteAccount(deletion);
  assert.equal(h.read(`invitation:secret:${id}`, friendId).token, unrelated.token);
  assert.equal(h.read(`invitation:receipt:${id}`, friendId).direction, 'outgoing');
  assert.equal(h.read('invitation:incoming', friendId), undefined);
});

test('an immutable rest checkin cannot be retried as a positive to forge a cosmetic reward', async () => {
  const h = harness();
  const friend = friendHandlers(h);
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  await friend.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const habit = recipe();
  const rest = practice(habit.id, 'notToday');
  await friend.sync(request('POST', payload({ habits: [habit], checkins: [rest] })));
  await friend.sync(request('POST', payload({ checkins: [{ ...rest, result: 'did' }] })));
  assert.equal(h.read(`checkins:${rest.id}`, friendId).record.result, 'notToday');
  assert.equal(h.read(`checkins:${rest.id}`, friendId).referralEligible, false);
  assert.equal((await friend.invitationStatus(request('GET'))).jsonBody.rewards.length, 0);
});

test('a missing lookup after interrupted creation repairs the same opaque code without reallocating records', async () => {
  const h = harness();
  const create = h.store.items.create;
  let interrupted = false;
  h.store.items.create = async document => {
    if (document.type === 'invitation_code' && !interrupted) {
      interrupted = true; throw Error('Offline lookup interruption');
    }
    return create(document);
  };
  const data = { requestId: randomUUID(), channel: 'link' };
  await assert.rejects(h.createInvitation(request('POST', data)), /Offline lookup interruption/);
  const secret = h.read(`invitation:secret:${data.requestId}`, teamId);
  const allocated = h.read('budget', '__preview_budget').records;
  const repaired = (await h.createInvitation(request('POST', data))).jsonBody;
  assert.equal(repaired.token, secret.token);
  assert.equal(h.read('account', teamId).invitationCreated, 1);
  assert.equal(h.read('budget', '__preview_budget').records, allocated);
});

test('acceptance qualification closes at its deadline and an original code/card retains absolute seven-day TTL', async () => {
  const h = harness();
  const invitation = (await h.createInvitation(request('POST', { requestId: randomUUID(), channel: 'link' }))).jsonBody;
  const later = createHandlers({ container: () => h.store, authenticate: async () => ({ userId: friendId, roles: [], scopes: ['Garden.ReadWrite'] }),
    clock: () => new Date('2026-09-03T12:00:00.000Z') });
  await later.redeemInvitation(request('POST', { requestId: randomUUID(), token: invitation.token }));
  const index = [...h.documents.values()].find(row => row.type === 'invitation_code');
  assert.equal(index.ttl, 5 * 86400);
  const expired = createHandlers({ container: () => h.store, authenticate: async () => ({ userId: friendId, roles: [], scopes: ['Garden.ReadWrite'] }),
    clock: () => new Date('2026-10-04T12:00:00.000Z') });
  const habit = { ...recipe(), updated: '2026-10-04T12:00:00.000Z' };
  const late = { ...practice(habit.id), day: '2026-10-04', ts: '2026-10-04T12:00:00.000Z' };
  await expired.sync(request('POST', payload({ habits: [habit], checkins: [late] })));
  const state = (await expired.invitationStatus(request('GET'))).jsonBody;
  assert.equal(state.invitations[0].status, 'expired');
  assert.equal(state.rewards.length, 0);
});

test('metrics consumes persisted daily records distinctly from on-demand values and missing days', async () => {
  const h = harness();
  await h.aggregates(request('POST', {}));
  const saved = h.read('daily:2026-08-31', '__daily_aggregates');
  saved.record.categories.activationRetention.checkins = 123;
  saved.record.dashboards.reminderHealth.sentUsers = 77;
  saved.digest = createHash('sha256').update(JSON.stringify(saved.record)).digest('hex');
  h.put(saved);
  const result = (await h.metrics(request('GET', null, { days: '2' }))).jsonBody;
  assert.equal(result.categories.activationRetention.checkins, null);
  assert.equal(result.dailySnapshots.source, 'persisted_daily_worker');
  assert.deepEqual(result.dailySnapshots.days.map(row => [row.day, row.status]), [
    ['2026-08-30', 'unavailable'], ['2026-08-31', 'available'],
  ]);
  const day = result.dailySnapshots.days[1];
  assert.equal(day.generatedAt, now);
  assert.equal(day.registryVersion, 1);
  assert.equal(day.record.categories.activationRetention.checkins, 123);
  assert.equal(day.record.dashboards.reminderHealth.sentUsers, 77);
  assert.equal(day.record.dashboards.outcomes.daily[0].medianAutomaticity, null);
  assert.equal(day.suppression.minimumCohort, 50);
  assert.equal(result.dailySnapshots.days[0].record, null);
  assert.equal(h.writes.filter(row => row.action === 'metrics_read').length, 1);
});

test('persisted series is unavailable without scheduling, for stale generations or malformed records', async () => {
  const h = harness();
  const absent = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  assert.equal(absent.days[0].reason, 'not_generated');
  assert.equal(h.read('generation', '__daily_aggregates'), undefined);
  await h.aggregates(request('POST', {}));
  const saved = h.read('daily:2026-08-31', '__daily_aggregates');
  for (const patch of [
    { generation: 'obsolete' }, { registryVersion: 999 },
    { generatedAt: '2026-09-02T00:00:00.000Z' },
    { generatedAt: '2026-08-31T12:00:00.000Z' },
    { record: { ...saved.record, dashboards: { ...saved.record.dashboards, accountId: userId } } },
    { record: { ...saved.record, startDay: '2026-08-30' } },
    { record: { ...saved.record, privateText: 'must never escape' } },
    { digest: 'invalid' },
  ]) {
    h.put({ ...saved, ...patch });
    const row = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots.days[0];
    assert.equal(row.status, 'unavailable');
    assert.equal(row.record, null);
    assert.equal(JSON.stringify(row).includes('must never escape'), false);
  }
});

test('sparse stored snapshots stay deterministically null and fail closed if their generation gate is absent', async () => {
  const h = harness();
  await h.aggregates(request('POST', {}));
  const first = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  const second = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  assert.deepEqual(first, second);
  assert.equal(first.days[0].status, 'available');
  assert.equal(first.days[0].suppression.dailySuppressed, true);
  assert.equal(first.days[0].record.daily[0].counts, null);
  assert.equal(first.days[0].record.daily[0].users, null);
  assert.equal(first.days[0].record.dashboards.funnel.sameDayActivation.rate, null);
  assert.equal(JSON.stringify(first).includes(userId), false);
  h.documents.delete('__daily_aggregates/generation');
  const unavailable = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots.days[0];
  assert.equal(unavailable.reason, 'stale_generation');
  assert.equal(unavailable.record, null);
});

test('actual account deletion during snapshot read invalidates the whole persisted series', async () => {
  let deleting = false;
  let customer;
  const h = harness({ beforeQuery: async spec => {
    if (deleting && spec.query.includes('c.type = "aggregate"')) {
      deleting = false;
      const deletion = request('DELETE');
      deletion.headers.set('x-confirm-delete', 'delete-my-garden');
      await customer.deleteAccount(deletion);
    }
  } });
  customer = createHandlers({ container: () => h.store, authenticate: async () => ({ userId, roles: [] }), clock: () => new Date(now) });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  await h.aggregates(request('POST', { days: 2 }));
  deleting = true;
  const series = (await h.metrics(request('GET', null, { days: '2' }))).jsonBody.dailySnapshots;
  assert.equal(h.read('account', userId).deleted, true);
  assert.equal(series.days.every(row => row.record === null && row.reason === 'generation_changed'), true);
});

test('daily series range is completed UTC days and earlier snapshots survive later worker runs', async () => {
  const h = harness();
  await h.aggregates(request('POST', { endDay: '2026-08-30' }));
  await h.aggregates(request('POST', {}));
  const result = (await h.metrics(request('GET', null, { days: '2' }))).jsonBody.dailySnapshots;
  assert.equal(result.startDay, '2026-08-30');
  assert.equal(result.endDay, '2026-08-31');
  assert.deepEqual(result.days.map(row => row.status), ['available', 'available']);
  const one = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  assert.equal(one.days.length, 1);
  assert.equal(one.days[0].day, '2026-08-31');
});

test('worker freshness exposes declared UTC due time and generation delay without inferring a scheduled invocation', async () => {
  const h = harness();
  let series = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  assert.equal(series.schedule.cron, '20 2 * * *');
  assert.equal(series.schedule.latestDueAt, '2026-09-01T02:20:00.000Z');
  assert.equal(series.schedule.latestTickDue, true);
  assert.equal(series.days[0].generationOffsetSeconds, null);
  await h.aggregates(request('POST', {}));
  series = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots;
  assert.equal(series.days[0].scheduledAt, '2026-09-01T02:20:00.000Z');
  assert.equal(series.days[0].generationOffsetSeconds, 34800);
  assert.match(series.schedule.definition, /not.*scheduled.*invocation/i);
  assert.equal(series.schedule.backfillMaxDays, 30);
});

test('explicit worker rerun repairs invalid legacy/private records instead of treating their digest as a valid retry', async () => {
  const h = harness();
  await h.aggregates(request('POST', {}));
  const saved = h.read('daily:2026-08-31', '__daily_aggregates');
  h.put({ ...saved, record: { ...saved.record, privateText: 'never publish' } });
  const repaired = await h.aggregates(request('POST', {}));
  assert.equal(repaired.jsonBody.snapshots[0].updated, true);
  assert.equal((await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots.days[0].status, 'available');
  assert.equal(h.read(saved.id, saved.userId).record.privateText, undefined);
});

test('metrics generation race and account deletion cannot disclose a previous persisted record', async () => {
  let race = false;
  const h = harness({ beforeQuery: (spec, store) => {
    if (race && spec.query.includes('c.type = "aggregate"')) {
      const gate = store.read('generation', '__daily_aggregates');
      store.put({ ...gate, generation: 'deleted', revision: 'deleted' });
    }
  } });
  await h.aggregates(request('POST', {}));
  race = true;
  const rows = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots.days;
  assert.equal(rows[0].reason, 'generation_changed');
  assert.equal(rows[0].record, null);
  const customer = createHandlers({ container: () => h.store, authenticate: async () => ({ userId, roles: [] }), clock: () => new Date(now) });
  h.put({ id: 'account', userId, type: 'account', deleted: false });
  const deletion = request('DELETE');
  deletion.headers.set('x-confirm-delete', 'delete-my-garden');
  race = false;
  await customer.deleteAccount(deletion);
  assert.equal((await h.metrics(request('GET', null, { days: '1' }))).jsonBody.dailySnapshots.days[0].record, null);
});

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
  assert.deepEqual(Object.keys(garden), ['habits', 'checkins', 'reflections', 'voice', 'settings', 'deletions']);
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

test('target metrics fetch90-day cohort history under the existing scan cap and exclude deleted accounts', async () => {
  const h = harness();
  const habitId = randomUUID();
  for (let index = 0; index < 50; index++) {
    const partition = index.toString(16).padStart(64, '0');
    h.put({ id: 'account', userId: partition, type: 'account', deleted: false });
    for (const [name, day, extra] of [
      ['first_checkin', '2026-06-02', { result: 'did' }],
      ['habit_graduated', '2026-07-01', {}],
    ]) {
      const id = randomUUID();
      h.put({ id: `events:${id}`, userId: partition, type: 'events',
        record: { id, name, ts: `${day}T12:00:00Z`, properties: { habitId, localDay: day, ...extra } } });
    }
  }
  let data = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody;
  const graduation = () => data.goalMetrics.goals.find(row => row.id === 'graduated_d90');
  assert.equal(graduation().value, 1);
  assert.equal(data.goalMetrics.startDay, '2026-08-31');
  h.put({ id: 'account', userId: '0'.repeat(64), type: 'account', deleted: true });
  data = (await h.metrics(request('GET', null, { days: '1' }))).jsonBody;
  assert.equal(graduation().value, null);
  const capped = harness({ limits: { metricRecords: 1 } });
  for (const row of h.documents.values()) if (row.type !== 'audit') capped.put(row);
  await assert.rejects(capped.metrics(request('GET', null, { days: '1' })), error => error.status === 429);
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
