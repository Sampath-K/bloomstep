import { z } from 'zod';
import { isAdmin } from './contracts.mjs';
import { ServiceError } from './backend.mjs';
import { summarizeWebCounts } from './website-funnel.mjs';
import { addDays } from './dashboards.mjs';
import {
  ARMS, CATALOG, DESIGN, OUTCOMES, assignArm, canonicalJson, catalogEntry, evaluate, freezeInstance, policyHash,
  selectNext, sha256Hex, subjectHash, verifyInstance,
} from './experiment-policy.mjs';

export const PARTITIONS = Object.freeze({ production: '__experiments', isolated: '__experiments_isolated' });
const subjectTtlSeconds = 90 * 86400;
const auditLimit = 500, concludedLimit = 50;

const exposureSchema = z.strictObject({
  experimentId: z.string().regex(/^[a-z0-9-]{1,40}\.\d{8}T\d{6}$/), definitionHash: z.string().regex(/^[a-f0-9]{64}$/),
  subjectId: z.uuid(), arm: z.enum(ARMS), applied: z.boolean(),
});
const outcomeSchema = z.strictObject({
  experimentId: z.string().regex(/^[a-z0-9-]{1,40}\.\d{8}T\d{6}$/), subjectId: z.uuid(), event: z.enum(OUTCOMES),
});
const forgetSchema = z.strictObject({ subjectId: z.uuid() });
const killSchema = z.strictObject({ killed: z.boolean(), reason: z.string().regex(/^[\w .,:;()/-]{1,160}$/) });
export const receiptSchema = z.object({
  schemaVersion: z.literal(1), kind: z.literal('bloomstep-experiment-isolated-acceptance'), result: z.literal('passed'),
  policyVersion: z.string(), policyHash: z.string().regex(/^[a-f0-9]{64}$/),
  segregation: z.object({ environment: z.literal('isolated'), productionDocuments: z.literal(0), syntheticOnly: z.literal(true) }),
  scenarios: z.array(z.object({ name: z.string(), passed: z.literal(true) })).min(6),
  // Declares only what this isolated run depends on; it is not a statement about the actual hosting bill.
  costs: z.object({
    declaration: z.literal('run_dependencies_only'), paidServices: z.array(z.never()).length(0),
    newBillableResources: z.array(z.never()).length(0), actualHostingBill: z.literal('not_measured'),
  }),
});

/** @returns {{exposed:number,converted:{primary_cta_click:number,download_click:number},errors:number}} */
const emptyArm = () => ({ exposed: 0, converted: { primary_cta_click: 0, download_click: 0 }, errors: 0 });

/** Bounded raw-body reader shared by public experiment routes. @param {import('@azure/functions').HttpRequest} request */
async function readJson(request) {
  if (!/^application\/json(?:;|$)/i.test(request.headers.get('content-type') ?? '')) throw new ServiceError(400, 'JSON required.');
  const declared = request.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > 1024)) throw new ServiceError(413, 'Experiment observation too large.');
  const raw = await request.text();
  if (Buffer.byteLength(raw) > 1024) throw new ServiceError(413, 'Experiment observation too large.');
  try { return JSON.parse(raw); } catch { throw new ServiceError(400, 'Invalid JSON.'); }
}
/** @template T @param {z.ZodType<T>} schema @param {unknown} value @returns {T} */
function parse(schema, value) {
  const result = schema.safeParse(value);
  if (!result.success) throw new ServiceError(400, 'Invalid experiment request.');
  return result.data;
}

/**
 * @param {{
 *  container:()=>import('@azure/cosmos').Container,
 *  environment:'production'|'isolated',
 *  authenticate:(request:import('@azure/functions').HttpRequest)=>Promise<{roles:unknown}>,
 *  authenticateWorker:(request:import('@azure/functions').HttpRequest)=>Promise<{roles:unknown}>,
 *  operationalEnabled?:()=>Promise<void>,
 *  settings?:()=>{production?:string, acceptanceSha256?:string, disabled?:string},
 *  stageSummary?:()=>Promise<unknown>,
 *  clock?:()=>Date,
 * }} dependencies
 */
