import { createHash, randomUUID } from 'node:crypto';
import { isAdmin, syncSchema, replySchema, newerRecipe, newerSetting } from './contracts.mjs';
import { aggregateEvents, previewLimits, feedbackQuerySchema, metricsQuerySchema, decodeCursor } from './engagement.mjs';
import { dashboardSummaries, addDays } from './dashboards.mjs';
import { aarrrSummary } from './aarrr.mjs';
import { goalMetrics } from './goals.mjs';
import { supportReceiptSchema, supportMetrics } from './support.mjs';
import { reminderPreferenceCohorts } from './reminder-cohorts.mjs';
import { registryVersion } from './event_registry.g.mjs';
import { dailySnapshotRecordSchema, snapshotMetadataSchema } from './snapshot-contracts.mjs';
import { createInvitations } from './invitations.mjs';
import { z } from 'zod';

export class ServiceError extends Error {
  /** @param {number} status @param {string} message */
  constructor(status, message) { super(message); this.status = status; }
}

/**
 * Dependency injection is for deterministic store tests; production always
 * supplies the real strict JWT verifier and provisioned Cosmos container.
 * @param {{
 * container: () => import('@azure/cosmos').Container,
 * authenticate: (request: import('@azure/functions').HttpRequest) => Promise<{userId: string, roles: unknown, scopes?: string[]}>,
 * authenticateAggregate?: (request: import('@azure/functions').HttpRequest) => Promise<{userId: string, roles: unknown}>,
 * authenticateSpend?: (request: import('@azure/functions').HttpRequest) => Promise<{userId: string, roles: unknown}>,
 * clock?: () => Date,
 * environment?: () => NodeJS.ProcessEnv,
 * limits?: typeof previewLimits
 * }} dependencies
 */
