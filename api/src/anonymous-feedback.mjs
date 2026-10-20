import { createHmac, randomUUID } from 'node:crypto';
import { isIP } from 'node:net';
import { z } from 'zod';
import { ServiceError } from './backend.mjs';

export const feedbackLimits = Object.freeze({
  bodyBytes: 8192, textCharacters: 2000, devicePerDay: 3,
  ipPerDay: 10, globalPerDay: 100, retentionSeconds: 7 * 86400,
});
const partition = '__anonymous_feedback';
const text = z.string().refine(value => value.trim().length > 0 &&
  Array.from(value).length <= feedbackLimits.textCharacters &&
  !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value));
const bodySchema = z.strictObject({
  consent: z.literal(true), deviceId: z.uuidv4(), requestId: z.uuidv4(),
  text: text.optional(), rating: z.number().int().min(1).max(5).optional(),
}).refine(value => value.text !== undefined || value.rating !== undefined);
/** @typedef {{id:string,userId:string,type:string,count:number,ttl:number,_etag?:string}} Counter */
/** @typedef {{id:string,userId:string,type:string,digest:string,receiptId:string,receivedAt:string,expiresAt:number,ttl:number,text?:string,rating?:number}} Receipt */

/** Stream rather than trusting Content-Length.
 * @param {import('@azure/functions').HttpRequest | Request} request */
async function readBody(request) {
  const length = request.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > feedbackLimits.bodyBytes)) {
    throw new ServiceError(413, 'Feedback body too large.');
  }
  if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type') ?? '')) {
    throw new ServiceError(415, 'JSON required.');
  }
  if (!request.body) throw new ServiceError(400, 'Invalid feedback.');
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > feedbackLimits.bodyBytes) {
        await reader.cancel();
        throw new ServiceError(413, 'Feedback body too large.');
      }
      chunks.push(value);
    }
    const parsed = bodySchema.safeParse(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))));
    if (!parsed.success) throw new ServiceError(400, 'Invalid feedback.');
    return parsed.data;
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    throw new ServiceError(400, 'Invalid feedback.');
  } finally { reader.releaseLock(); }
}

/**
 * All receipts and counters share one Cosmos partition: their four writes commit
 * together, including global quota CAS, across instances and restarts.
 * @param {{
 * container:()=>import('@azure/cosmos').Container,
 * settings:()=>Record<string,string|undefined>,
 * clock?:()=>Date
 * }} dependencies
 */