export function createExperimentHandlers({ container, environment, authenticate, authenticateWorker,
  operationalEnabled = async () => {}, settings = () => ({}), stageSummary, clock = () => new Date() }) {
  if (!(environment in PARTITIONS)) throw Error('Unknown experiment environment.');
  const partition = PARTITIONS[environment];
  let admissionMinute = -1, admissionCount = 0;
  function admit() {
    const minute = Math.floor(clock().getTime() / 60000);
    if (minute !== admissionMinute) { admissionMinute = minute; admissionCount = 0; }
    if (++admissionCount > 120) throw new ServiceError(429, 'Experiment admission cap reached; observation not recorded.');
  }
  /** @param {string} id */
  async function read(id) {
    const { resource } = await container().item(id, partition).read();
    return resource ?? null;
  }
  async function readState() {
    const state = await read('state');
    if (state && (state.type !== 'experiment_state' || state.schemaVersion !== 1 || !Array.isArray(state.audit) || !state._etag)) {
      throw new ServiceError(503, 'Experiment state is invalid; experiments halted.');
    }
    return state ?? { id: 'state', userId: partition, type: 'experiment_state', schemaVersion: 1, environment,
      killed: false, killReason: null, active: null, concluded: [], promotions: [], acceptance: null, audit: [] };
  }
  /** @param {import('@azure/cosmos').OperationInput[]} operations */
  async function commit(operations) {
    try {
      const response = await container().items.batch(operations, partition);
      if (response.code === undefined) throw new ServiceError(503, 'Experiment transaction status unavailable.');
      if (response.code >= 400) throw Object.assign(Error('Experiment transaction rejected.'), { code: response.code });
    } catch (error) {
      if (typeof error === 'object' && error && 'code' in error && [409, 412, 424].includes(Number(error.code))) {
        throw new ServiceError(429, 'Concurrent experiment update; retry once later.');
      }
      throw error;
    }
  }
  /** @param {any} doc @param {any} old */
  const put = (doc, old) => /** @type {import('@azure/cosmos').OperationInput} */ (old?._etag ?
    { operationType: 'Replace', id: doc.id, ifMatch: old._etag, resourceBody: strip(doc) } :
    { operationType: 'Create', resourceBody: strip(doc) });
  /** @param {any} doc */
  function strip(doc) { const { _etag, _rid, _self, _ts, _attachments, ...rest } = doc; return rest; }
  /** @param {any} state @param {string} action @param {Record<string,unknown>} detail */
  function audit(state, action, detail) {
    state.audit = [...state.audit, { at: clock().toISOString(), action, ...detail }].slice(-auditLimit);
  }

  /** Settings-only gate evaluated before any storage access, so OFF production performs no network I/O. */
  function settingsGate() {
    const env = settings();
    if (['true', '1'].includes(String(env.disabled ?? '').toLowerCase())) return { enabled: false, reason: 'disabled_by_environment' };
    if (environment === 'isolated') return { enabled: true, reason: null };
    if (env.production !== 'enabled') return { enabled: false, reason: 'production_not_enabled' };
    if (!/^[a-f0-9]{64}$/.test(env.acceptanceSha256 ?? '')) return { enabled: false, reason: 'acceptance_hash_not_configured' };
    return { enabled: true, reason: null };
  }

  /** Production requires deployment opt-in AND a server-verified acceptance receipt for this exact policy. */
  async function gate(/** @type {any} */ state) {
    const env = settings(), early = settingsGate();
    if (!early.enabled) return early;
    if (state.killed) return { enabled: false, reason: 'killed' };
    if (environment === 'isolated') return { enabled: true, reason: null };
    if (state.acceptance?.sha256 !== env.acceptanceSha256 || state.acceptance?.policyHash !== await policyHash()) {
      return { enabled: false, reason: 'acceptance_receipt_not_verified' };
    }
    return { enabled: true, reason: null };
  }

  function refuseIfOff() {
    const early = settingsGate();
    if (!early.enabled) throw new ServiceError(503, `Experiments unavailable: ${early.reason}.`);
  }

  /** GET /api/web/experiments — public config readback for consented visits. */
  async function config() {
    admit();
    const early = settingsGate();
    if (!early.enabled) return { status: 200, jsonBody: { schemaVersion: 1, enabled: false, reason: early.reason, active: null } };
    await operationalEnabled();
    const state = await readState(), status = await gate(state);
    const now = clock().getTime();
    const live = status.enabled && state.active && Date.parse(state.active.startAt) <= now && now < Date.parse(state.active.endAt);
    return { status: 200, jsonBody: { schemaVersion: 1, enabled: status.enabled, reason: status.reason ?? (state.active ? (live ? null : 'outside_horizon') : 'no_active_experiment'),
      active: live ? state.active : null } };
  }

  /** @param {any} state @param {string} experimentId */
  async function requireLive(state, experimentId) {
    const status = await gate(state);
    if (!status.enabled) throw new ServiceError(503, `Experiments unavailable: ${status.reason}.`);
    const now = clock().getTime();
    if (!state.active || state.active.experimentId !== experimentId) throw new ServiceError(409, 'Experiment is not active.');
    if (now < Date.parse(state.active.startAt) || now >= Date.parse(state.active.endAt)) throw new ServiceError(409, 'Outside the pre-registered horizon; not recorded.');
    return state.active;
  }

  /** POST /api/web/experiments/exposure — must be persisted before any outcome is accepted. */
  async function exposure(/** @type {import('@azure/functions').HttpRequest} */ request) {
    if (request.headers.get('dnt') === '1' || request.headers.get('sec-gpc') === '1') return { status: 204 };
    admit();
    const value = parse(exposureSchema, await readJson(request));
    refuseIfOff();
    await operationalEnabled();
    const state = await readState(), active = await requireLive(state, value.experimentId);
    if (active.definitionHash !== value.definitionHash) throw new ServiceError(409, 'Definition hash mismatch; stale or altered experiment.');
    const hash = await subjectHash(value.subjectId);
    const existing = await read(`visit:${hash}`);
    if (existing?.forgotten) throw new ServiceError(410, 'This visit withdrew consent; nothing recorded.');
    if (await assignArm(active, value.subjectId) !== value.arm) throw new ServiceError(400, 'Arm does not match deterministic assignment.');
    if (existing) {
      if (existing.experimentId === value.experimentId && existing.arm === value.arm) return { status: 200, jsonBody: { recorded: false, duplicate: true } };
      throw new ServiceError(409, 'Visit already exposed to a different arm or experiment.');
    }
    const countsId = `counts:${value.experimentId}`, old = await read(countsId);
    const counts = structuredClone(old ?? { id: countsId, userId: partition, type: 'experiment_counts', schemaVersion: 1,
      experimentId: value.experimentId, definitionHash: active.definitionHash, arms: { control: emptyArm(), candidate: emptyArm() }, looksDone: [] });
    if (counts.arms[value.arm].exposed >= DESIGN.maxSubjectsPerArm) throw new ServiceError(429, 'Experiment arm volume cap reached; not recorded.');
    counts.arms[value.arm].exposed++;
    if (!value.applied) counts.arms[value.arm].errors++;
    const now = clock().toISOString();
    // One per-visit document: Create fails atomically if a consent withdrawal tombstone landed concurrently.
    await commit([put(counts, old), { operationType: 'Create', resourceBody: { id: `visit:${hash}`, userId: partition, type: 'experiment_visit',
      schemaVersion: 1, forgotten: false, experimentId: value.experimentId, arm: value.arm, applied: value.applied, exposedAt: now, outcomes: {}, ttl: subjectTtlSeconds } }]);
    return { status: 201, jsonBody: { recorded: true, arm: value.arm } };
  }

  /** POST /api/web/experiments/outcome */
  async function outcome(/** @type {import('@azure/functions').HttpRequest} */ request) {
    if (request.headers.get('dnt') === '1' || request.headers.get('sec-gpc') === '1') return { status: 204 };
    admit();
    const value = parse(outcomeSchema, await readJson(request));
    refuseIfOff();
    await operationalEnabled();
    const hash = await subjectHash(value.subjectId);
    const subject = await read(`visit:${hash}`);
    if (subject?.forgotten) throw new ServiceError(410, 'This visit withdrew consent; nothing recorded.');
    const state = await readState();
    await requireLive(state, value.experimentId);
    if (!subject || subject.experimentId !== value.experimentId) throw new ServiceError(409, 'Exposure must be persisted before outcomes.');
    if (subject.outcomes[value.event]) return { status: 200, jsonBody: { recorded: false, duplicate: true } };
    const countsId = `counts:${value.experimentId}`, old = await read(countsId);
    if (!old) throw new ServiceError(503, 'Experiment counts missing; outcome not recorded.');
    const counts = structuredClone(old), next = structuredClone(subject);
    next.outcomes[value.event] = clock().toISOString();
    counts.arms[subject.arm].converted[value.event]++;
    await commit([put(counts, old), put(next, subject)]);
    return { status: 201, jsonBody: { recorded: true } };
  }

  /** POST /api/web/experiments/forget — deletes the visit, removes its contribution, blocks late writes. */
  async function forget(/** @type {import('@azure/functions').HttpRequest} */ request) {
    admit();
    const value = parse(forgetSchema, await readJson(request));
    const hash = await subjectHash(value.subjectId);
    const subject = await read(`visit:${hash}`);
    if (subject?.forgotten) return { status: 200, jsonBody: { deleted: false } };
    // The visit document becomes a content-free tombstone (TTL) so late exposures/outcomes cannot recreate it.
    const tombstone = { id: `visit:${hash}`, userId: partition, type: 'experiment_visit', schemaVersion: 1, forgotten: true, ttl: subjectTtlSeconds };
    /** @type {import('@azure/cosmos').OperationInput[]} */
    const operations = [put(tombstone, subject)];
    if (subject) {
      const countsId = `counts:${subject.experimentId}`, old = await read(countsId);
      if (old) {
        const counts = structuredClone(old), arm = counts.arms[subject.arm];
        arm.exposed = Math.max(0, arm.exposed - 1);
        if (!subject.applied) arm.errors = Math.max(0, arm.errors - 1);
        for (const name of OUTCOMES) if (subject.outcomes[name]) arm.converted[name] = Math.max(0, arm.converted[name] - 1);
        operations.push(put(counts, old));
      }
    }
    await commit(operations);
    return { status: 200, jsonBody: { deleted: !!subject } };
  }

  /** Scheduled bounded worker step: evaluate active experiment, conclude/rollback, then prioritize & launch next. */
  async function tick(/** @type {import('@azure/functions').HttpRequest} */ request) {
    const actor = await authenticateWorker(request);
    if (!Array.isArray(actor.roles) || !actor.roles.includes('Bloomstep.AggregateWriter') || isAdmin(actor.roles)) {
      throw new ServiceError(403, 'Isolated experiment worker role required.');
    }
    admit();
    const early = settingsGate();
    if (!early.enabled) return { status: 200, jsonBody: { schemaVersion: 1, status: 'disabled', reason: early.reason, actions: [] } };
    await operationalEnabled();
    const old = await readState(), state = structuredClone(old), status = await gate(state);
    if (!status.enabled) return { status: 200, jsonBody: { schemaVersion: 1, status: 'disabled', reason: status.reason, actions: [] } };
    const now = clock(), actions = [];
    /** @type {import('@azure/cosmos').OperationInput[]} */
    const operations = [];
    if (state.active) {
      const countsId = `counts:${state.active.experimentId}`, oldCounts = await read(countsId);
      const counts = oldCounts?.arms ?? { control: emptyArm(), candidate: emptyArm() };
      const decision = await evaluate(state.active, counts, now, oldCounts?.looksDone ?? []);
      actions.push({ action: 'evaluate', experimentId: state.active.experimentId, decision });
      if (decision.terminal) {
        const record = { key: state.active.key, experimentId: state.active.experimentId, definitionHash: state.active.definitionHash,
          surface: state.active.surface, decision: decision.status, promote: decision.promote, rollback: decision.rollback,
          reason: decision.reason, stats: decision.stats ?? null, counts, concludedAt: now.toISOString() };
        state.concluded = [...state.concluded, record].slice(-concludedLimit);
        if (decision.promote) {
          state.promotions = [...state.promotions, { key: record.key, experimentId: record.experimentId, definitionHash: record.definitionHash,
            decision: 'promote', status: environment === 'production' ? 'pending_build_via_draft_pr' : 'isolated_acceptance_only', at: record.concludedAt }];
        }
        audit(state, decision.promote ? 'promote' : decision.rollback ? 'rollback' : 'retain_control', { experimentId: record.experimentId, decision: decision.status });
        state.active = null;
      } else if (decision.look !== undefined && oldCounts) {
        const counts = structuredClone(oldCounts);
        counts.looksDone = [...new Set([...counts.looksDone, decision.look])];
        operations.push(put(counts, oldCounts));
        audit(state, 'harm_look', { experimentId: state.active.experimentId, look: decision.look });
      }
    }
    if (!state.active) {
      const summary = stageSummary ? await stageSummary() : null;
      const choice = selectNext(/** @type {any} */ (summary), state.concluded.map((/** @type {{key:string}} */ row) => row.key),
        state.promotions.map((/** @type {{key:string}} */ row) => catalogEntry(row.key)?.surface ?? ''));
      actions.push({ action: 'prioritize', status: choice.status, stage: choice.stage, key: choice.entry?.key ?? null });
      if (choice.entry) {
        state.active = await freezeInstance(choice.entry, { startAt: now.toISOString(), environment });
        audit(state, 'launch', { experimentId: state.active.experimentId, definitionHash: state.active.definitionHash, stage: choice.stage });
      } else audit(state, 'no_launch', { reason: choice.status });
    }
    await commit([put(state, old), ...operations]);
    return { status: 200, jsonBody: { schemaVersion: 1, status: 'ok', active: state.active?.experimentId ?? null, actions } };
  }

  async function requireAdmin(/** @type {import('@azure/functions').HttpRequest} */ request) {
    const actor = await authenticate(request);
    if (!isAdmin(actor.roles)) throw new ServiceError(403, 'Bloomstep.Admin required.');
    admit();
  }

  /** POST /api/team/experiments/kill — immediate rollback to control and halt. */
  async function kill(/** @type {import('@azure/functions').HttpRequest} */ request) {
    await requireAdmin(request);
    const value = parse(killSchema, await readJson(request));
    const old = await readState(), state = structuredClone(old);
    if (value.killed && state.active) {
      state.concluded = [...state.concluded, { key: state.active.key, experimentId: state.active.experimentId, definitionHash: state.active.definitionHash,
        surface: state.active.surface, decision: 'killed', promote: false, rollback: true, reason: value.reason, stats: null, counts: null,
        concludedAt: clock().toISOString() }].slice(-concludedLimit);
      state.active = null;
    }
    state.killed = value.killed; state.killReason = value.killed ? value.reason : null;
    audit(state, value.killed ? 'kill' : 'unkill', { reason: value.reason });
    await commit([put(state, old)]);
    return { status: 200, jsonBody: { killed: state.killed } };
  }

  /** POST /api/team/experiments/acceptance — server recomputes receipt hash + policy hash; never self-attested. */
  async function acceptance(/** @type {import('@azure/functions').HttpRequest} */ request) {
    await requireAdmin(request);
    const raw = await request.text();
    if (Buffer.byteLength(raw) > 65536) throw new ServiceError(413, 'Receipt too large.');
    let parsed; try { parsed = JSON.parse(raw); } catch { throw new ServiceError(400, 'Invalid JSON.'); }
    const receipt = parse(receiptSchema, parsed);
    const sha256 = await sha256Hex(canonicalJson(parsed)), expected = settings().acceptanceSha256;
    if (receipt.policyHash !== await policyHash()) throw new ServiceError(409, 'Receipt is for a different experiment policy/catalog.');
    if (!expected || sha256 !== expected) throw new ServiceError(409, 'Receipt hash does not match the deployment-configured acceptance hash.');
    const old = await readState(), state = structuredClone(old);
    state.acceptance = { sha256, policyHash: receipt.policyHash, verifiedAt: clock().toISOString() };
    audit(state, 'acceptance_verified', { sha256 });
    await commit([put(state, old)]);
    return { status: 200, jsonBody: { verified: true, sha256 } };
  }

  /** GET /api/team/experiments — private audit/export (aggregate counts only, no visit hashes). */
  async function report(/** @type {import('@azure/functions').HttpRequest} */ request) {
    await requireAdmin(request);
    const state = await readState(), status = await gate(state);
    const activeCounts = state.active ? (await read(`counts:${state.active.experimentId}`))?.arms ?? null : null;
    return { status: 200, jsonBody: { schemaVersion: 1, environment, policyHash: await policyHash(), enabled: status.enabled, reason: status.reason,
      killed: state.killed, active: state.active, activeCounts: null, activeCountsWithheld: !!activeCounts,
      concluded: state.concluded, promotions: state.promotions, audit: state.audit, catalog: CATALOG.map(entry => entry.key),
      definition: 'Unit: consented website visit (page memory; reloads/new tabs are new units, not people). Primary: download_click per exposed visit, intent-to-treat. Interim counts withheld until conclusion to prevent peeking. Activation/install are unobservable for website variants; no causal claim about people or activation.',
      retention: { subjectsAndTombstonesDays: 90, auditEntries: auditLimit, concluded: concludedLimit } } };
  }
  return { config, exposure, outcome, forget, tick, kill, acceptance, report };
}

/** Prioritization input from the foundation website counts (never used for evaluation). */
export function websiteStageSummary(/** @type {()=>import('@azure/cosmos').Container} */ container, /** @type {string} */ partitionKey, clock = () => new Date()) {
  return async () => {
    const endDay = addDays(clock().toISOString().slice(0, 10), -1), startDay = addDays(endDay, -27);
    const { resources } = await container().items.query({
      query: 'SELECT TOP 31 c.day, c.counts, c.accepted FROM c WHERE c.type = "website_daily" AND c.day >= @start AND c.day <= @end',
      parameters: [{ name: '@start', value: startDay }, { name: '@end', value: endDay }],
    }, { partitionKey }).fetchAll();
    return summarizeWebCounts({ days: Object.fromEntries(resources.map(row => [row.day, row])) }, startDay, endDay);
  };
}
