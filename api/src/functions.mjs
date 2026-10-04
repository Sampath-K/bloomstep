import { app } from '@azure/functions';
import { CosmosClient } from '@azure/cosmos';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { randomUUID } from 'node:crypto';
import { accountKey, isAdmin, syncSchema, replySchema } from './contracts.mjs';

const issuer = process.env.OIDC_ISSUER;
const audience = process.env.OIDC_API_AUDIENCE;
const jwks = process.env.OIDC_JWKS_URI;
const cosmosConnection = process.env.COSMOS_CONNECTION_STRING;
// Missing environment never produces a permissive or mock endpoint.
const configuredContainer = cosmosConnection ? new CosmosClient(cosmosConnection).database('bloomstep').container('data') : null;
function container() {
  if (!configuredContainer) throw new ServiceError(503, 'Database is not provisioned.');
  return configuredContainer;
}
const keys = jwks?.startsWith('https://') ? createRemoteJWKSet(new URL(jwks)) : null;

/** @param {import('@azure/functions').HttpRequest} request */
async function authenticate(request) {
  if (!issuer || !audience || !keys || !configuredContainer) throw new ServiceError(503, 'Service is not provisioned.');
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) throw new ServiceError(401, 'Sign in required.');
  try {
    const { payload } = await jwtVerify(authorization.slice(7), keys, { issuer, audience, algorithms: ['RS256'], requiredClaims: ['sub', 'iss', 'exp', 'iat'] });
    if (!payload.sub || !payload.iss) throw new Error('Missing subject');
    const scopes = typeof payload.scp === 'string' ? payload.scp.split(' ') : [];
    if (!scopes.includes('Garden.ReadWrite') && !isAdmin(payload.roles)) throw new ServiceError(403, 'Required API scope is missing.');
    return { userId: accountKey(payload.iss, payload.sub), roles: payload.roles };
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    throw new ServiceError(401, 'Identity token could not be validated.');
  }
}

class ServiceError extends Error {
  /** @param {number} status @param {string} message */
  constructor(status, message) { super(message); this.status = status; }
}

/** @param {import('@azure/functions').HttpRequest} request */
async function body(request) {
  const raw = await request.text();
  if (Buffer.byteLength(raw) > 512 * 1024) throw new ServiceError(413, 'Request is too large.');
  try { return JSON.parse(raw); } catch { throw new ServiceError(400, 'Invalid JSON.'); }
}

/** @param {string} userId */
async function assertActive(userId) {
  const item = container().item('account', userId);
  let { resource } = await item.read();
  if (!resource) {
    try {
      const created = await container().items.create({ id: 'account', userId, type: 'account', deleted: false, revision: randomUUID(), ttl: -1 });
      resource = created.resource;
    } catch (error) {
      if (typeof error !== 'object' || !error || !('code' in error) || Number(error.code) !== 409) throw error;
      resource = (await item.read()).resource;
    }
  }
  if (!resource) throw new ServiceError(503, 'Account state is unavailable.');
  if (resource.deleted) throw new ServiceError(410, 'Account data has been deleted.');
  return resource;
}

/** @param {string} userId */
async function rateLimit(userId) {
  const id = `rate:${Math.floor(Date.now() / 60000)}`;
  const item = container().item(id, userId);
  const { resource } = await item.read();
  const count = Number(resource?.count ?? 0);
  if (count >= 30) throw new ServiceError(429, 'Please wait before trying again.');
  try {
    if (resource) {
      await item.replace({ id, userId, type: 'rate', count: count + 1, ttl: 120 }, { accessCondition: { type: 'IfMatch', condition: resource._etag } });
    } else {
      await container().items.create({ id, userId, type: 'rate', count: 1, ttl: 120 });
    }
  } catch (error) {
    if (typeof error === 'object' && error && 'code' in error && [409, 412].includes(Number(error.code))) throw new ServiceError(429, 'Concurrent requests; retry later.');
    throw error;
  }
}

/** @param {string} userId */
async function readGarden(userId) {
  const { resources } = await container().items.query({
    query: 'SELECT c.type, c.record FROM c WHERE c.userId = @u AND c.type IN ("habits","checkins","reflections","voice")',
    parameters: [{ name: '@u', value: userId }],
  }, { partitionKey: userId }).fetchAll();
  /** @type {Record<string, unknown[]>} */
  const data = { habits: [], checkins: [], reflections: [], voice: [] };
  for (const resource of resources) data[resource.type].push(resource.record);
  return data;
}