export function createAnonymousFeedbackHandler({ container, settings, clock = () => new Date() }) {
  /** @param {import('@azure/functions').HttpRequest | Request} request */
  return async function submit(request) {
    const config = settings();
    const secret = config.ANONYMOUS_FEEDBACK_HASH_SECRET;
    const header = config.ANONYMOUS_FEEDBACK_TRUSTED_IP_HEADER;
    if (config.BUDLARK_ANONYMOUS_FEEDBACK !== 'enabled' || !secret || Buffer.byteLength(secret) < 32 ||
        !header || !['x-azure-clientip', 'x-forwarded-for'].includes(header) ||
        ['true', '1'].includes((config.BUDLARK_API_DISABLED ?? '').toLowerCase())) {
      throw new ServiceError(503, 'Anonymous feedback is not configured.');
    }
    // Deployment MUST overwrite this header at a trusted ingress; never take an
    // arbitrary first forwarded address, alternate header, or caller fallback.
    const suppliedIp = request.headers.get(header);
    if (!suppliedIp || !isIP(suppliedIp)) throw new ServiceError(503, 'Feedback ingress unavailable.');
    const ip = new URL(`http://${suppliedIp.includes(':') ? `[${suppliedIp}]` : suppliedIp}`).hostname;
    const value = await readBody(request);
    const now = clock();
    const day = now.toISOString().slice(0, 10);
    /** @param {string} label @param {string} value */
    const hash = (label, value) => createHmac('sha256', secret).update(`${label}\0${value}`).digest('hex');
    const deviceHash = hash('device', value.deviceId.toLowerCase());
    const receiptKey = `receipt:${hash('request', value.requestId.toLowerCase())}`;
    const digest = hash('payload', JSON.stringify({ deviceHash, text: value.text ?? null, rating: value.rating ?? null }));
    /** @param {Receipt} saved */
    function response(saved) {
      if (saved.digest !== digest) throw new ServiceError(409, 'Feedback request key already used.');
      if (saved.expiresAt <= now.getTime()) throw new ServiceError(410, 'Feedback request expired.');
      return { status: 200, jsonBody: { status: 'received', receiptId: saved.receiptId, receivedAt: saved.receivedAt } };
    }
    try {
      const store = container();
      const metadata = (await store.read()).resource;
      if (!metadata || !Number.isInteger(metadata.defaultTtl) ||
          !(metadata.defaultTtl === -1 || Number(metadata.defaultTtl) > 0) ||
          JSON.stringify(metadata.partitionKey?.paths) !== '["/userId"]') {
        throw new ServiceError(503, 'Feedback retention storage unavailable.');
      }
      /** @template T @param {string} id @returns {Promise<T | undefined>} */
      async function read(id) {
        try { return (await store.item(id, partition).read()).resource; }
        catch (error) {
          if (typeof error === 'object' && error && 'code' in error && Number(error.code) === 404) return undefined;
          throw error;
        }
      }
      const limits = [
        { id: `global:${day}`, limit: feedbackLimits.globalPerDay },
        { id: `device:${day}:${deviceHash}`, limit: feedbackLimits.devicePerDay },
        { id: `ip:${day}:${hash('ip', ip)}`, limit: feedbackLimits.ipPerDay },
      ];
      for (let attempt = 0; attempt < 24; attempt++) {
        const existing = await read(receiptKey);
        if (existing) return response(/** @type {Receipt} */ (existing));
        const counters = await Promise.all(limits.map(async ({ id, limit }) => {
          const old = /** @type {Counter | undefined} */ (await read(id));
          if (old && (!old._etag || !Number.isSafeInteger(old.count) || old.count < 0)) {
            throw new ServiceError(503, 'Feedback quota unavailable.');
          }
          if ((old?.count ?? 0) >= limit) throw new ServiceError(429, 'Daily anonymous feedback limit reached.');
          const document = { id, userId: partition, type: 'anonymous_feedback_budget',
            count: (old?.count ?? 0) + 1, ttl: 2 * 86400 };
          return old
            ? { operationType: /** @type {const} */ ('Replace'), id, ifMatch: old._etag, resourceBody: document }
            : { operationType: /** @type {const} */ ('Create'), resourceBody: document };
        }));
        /** @type {Receipt} */
        const saved = { id: receiptKey, userId: partition, type: 'anonymous_feedback',
          digest, receiptId: randomUUID(), receivedAt: now.toISOString(),
          expiresAt: now.getTime() + feedbackLimits.retentionSeconds * 1000,
          ttl: feedbackLimits.retentionSeconds,
          ...(value.text !== undefined ? { text: value.text } : {}),
          ...(value.rating !== undefined ? { rating: value.rating } : {}) };
        let code;
        try {
          const result = await store.items.batch([
            ...counters, { operationType: 'Create', resourceBody: saved },
          ], partition);
          code = result.code;
          if (code === 200 && result.result?.length === 4 &&
              result.result.every(operation => [200, 201].includes(operation.statusCode))) {
            return { ...response(saved), status: 201 };
          }
        } catch (error) {
          if (typeof error === 'object' && error && 'code' in error) code = Number(error.code);
        }
        if (![409, 412, 424].includes(Number(code))) throw new ServiceError(503, 'Feedback save unavailable; retry with the same key.');
      }
      throw new ServiceError(429, 'Feedback is busy; retry with the same key.');
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      // Never expose/log storage errors, addresses, feedback text, or headers.
      throw new ServiceError(503, 'Feedback save unavailable; retry with the same key.');
    }
  };
}