export function createHandlers({ container, authenticate, authenticateAggregate = authenticate,
  authenticateSpend = async () => { throw new ServiceError(503, 'Spend guard identity is not provisioned.'); },
  clock = () => new Date(), environment = () => process.env, limits = previewLimits }) {
  const budgetPartition = '__preview_budget';
  const rawTtl = 34214400;
  const auditTtl = 2592000;
  const aggregatePartition = '__daily_aggregates';
  const aggregateSchema = z.object({ endDay: z.iso.date().optional(), days: z.number().int().min(1).max(30).default(1) }).strict();
  const workerOnly = (/** @type {unknown} */ roles) => Array.isArray(roles) && roles.includes('Bloomstep.AggregateWriter') && !isAdmin(roles);
  /** @param {import('@azure/functions').HttpRequest} request */
  async function gardenActor(request) {
    const actor = await authenticate(request);
    if (workerOnly(actor.roles) || Array.isArray(actor.roles) && actor.roles.includes('Bloomstep.SpendGuard')) throw new ServiceError(403, 'Operational roles cannot access customer records.');
    return actor;
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function invitationActor(request) {
    const actor = await gardenActor(request);
    if (!actor.scopes?.includes('Garden.ReadWrite')) throw new ServiceError(403, 'Customer Garden.ReadWrite scope required.');
    apiEnabled();
    await operationalEnabled();
    engagementEnabled();
    if (['true', '1'].includes((environment().BLOOMSTEP_INVITATIONS_DISABLED ?? '').toLowerCase())) throw new ServiceError(503, 'Invitations are paused.');
    return actor;
  }
  const gateBody = (/** @type {any} */ gate) => ({ ...gate, revision: randomUUID() });
  /** @param {unknown} error */
  const conflict = error => typeof error === 'object' && error && 'code' in error && [409, 412, 424].includes(Number(error.code));
  function engagementEnabled() {
    if (['true', '1'].includes((environment().BLOOMSTEP_ENGAGEMENT_DISABLED ?? '').toLowerCase())) throw new ServiceError(503, 'Engagement is paused by the operator.');
  }
  function apiEnabled() {
    if (['true', '1'].includes((environment().BLOOMSTEP_API_DISABLED ?? '').toLowerCase())) throw new ServiceError(503, 'API is paused by the operator; account deletion remains available.');
  }
  async function operationalEnabled() {
    const gate = (await container().item('budget', budgetPartition).read()).resource;
    if (gate?.operationalPause?.paused === true) throw new ServiceError(503, 'Remote writes and team engagement are paused for spending review; export and deletion remain available.');
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function operationalPause(request) {
    const actor = await authenticateSpend(request);
    if (!Array.isArray(actor.roles) || !actor.roles.includes('Bloomstep.SpendGuard')) throw new ServiceError(403, 'Explicit SpendGuard role required.');
    const schema = z.strictObject({ requestId: z.uuid(), reason: z.enum(['paid_sku', 'spending_limit_off', 'positive_cost', 'configuration_unknown']) });
    const parsed = schema.safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Invalid operational pause request.');
    const item = container().item('budget', budgetPartition);
    const { resource } = await item.read();
    const previous = resource?.operationalPause;
    if (previous?.requestId === parsed.data.requestId && previous.reason !== parsed.data.reason) throw new ServiceError(409, 'Pause request ID reused with a different reason.');
    if (previous?.paused) return { jsonBody: previous };
    const pause = { paused: true, requestId: parsed.data.requestId, reason: parsed.data.reason, pausedAt: clock().toISOString() };
    const document = { ...(resource ?? { id: 'budget', userId: budgetPartition, type: 'budget', ttl: -1 }),
      operationalPause: pause, pauseActor: actor.userId, pauseOperations: Math.min(Number(resource?.pauseOperations ?? 0) + 1, 11) };
    try {
      if (resource) await item.replace(document, { accessCondition: { type: 'IfMatch', condition: resource._etag } });
      else await container().items.create(document);
    } catch (error) {
      if (conflict(error)) throw new ServiceError(409, 'Concurrent pause; retry same request.');
      throw error;
    }
    return { jsonBody: pause };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function operationalResume(request) {
    const actor = await gardenActor(request);
    if (!isAdmin(actor.roles) || !actor.scopes?.includes('Garden.ReadWrite')) throw new ServiceError(403, 'Selected customer Admin and Garden scope required.');
    const parsed = z.strictObject({ requestId: z.uuid(), reviewedPauseRequestId: z.uuid(),
      confirmation: z.literal('reviewed-free-tier-and-spending-limit') }).safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Explicit spending review confirmation required.');
    const item = container().item('budget', budgetPartition);
    const { resource } = await item.read();
    if (!resource?.operationalPause?.paused && resource?.pauseReview?.requestId === parsed.data.requestId &&
        resource.pauseReview.reviewedPauseRequestId === parsed.data.reviewedPauseRequestId) return { jsonBody: { paused: false } };
    if (!resource?.operationalPause?.paused || resource.operationalPause.requestId !== parsed.data.reviewedPauseRequestId) throw new ServiceError(409, 'Pause changed; review the current pause.');
    if (Number(resource.pauseResumes ?? 0) >= 10) throw new ServiceError(429, 'Manual resume lifetime cap reached.');
    const document = { ...resource, operationalPause: null, pauseResumes: Number(resource.pauseResumes ?? 0) + 1,
      pauseReview: { ...parsed.data, actor: actor.userId, reviewedAt: clock().toISOString() } };
    try { await item.replace(document, { accessCondition: { type: 'IfMatch', condition: resource._etag } }); }
    catch (error) { if (conflict(error)) throw new ServiceError(409, 'Pause changed during review.'); throw error; }
    return { jsonBody: { paused: false } };
  }
  /** @param {number} records @param {number} accounts @param {keyof typeof limits.adminActions | undefined} action */
  async function reserve(records = 0, accounts = 0, action = undefined) {
    const item = container().item('budget', budgetPartition);
    const { resource } = await item.read();
    const day = clock().toISOString().slice(0, 10);
    const daily = resource?.day === day ? Number(resource.daily) : 0;
    const actions = { ...resource?.actions };
    if (action) {
      const old = actions[action];
      const actionDaily = old?.day === day ? Number(old.daily) : 0;
      const lifetime = Number(old?.lifetime ?? 0);
      if (actionDaily + 1 > limits.adminActions[action].daily || lifetime + 1 > limits.adminActions[action].lifetime) throw new ServiceError(429, 'Admin read/write volume cap reached; operator review required.');
      actions[action] = { day, daily: actionDaily + 1, lifetime: lifetime + 1 };
    }
    if (Number(resource?.operations ?? 0) + 1 > limits.lifetimeOperations
        || daily + 1 > limits.operationsPerDay
        || Number(resource?.records ?? 0) + records > limits.lifetimeRecords
        || Number(resource?.accounts ?? 0) + accounts > limits.accounts) throw new ServiceError(429, 'Preview volume cap reached; operator review required.');
    const document = { ...resource, id: 'budget', userId: budgetPartition, type: 'budget', day,
      daily: daily + 1, operations: Number(resource?.operations ?? 0) + 1,
      records: Number(resource?.records ?? 0) + records, accounts: Number(resource?.accounts ?? 0) + accounts, actions, ttl: -1 };
    try {
      if (resource) await item.replace(document, { accessCondition: { type: 'IfMatch', condition: resource._etag } });
      else await container().items.create(document);
    } catch (error) {
      if (conflict(error)) throw new ServiceError(429, 'Concurrent budget reservation; retry later.');
      throw error;
    }
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function body(request) {
    const raw = await request.text();
    if (Buffer.byteLength(raw) > 512 * 1024) throw new ServiceError(413, 'Request is too large.');
    try { return JSON.parse(raw); } catch { throw new ServiceError(400, 'Invalid JSON.'); }
  }
  /** @param {string} userId @param {boolean} create */
  async function assertActive(userId, create = true) {
    const item = container().item('account', userId);
    let { resource } = await item.read();
    if (!resource && create) {
      await reserve(1, 1);
      try {
        resource = (await container().items.create({ id: 'account', userId, type: 'account', deleted: false, revision: randomUUID(), counts: {}, ttl: -1 })).resource;
      } catch (error) {
        if (!conflict(error)) throw error;
        resource = (await item.read()).resource;
      }
    }
    if (!resource || resource.deleted) throw new ServiceError(410, 'Account data is unavailable or deleted.');
    return resource;
  }
  /** @param {string} userId */
  async function rateLimit(userId) {
    const gate = await assertActive(userId);
    const minute = Math.floor(clock().getTime() / 60000);
    const count = gate.rateMinute === minute ? Number(gate.rateCount) : 0;
    if (count >= 30) throw new ServiceError(429, 'Please wait before trying again.');
    try {
      await container().item('account', userId).replace({ ...gateBody(gate), rateMinute: minute, rateCount: count + 1 },
        { accessCondition: { type: 'IfMatch', condition: gate._etag } });
    } catch (error) {
      if (conflict(error)) throw new ServiceError(429, 'Concurrent requests; retry later.');
      throw error;
    }
  }
  /** @param {import('@azure/cosmos').OperationInput[]} operations @param {string} userId */
  async function batch(operations, userId) {
    try {
      const result = await container().items.batch(operations, userId);
      if (result.code === undefined || result.code < 200 || result.code >= 300) throw new ServiceError(409, 'Concurrent update; retry safely.');
    } catch (error) {
      if (conflict(error)) throw new ServiceError(409, 'Concurrent update; retry safely.');
      throw error;
    }
  }
  /** @param {string} userId */
  async function readGarden(userId) {
    await assertActive(userId, false);
    const { resources } = await container().items.query({
      query: `SELECT TOP ${limits.gardenRecords + 1} c.type, c.record, c.support FROM c WHERE c.userId = @u AND c.type IN ("habits","checkins","reflections","voice","settings")`,
      parameters: [{ name: '@u', value: userId }],
    }, { partitionKey: userId }).fetchAll();
    const gate = await assertActive(userId, false);
    if (gate.pendingRecordCleanup?.length) throw new ServiceError(409, 'Record deletion cleanup is in progress; retry sync.');
    const deletions = Object.values(gate.deletedRecords ?? {});
    if (resources.length > limits.gardenRecords) throw new ServiceError(429, 'Legacy garden exceeds preview cap; operator review required.');
    /** @type {Record<string, any[]>} */
    const data = { habits: [], checkins: [], reflections: [], voice: [], settings: [], voiceReceipts: [] };
    for (const row of resources) {
      if (!recordDeleted(gate, row.type, row.record)) {
        data[row.type].push(row.record);
        if (row.type === 'voice') {
          const support = readSupport(row.support);
          const replies = support ? readReplies(row.record.replies) : null;
          if (support && support.firstRespondedAt !== null && !replies?.length) {
            throw new ServiceError(409, 'First response receipt has no stored reply.');
          }
          data.voiceReceipts.push(support ? { id: row.record.id, ...support }
            : { id: row.record.id, schemaVersion: 1, receivedAt: null, firstRespondedAt: null, reason: 'legacy_receipt_unavailable' });
          if (support && support.firstRespondedAt === null && replies?.length) {
            data.voiceReceipts[data.voiceReceipts.length - 1].reason = 'first_response_unavailable';
          }
        }
      }
    }
    data.deletions = deletions;
    return data;
  }
  /** @param {unknown} value */
  function readSupport(value) {
    if (value === undefined) return null;
    const parsed = supportReceiptSchema.safeParse(value);
    if (!parsed.success) throw new ServiceError(409, 'Server support receipt provenance is invalid.');
    return parsed.data;
  }
  /** @param {unknown} value */
  function readReplies(value) {
    let replies;
    try { replies = typeof value === 'string' ? JSON.parse(value) : null; }
    catch { throw new ServiceError(409, 'Feedback thread is invalid.'); }
    if (!Array.isArray(replies) || replies.some(reply => typeof reply !== 'string' || Array.from(reply).length > 2100)) throw new ServiceError(409, 'Feedback thread is invalid.');
    return replies;
  }
  /** @param {any} gate @param {string} type @param {any} record */
  function recordDeleted(gate, type, record) {
    const ledger = gate.deletedRecords ?? {};
    return !!ledger[`${type}:${record?.id}`] ||
      !!ledger[`habits:${record?.habitId ?? record?.properties?.habitId}`] ||
      type === 'audit' && !!ledger[`voice:${record?.targetId}`];
  }
  /** @param {string} userId @param {any} deletion */
  async function removeRecord(userId, deletion) {
    let gate = await assertActive(userId, false);
    const key = `${deletion.type}:${deletion.recordId}`;
    const ledger = gate.deletedRecords ?? {};
    const reused = Object.values(ledger).find((/** @type {any} */ row) => row.id === deletion.id);
    if (reused && (reused.type !== deletion.type || reused.recordId !== deletion.recordId || reused.ts !== deletion.ts)) {
      throw new ServiceError(409, 'Deletion request ID was already used for another record.');
    }
    if (ledger[key] && !(gate.pendingRecordCleanup ?? []).includes(key)) return;
    if (!ledger[key]) {
      if (Object.keys(ledger).length >= 1000) throw new ServiceError(429, 'Record deletion safety ledger is full; account export/deletion remains available.');
      await batch([{ operationType: 'Replace', id: 'account', ifMatch: gate._etag,
        resourceBody: { ...gateBody(gate), deletedRecords: { ...ledger, [key]: deletion },
          pendingRecordCleanup: [...(gate.pendingRecordCleanup ?? []), key] } }], userId);
    }
    await invalidateSnapshots();
    // Permanent minimal ID-only suppression is committed first. Every writer
    // also CASes this gate, so offline edits cannot race past a deletion.
    const finished = async () => {
      const current = await assertActive(userId, false);
      if (!(current.pendingRecordCleanup ?? []).includes(key)) return;
      await batch([{ operationType: 'Replace', id: 'account', ifMatch: current._etag,
        resourceBody: { ...gateBody(current), pendingRecordCleanup: current.pendingRecordCleanup.filter((/** @type {string} */ value) => value !== key) } }], userId);
    };
    for (let page = 0; page < 100; page++) {
      const { resources } = await container().items.query({
        query: 'SELECT TOP 100 * FROM c WHERE c.userId = @u AND c.type != "account" AND ((c.type = @targetType AND c.record.id = @target) OR (@targetType = "habits" AND (c.record.habitId = @target OR c.record.properties.habitId = @target)) OR (@targetType = "voice" AND c.type = "audit" AND c.targetId = @target))',
        parameters: [{ name: '@u', value: userId }, { name: '@target', value: deletion.recordId }, { name: '@targetType', value: deletion.type }],
      }, { partitionKey: userId }).fetchAll();
      if (!resources.length) { await finished(); return; }
      for (let start = 0; start < resources.length; start += 90) {
        gate = await assertActive(userId, false);
        const targets = resources.slice(start, start + 90).filter(row => recordDeleted(gate, row.type,
          row.type === 'audit' ? row : row.record));
        if (!targets.length) continue;
        await batch([
          { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: gateBody(gate) },
          ...targets.map(row => /** @type {import('@azure/cosmos').OperationInput} */ ({ operationType: 'Delete', id: row.id })),
        ], userId);
      }
      if (resources.length < 100) { await finished(); return; }
    }
    throw new ServiceError(429, 'Record cleanup scan cap reached; deletion remains suppressed. Retry cleanup.');
  }
  /** @param {string} userId @param {string} type @param {any} gate @param {Record<string, any[]>} existing */
  async function nextGate(userId, type, gate, existing) {
    const counts = { ...gate.counts };
    let observed = existing[type]?.length ?? 0;
    if (type === 'events' && !Object.hasOwn(counts, type)) {
      const { resources } = await container().items.query({
        query: `SELECT TOP ${limits.records.events + 1} c.id FROM c WHERE c.userId = @u AND c.type = "events"`,
        parameters: [{ name: '@u', value: userId }],
      }, { partitionKey: userId }).fetchAll();
      observed = resources.length;
    }
    const baseline = Math.max(Number(counts[type] ?? 0), observed);
    if (baseline + 1 > limits.records[/** @type {keyof typeof limits.records} */ (type)]) throw new ServiceError(429, 'Account record cap reached; export or contact the operator.');
    counts[type] = baseline + 1;
    const updated = { ...gateBody(gate), userId, counts };
    if (type === 'events') {
      const day = clock().toISOString().slice(0, 10);
      const daily = gate.eventDay === day ? Number(gate.eventCount) : 0;
      if (daily + 1 > limits.eventsPerDay) throw new ServiceError(429, 'Daily telemetry cap reached.');
      Object.assign(updated, { eventDay: day, eventCount: daily + 1 });
    }
    return updated;
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function sync(request) {
    const { userId } = await gardenActor(request);
    const parsed = request.method === 'GET' ? null : syncSchema.safeParse(await body(request));
    if (parsed && !parsed.success) throw new ServiceError(400, 'Sync payload failed validation.');
    const deletionOnly = parsed?.success && parsed.data.deletions.length > 0 &&
      !Object.entries(parsed.data).some(([key, rows]) => key !== 'deletions' && rows.length);
    if (!deletionOnly) apiEnabled();
    if (parsed?.success && parsed.data.deletions.length) {
      const actor = await gardenActor(request);
      if (!actor.scopes?.includes('Garden.ReadWrite')) throw new ServiceError(403, 'Customer Garden.ReadWrite scope required for record deletion.');
    }
    if (request.method !== 'GET' && !deletionOnly) await operationalEnabled();
    if (parsed?.success && (parsed.data.events.length || parsed.data.voice.length)) engagementEnabled();
    if (parsed?.success && parsed.data.events.some(event =>
      Date.parse(event.ts) + rawTtl * 1000 <= clock().getTime() || Date.parse(event.ts) > clock().getTime() + 300000)) throw new ServiceError(400, 'Telemetry timestamp is outside the retention window.');
    await reserve();
    await rateLimit(userId);
    const pendingGate = await assertActive(userId, false);
    for (const key of pendingGate.pendingRecordCleanup ?? []) {
      await removeRecord(userId, pendingGate.deletedRecords[key]);
    }
    if (request.method === 'GET') {
      const data = await readGarden(userId);
      await assertActive(userId, false);
      return { jsonBody: data };
    }
    if (!parsed?.success) throw new ServiceError(400, 'Sync payload failed validation.');
    const incoming = parsed.data;
    for (const deletion of incoming.deletions) await removeRecord(userId, deletion);
    const existing = await readGarden(userId);
    const deletedGate = await assertActive(userId, false);
    const owned = new Set([...incoming.habits.map(h => h.id), ...existing.habits.map(h => h.id)]);
    for (const row of [...incoming.checkins, ...incoming.reflections]) {
      if (!owned.has(row.habitId) && !recordDeleted(deletedGate, 'checkins', row)) throw new ServiceError(400, 'Unknown habit reference.');
    }
    for (const [type, records] of Object.entries(incoming)) {
      if (type === 'deletions') continue;
      for (const original of records) {
        /** @type {any} */
        let record = { ...original };
        const id = `${type}:${type === 'settings' ? record.key : record.id}`;
        const { resource } = await container().item(id, userId).read();
        if (!['habits', 'settings'].includes(type) && resource) continue;
        if (type === 'settings' && resource && !newerSetting(record, resource.record)) continue;
        if (type === 'habits' && resource) {
          const stage = Math.max(resource.record.stage, Number(record.stage));
          if (!newerRecipe(record, resource.record)) {
            if (stage === resource.record.stage) continue;
            record = { ...resource.record };
          }
          record.stage = stage;
        }
        if (type === 'voice') Object.assign(record, { status: 'received', replies: '[]' });
        if (type === 'reflections') record.items = JSON.stringify(record.items);
        const gate = await assertActive(userId, false);
        if (recordDeleted(gate, type, record)) continue;
        const updated = resource ? gateBody(gate) : await nextGate(userId, type, gate, existing);
        const ttl = type === 'events' ? Math.max(1, Math.ceil((Date.parse(record.ts) + rawTtl * 1000 - clock().getTime()) / 1000)) : -1;
        /** @type {Record<string, string | boolean>} */
        const practiceProof = type === 'checkins' ? {
          receivedAt: clock().toISOString(),
          referralEligible: ['did', 'didMore'].includes(record.result) &&
            record.day <= clock().toISOString().slice(0, 10) && Date.parse(record.ts) <= clock().getTime() + 300000,
        } : {};
        /** @type {Record<string, z.infer<typeof supportReceiptSchema>>} */
        const supportProof = type === 'voice'
          ? { support: { schemaVersion: 1, receivedAt: clock().toISOString(), firstRespondedAt: null } } : {};
        if (practiceProof.referralEligible) updated.gardenPositiveSeen = true;
        await reserve(resource ? 0 : 1);
        await operationalEnabled();
        await batch([
          { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: updated },
          resource
            ? { operationType: 'Replace', id, ifMatch: resource._etag, resourceBody: { id, userId, type, record, ttl } }
            : { operationType: 'Create', resourceBody: { id, userId, type, record, ...practiceProof, ...supportProof, ttl } },
        ], userId);
      }
    }
    const garden = await readGarden(userId);
    if (!deletionOnly) await invitations.observePractice(userId, garden.checkins);
    if (!deletionOnly &&
        !['true', '1'].includes((environment().BLOOMSTEP_ENGAGEMENT_DISABLED ?? '').toLowerCase()) &&
        !['true', '1'].includes((environment().BLOOMSTEP_INVITATIONS_DISABLED ?? '').toLowerCase())) {
      await invitations.resume(userId);
    }
    await assertActive(userId, false);
    return { jsonBody: { ...garden, acknowledgedEvents: incoming.events.map(event => event.id) } };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function deleteAccount(request) {
    const { userId } = await gardenActor(request);
    if (request.headers.get('x-confirm-delete') !== 'delete-my-garden') throw new ServiceError(400, 'Explicit deletion confirmation required.');
    const item = container().item('account', userId);
    let current = (await item.read()).resource;
    if (!current) current = await assertActive(userId);
    try {
      await item.replace({ id: 'account', userId, type: 'account', revision: randomUUID(), deleted: true, ttl: -1 },
        { accessCondition: { type: 'IfMatch', condition: current._etag } });
    } catch (error) {
      if (conflict(error)) throw new ServiceError(409, 'Concurrent update; retry deletion.');
      throw error;
    }
    await invalidateSnapshots();
    await invitations.deleteLinks(userId);
    // Repeated bounded drains make deletion retryable without a cross-partition scan.
    for (;;) {
      const { resources } = await container().items.query({
        query: 'SELECT TOP 100 c.id FROM c WHERE c.userId = @u AND c.type != "account"',
        parameters: [{ name: '@u', value: userId }],
      }, { partitionKey: userId }).fetchAll();
      if (!resources.length) break;
      for (const row of resources) {
        try { await container().item(row.id, userId).delete(); }
        catch (error) {
          if (typeof error !== 'object' || !error || !('code' in error) || Number(error.code) !== 404) throw error;
        }
      }
    }
    return { status: 204 };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function team(request) {
    const actor = await authenticate(request);
    if (!isAdmin(actor.roles) || Array.isArray(actor.roles) && actor.roles.includes('Bloomstep.SpendGuard')) throw new ServiceError(403, 'Product team role required.');
    apiEnabled();
    await operationalEnabled();
    engagementEnabled();
    return actor;
  }
  async function aggregateGate() {
    const item = container().item('generation', aggregatePartition);
    let { resource } = await item.read();
    if (!resource) {
      try {
        resource = (await container().items.create({ id: 'generation', userId: aggregatePartition, type: 'aggregate_generation', revision: randomUUID(), generation: randomUUID(), ttl: -1 })).resource;
      } catch (error) {
        if (!conflict(error)) throw error;
        resource = (await item.read()).resource;
      }
    }
    if (!resource) throw new ServiceError(503, 'Aggregate generation unavailable.');
    return resource;
  }
  async function snapshots() {
    const { resources } = await container().items.query({
      query: 'SELECT TOP 31 * FROM c WHERE c.type = "aggregate"',
    }, { partitionKey: aggregatePartition }).fetchAll();
    if (resources.length > 30) throw new ServiceError(429, 'Snapshot count exceeds bounded store.');
    return resources;
  }
  async function invalidateSnapshots() {
    const gate = await aggregateGate();
    const rows = await snapshots();
    await batch([
      { operationType: 'Replace', id: 'generation', ifMatch: gate._etag, resourceBody: { ...gateBody(gate), generation: randomUUID() } },
      ...rows.map(row => /** @type {import('@azure/cosmos').OperationInput} */ ({
        operationType: 'Delete', id: row.id,
      })),
    ], aggregatePartition);
  }
  async function metricAccounts() {
    const { resources: accounts } = await container().items.query({
      query: `SELECT TOP ${limits.accounts + 1} c.userId, c.deleted, c.deletedRecords FROM c WHERE c.type = "account"`,
    }).fetchAll();
    if (accounts.length > limits.accounts) throw new ServiceError(429, 'Legacy account volume exceeds metrics cap.');
    return new Map(accounts.filter(row => !row.deleted).map(row => [row.userId, row]));
  }
  /** @param {string} startDay @param {string} endExclusive @param {{remaining:number}} scan */
  async function rawEventRecords(startDay, endExclusive, scan = { remaining: limits.metricRecords }) {
    const { resources } = await container().items.query({
      query: `SELECT TOP ${scan.remaining + 1} c.userId, c.record FROM c WHERE c.type = "events" AND c.record.ts >= @start AND c.record.ts < @end`,
      parameters: [{ name: '@start', value: startDay }, { name: '@end', value: endExclusive }],
    }).fetchAll();
    if (resources.length > scan.remaining) throw new ServiceError(429, 'Metrics scan cap exceeded; no partial counts returned.');
    scan.remaining -= resources.length;
    return resources;
  }
  /** @param {string} startDay @param {string} endExclusive */
  async function rawEvents(startDay, endExclusive) {
    const resources = await rawEventRecords(startDay, endExclusive);
    const active = await metricAccounts();
    return resources.filter(row => active.has(row.userId) && !recordDeleted(active.get(row.userId), 'events', row.record));
  }
  /** @param {{remaining:number}} scan */
  async function rawSupport(scan) {
    const { resources } = await container().items.query({
      query: `SELECT TOP ${scan.remaining + 1} c.userId, c.id, c.support, c.record.kind AS kind, c.record.rating AS rating, IIF(IS_ARRAY(STRINGTOARRAY(c.record.replies)) AND NOT EXISTS(SELECT VALUE r FROM r IN STRINGTOARRAY(c.record.replies) WHERE NOT IS_STRING(r) OR LENGTH(r) > 2100), ARRAY_LENGTH(STRINGTOARRAY(c.record.replies)) > 0, null) AS hasResponses FROM c WHERE c.type = "voice"`,
    }).fetchAll();
    if (resources.length > scan.remaining) throw new ServiceError(429, 'Combined metrics scan cap exceeded; no partial counts returned.');
    scan.remaining -= resources.length;
    return resources;
  }
  /** @param {string} startDay @param {string} endDay */
  async function persistedSeries(startDay, endDay) {
    const item = container().item('generation', aggregatePartition);
    const before = (await item.read()).resource;
    const rows = await snapshots();
    const after = (await item.read()).resource;
    const changed = before?._etag !== after?._etag;
    const generation = after?.id === 'generation' && after?.type === 'aggregate_generation'
      ? after.generation ?? after.revision : undefined;
    const observedAt = clock().toISOString();
    const latestDueAt = `${observedAt.slice(0, 10)}T02:20:00.000Z`;
    const days = [];
    for (let day = startDay; day <= endDay; day = addDays(day, 1)) {
      const matches = rows.filter(row => row.day === day);
      const saved = matches[0];
      let reason = changed ? 'generation_changed' : !saved ? 'not_generated'
        : !generation || saved.generation !== generation ? 'stale_generation' : null;
      const metadata = saved && snapshotMetadataSchema.safeParse({
        day: saved.day, generatedAt: saved.generatedAt, registryVersion: saved.registryVersion,
        generation: saved.generation, digest: saved.digest,
      });
      const record = saved && dailySnapshotRecordSchema.safeParse(saved.record);
      if (!reason && (matches.length !== 1 || saved.id !== `daily:${day}` || !metadata?.success || !record?.success ||
          saved.generatedAt > observedAt || saved.generatedAt.slice(0, 10) <= day ||
          record.data.startDay !== day ||
          createHash('sha256').update(JSON.stringify(saved.record)).digest('hex') !== saved.digest)) reason = 'invalid_snapshot';
      const scheduledAt = `${addDays(day, 1)}T02:20:00.000Z`;
      days.push(reason ? { day, status: 'unavailable', reason, scheduledAt, generationOffsetSeconds: null,
        generatedAt: null, registryVersion: null, suppression: null, record: null }
        : { day, status: 'available', reason: null, scheduledAt,
          generationOffsetSeconds: (Date.parse(saved.generatedAt) - Date.parse(scheduledAt)) / 1000,
          generatedAt: saved.generatedAt, registryVersion: saved.registryVersion,
          suppression: { minimumCohort: 50, dailySuppressed: saved.record.daily[0].suppressed },
          record: record.data });
    }
    return {
      source: 'persisted_daily_worker', startDay, endDay, days,
      schedule: { cron: '20 2 * * *', latestDueAt,
        latestTickDue: observedAt >= latestDueAt,
        backfillMaxDays: 30,
        definition: 'Declared daily02:20 UTC cron, not a guaranteed firing SLA. Generation offset is relative to that due time, not proof of a scheduled invocation; manual/backfill can generate early or late. Missing/stale latest-day records need explicit bounded worker backfill, never substitution with older data.' },
      definition: 'Independent completed UTC-day worker snapshots, not a window rollup. Never sum daily unique users, retention cohorts or medians. Missing/invalidated days remain unavailable; late arrivals require worker backfill. Older records are not substituted for the latest completed day.',
    };
  }
  /** @param {string} actor @param {'feedback_read' | 'metrics_read'} action */
  async function auditRead(actor, action) {
    await reserve(1, 0, action);
    await container().items.create({ id: randomUUID(), userId: budgetPartition, type: 'audit', actor, action, ts: clock().toISOString(), ttl: auditTtl });
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function admin(request) {
    const actor = await team(request);
    if (request.method === 'GET') {
      const parsed = feedbackQuerySchema.safeParse(Object.fromEntries(request.query));
      if (!parsed.success) throw new ServiceError(400, 'Invalid feedback page query.');
      let after;
      try { after = decodeCursor(parsed.data.cursor); } catch { throw new ServiceError(400, 'Invalid feedback cursor.'); }
      const limit = parsed.data.limit ?? limits.feedbackPage;
      // A lexicographic keyset avoids unlimited continuation tokens and offsets.
      await auditRead(actor.userId, 'feedback_read');
      const { resources } = await container().items.query({
        query: `SELECT TOP ${limit + 1} c.id, c.userId, c.record FROM c WHERE c.type = "voice" AND CONCAT(c.userId, ":", c.id) > @after ORDER BY c.userId, c.id`,
        parameters: [{ name: '@after', value: after }],
      }).fetchAll();
      const page = resources.slice(0, limit);
      /** @type {any[]} */
      const feedback = [];
      for (const row of page) {
        try {
          const gate = await assertActive(row.userId, false);
          if (!recordDeleted(gate, 'voice', row.record)) feedback.push({ userId: row.userId, record: row.record });
        }
        catch (error) { if (!(error instanceof ServiceError) || error.status !== 410) throw error; }
      }
      const last = page.at(-1);
      return { jsonBody: { feedback, nextCursor: resources.length > limit && last ? Buffer.from(`${last.userId}:${last.id}`).toString('base64url') : null } };
    }
    const userId = request.params.userId;
    if (!/^[a-f0-9]{64}$/.test(userId)) throw new ServiceError(400, 'Invalid account identifier.');
    const parsed = replySchema.safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Invalid status or reply.');
    await reserve(0, 0, 'feedback_reply');
    const gate = await assertActive(userId, false);
    if (gate.deletedRecords?.[`voice:${parsed.data.id}`]) throw new ServiceError(410, 'Feedback was removed by its owner.');
    const id = `voice:${parsed.data.id}`;
    const { resource } = await container().item(id, userId).read();
    if (!resource) throw new ServiceError(404, 'Feedback not found.');
    const replies = readReplies(resource.record.replies);
    const support = readSupport(resource.support);
    if (support && support.firstRespondedAt !== null && !replies.length) throw new ServiceError(409, 'Server support response provenance is inconsistent.');
    /** @type {{id: string, digest: string}[]} */
    const replyRequests = resource.replyRequests ?? [];
    if (!Array.isArray(replyRequests) || replyRequests.length > limits.replies
      || replyRequests.some(entry => typeof entry?.id !== 'string' || typeof entry?.digest !== 'string')) throw new ServiceError(409, 'Feedback retry history is invalid.');
    const digest = createHash('sha256').update(JSON.stringify([parsed.data.status, parsed.data.reply])).digest('hex');
    const previous = parsed.data.requestId ? replyRequests.find(entry => entry.id === parsed.data.requestId) : null;
    if (previous && previous.digest !== digest) throw new ServiceError(409, 'Reply request ID was already used for another response.');
    const last = replies.at(-1);
    const legacyRetry = !parsed.data.requestId && resource.record.status === parsed.data.status
      && typeof last === 'string' && last.includes(': ') && last.slice(last.indexOf(': ') + 2) === parsed.data.reply;
    if (previous || legacyRetry) {
      await assertActive(userId, false);
      return { jsonBody: { updated: true } };
    }
    if (replies.length >= limits.replies) throw new ServiceError(429, 'Feedback reply cap reached.');
    const ts = clock().toISOString();
    if (support && ts < (support.firstRespondedAt ?? support.receivedAt)) throw new ServiceError(503, 'Server response clock predates support provenance; retry later.');
    await reserve(1);
    await batch([
      { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: gateBody(gate) },
      { operationType: 'Replace', id, ifMatch: resource._etag, resourceBody: { ...resource,
        ...(support ? { support: { ...support, firstRespondedAt: support.firstRespondedAt ?? (replies.length ? null : ts) } } : {}),
        replyRequests: parsed.data.requestId ? [...replyRequests, { id: parsed.data.requestId, digest }] : replyRequests,
        record: { ...resource.record, status: parsed.data.status, replies: JSON.stringify([...replies, `${ts}: ${parsed.data.reply}`]) } } },
      { operationType: 'Create', resourceBody: { id: randomUUID(), userId, type: 'audit', actor: actor.userId, action: 'feedback_reply', targetId: parsed.data.id, ts, ttl: auditTtl } },
    ], userId);
    return { jsonBody: { updated: true } };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function metrics(request) {
    const actor = await team(request);
    const parsed = metricsQuerySchema.safeParse(Object.fromEntries(request.query));
    if (!parsed.success) throw new ServiceError(400, 'Invalid metrics query.');
    await auditRead(actor.userId, 'metrics_read');
    const end = new Date(clock().toISOString().slice(0, 10) + 'T00:00:00Z');
    end.setUTCDate(end.getUTCDate() + 1);
    const start = new Date(end);
    start.setUTCDate(start.getUTCDate() - (parsed.data.days ?? 7));
    const startDay = start.toISOString().slice(0, 10);
    const scan = { remaining: limits.metricRecords };
    const eventRecords = await rawEventRecords(addDays(startDay, -91), end.toISOString().slice(0, 10), scan);
    const supportRecords = await rawSupport(scan);
    const active = await metricAccounts();
    const resources = eventRecords.filter(row => active.has(row.userId) && !recordDeleted(active.get(row.userId), 'events', row.record));
    const supportRows = supportRecords.filter(row => active.has(row.userId) && !recordDeleted(active.get(row.userId), 'voice',
      { id: typeof row.id === 'string' && row.id.startsWith('voice:') ? row.id.slice(6) : row.id }));
    const endDay = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);
    return { jsonBody: { ...aggregateEvents(resources, startDay, endDay),
      dashboards: { ...dashboardSummaries(resources, addDays(startDay, -1), addDays(endDay, -1), clock().toISOString().slice(0, 10)),
        aarrr: aarrrSummary(resources, addDays(startDay, -1), addDays(endDay, -1), clock().toISOString().slice(0, 10)) },
      goalMetrics: goalMetrics(resources, addDays(startDay, -1), addDays(endDay, -1), clock().toISOString().slice(0, 10)),
      supportMetrics: supportMetrics(supportRows, addDays(startDay, -1), addDays(endDay, -1), clock().toISOString()),
      reminderPreferenceCohorts: reminderPreferenceCohorts(resources.map(row => ({ userId: row.userId, record: row.record })), addDays(startDay, -1), addDays(endDay, -1), clock().toISOString()),
      dailySnapshots: await persistedSeries(addDays(startDay, -1), addDays(endDay, -1)) } };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function aggregates(request) {
    const actor = await authenticateAggregate(request);
    if (!isAdmin(actor.roles) && !(Array.isArray(actor.roles) && actor.roles.includes('Bloomstep.AggregateWriter'))) throw new ServiceError(403, 'Aggregate writer role required.');
    apiEnabled();
    engagementEnabled();
    if (['true','1'].includes((environment().BLOOMSTEP_AGGREGATES_DISABLED ?? '').toLowerCase())) throw new ServiceError(503, 'Aggregate worker is paused.');
    const parsed = aggregateSchema.safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Invalid aggregate backfill.');
    const today = clock().toISOString().slice(0, 10);
    const endDay = parsed.data.endDay ?? addDays(today, -1);
    const startDay = addDays(endDay, 1 - parsed.data.days);
    if (endDay >= today || startDay < addDays(today, -30)) throw new ServiceError(400, 'Backfill must use the previous 30 completed UTC days.');
    await reserve(1, 0, 'aggregates_write');
    await container().items.create({ id: randomUUID(), userId: budgetPartition, type: 'audit', actor: actor.userId, action: 'aggregates_write', ts: clock().toISOString(), ttl: auditTtl });
    const gate = await aggregateGate();
    const existing = await snapshots();
    const rows = await rawEvents(addDays(startDay, -30), addDays(endDay, 1));
    const generation = gate.generation ?? gate.revision;
    /** @type {import('@azure/cosmos').OperationInput[]} */
    const operations = [{ operationType: 'Replace', id: 'generation', ifMatch: gate._etag, resourceBody: { ...gateBody(gate), generation } }];
    const result = [];
    let creates = 0;
    for (const old of existing.filter(row => row.day < addDays(today, -30))) {
      operations.push({ operationType: 'Delete', id: old.id });
    }
    for (let day = startDay; day <= endDay; day = addDays(day, 1)) {
      const record = { ...aggregateEvents(rows, day, day),
        dashboards: dashboardSummaries(rows.filter(row => row.record.ts.slice(0, 10) <= day), day, day, addDays(day, 1)) };
      dailySnapshotRecordSchema.parse(record);
      const digest = createHash('sha256').update(JSON.stringify(record)).digest('hex');
      const id = `daily:${day}`;
      const old = existing.find(row => row.id === id);
      const oldMetadata = old && snapshotMetadataSchema.safeParse({
        day: old.day, generatedAt: old.generatedAt, registryVersion: old.registryVersion,
        generation: old.generation, digest: old.digest,
      });
      const updated = old?.digest !== digest || old?.generation !== generation || !oldMetadata?.success ||
        old.generatedAt > clock().toISOString() || old.generatedAt.slice(0, 10) <= day ||
        !dailySnapshotRecordSchema.safeParse(old.record).success ||
        createHash('sha256').update(JSON.stringify(old.record)).digest('hex') !== old.digest;
      if (updated) {
        const document = { id, userId: aggregatePartition, type: 'aggregate', day, generatedAt: clock().toISOString(), generation, registryVersion, digest, record, ttl: auditTtl };
        operations.push(old ? { operationType: 'Replace', id, ifMatch: old._etag, resourceBody: document } : { operationType: 'Create', resourceBody: document });
        if (!old) creates++;
      }
      result.push({ day, digest, updated });
    }
    await reserve(creates);
    await batch(operations, aggregatePartition);
    return { jsonBody: { registryVersion, snapshots: result, experimentEnabled: false } };
  }
  const invitations = createInvitations({
    container, clock, active: assertActive, batch, reserve, gateBody, ServiceError,
    actor: invitationActor, body, rateLimit, readGarden,
  });
  return { sync, deleteAccount, admin, metrics, aggregates, operationalPause, operationalResume,
    createInvitation: invitations.createInvitation, redeemInvitation: invitations.redeemInvitation,
    invitationStatus: invitations.invitationStatus };
}