/** @param {import('@azure/functions').HttpRequest} request */
async function sync(request) {
  const { userId } = await authenticate(request);
  await assertActive(userId);
  await rateLimit(userId);
  if (request.method === 'GET') return { jsonBody: await readGarden(userId) };
  const parsed = syncSchema.safeParse(await body(request));
  if (!parsed.success) throw new ServiceError(400, 'Sync payload failed validation.');
  const incoming = parsed.data;
  const owned = new Set(incoming.habits.map(h => h.id));
  const existing = await readGarden(userId);
  for (const habit of existing.habits) {
    if (typeof habit === 'object' && habit && 'id' in habit && typeof habit.id === 'string') owned.add(habit.id);
  }
  for (const row of [...incoming.checkins, ...incoming.reflections]) {
    if (!owned.has(row.habitId)) throw new ServiceError(400, 'Unknown habit reference.');
  }
  for (const [type, records] of Object.entries(incoming)) {
    for (const original of records) {
      /** @type {Record<string, string | number | number[] | null>} */
      const record = { ...original };
      const id = `${type}:${record.id}`;
      const item = container().item(id, userId);
      const { resource } = await item.read();
      if (type !== 'habits' && resource) continue; // Immutable client IDs are idempotent.
      if (type === 'habits' && resource) {
        if (!('updated' in record) || typeof record.updated !== 'string') throw new ServiceError(400, 'Missing update version.');
        if (Date.parse(resource.record.updated) >= Date.parse(record.updated)) continue;
        record.stage = Math.max(resource.record.stage, Number(record.stage));
      }
      if (type === 'voice') Object.assign(record, { status: 'received', replies: '[]' });
      if (type === 'reflections' && 'items' in record) record.items = JSON.stringify(record.items);
      const document = { id, userId, type, record, ttl: type === 'events' ? 34214400 : -1 };
      try {
        const gate = await assertActive(userId);
        const result = await container().items.batch([
          { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: { id: 'account', userId, type: 'account', deleted: false, revision: randomUUID(), ttl: -1 } },
          resource
            ? { operationType: 'Replace', id, ifMatch: resource._etag, resourceBody: document }
            : { operationType: 'Create', resourceBody: document },
        ], userId);
        if (result.code === undefined || result.code < 200 || result.code >= 300) throw new ServiceError(409, 'Concurrent sync; retry safely.');
      } catch (error) {
        if (typeof error === 'object' && error && 'code' in error && [409, 412].includes(Number(error.code))) throw new ServiceError(409, 'Concurrent sync; retry safely.');
        throw error;
      }
    }
  }
  return { jsonBody: { ...await readGarden(userId), acknowledgedEvents: incoming.events.map(e => e.id) } };
}

/** @param {import('@azure/functions').HttpRequest} request */
async function deleteAccount(request) {
  const { userId } = await authenticate(request);
  if (request.headers.get('x-confirm-delete') !== 'delete-my-garden') throw new ServiceError(400, 'Explicit deletion confirmation required.');
  const item = container().item('account', userId);
  const { resource } = await item.read();
  if (!resource) await assertActive(userId);
  const current = (await item.read()).resource;
  if (!current) throw new ServiceError(503, 'Account state is unavailable.');
  await item.replace({ id: 'account', userId, type: 'account', deleted: true, revision: randomUUID(), ttl: -1 }, { accessCondition: { type: 'IfMatch', condition: current._etag } });
  const { resources } = await container().items.query({ query: 'SELECT c.id FROM c WHERE c.userId = @u AND c.type != "account"', parameters: [{ name: '@u', value: userId }] }, { partitionKey: userId }).fetchAll();
  for (const row of resources) await container().item(row.id, userId).delete();
  return { status: 204 };
}

/** @param {import('@azure/functions').HttpRequest} request */
async function admin(request) {
  const actor = await authenticate(request);
  if (!isAdmin(actor.roles)) throw new ServiceError(403, 'Product team role required.');
  if (request.method === 'GET') {
    const { resources } = await container().items.query('SELECT TOP 100 c.userId, c.record FROM c WHERE c.type = "voice"').fetchAll();
    return { jsonBody: { feedback: resources } };
  }
  const userId = request.params.userId;
  if (!/^[a-f0-9]{64}$/.test(userId)) throw new ServiceError(400, 'Invalid account identifier.');
  const parsed = replySchema.safeParse(await body(request));
  if (!parsed.success) throw new ServiceError(400, 'Invalid status or reply.');
  const item = container().item(`voice:${parsed.data.id}`, userId);
  const { resource } = await item.read();
  if (!resource) throw new ServiceError(404, 'Feedback not found.');
  const replies = JSON.parse(resource.record.replies);
  resource.record.status = parsed.data.status;
  resource.record.replies = JSON.stringify([...replies, `${new Date().toISOString()}: ${parsed.data.reply}`]);
  await item.replace(resource, { accessCondition: { type: 'IfMatch', condition: resource._etag } });
  await container().items.create({ id: randomUUID(), userId: actor.userId, type: 'audit', target: userId, action: 'feedback_reply', ts: new Date().toISOString(), ttl: 34214400 });
  return { jsonBody: { updated: true } };
}

/**
 * @param {(request: import('@azure/functions').HttpRequest) => Promise<import('@azure/functions').HttpResponseInit>} handler
 */
function guarded(handler) {
  /** @param {import('@azure/functions').HttpRequest} request @param {import('@azure/functions').InvocationContext} context */
  return async (request, context) => {
    try {
      const result = await handler(request);
      return { ...result, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } };
    } catch (error) {
      if (error instanceof ServiceError) return { status: error.status, jsonBody: { error: error.message } };
      context.error('Request failed; request body and tokens intentionally omitted.');
      return { status: 500, jsonBody: { error: 'The request failed. Your local garden is safe; retry later.' } };
    }
  };
}

app.http('sync', { route: 'sync', methods: ['GET', 'POST'], authLevel: 'anonymous', handler: guarded(sync) });
app.http('deleteAccount', { route: 'account', methods: ['DELETE'], authLevel: 'anonymous', handler: guarded(deleteAccount) });
app.http('adminFeedback', { route: 'admin/feedback/{userId?}', methods: ['GET', 'POST'], authLevel: 'anonymous', handler: guarded(admin) });
