import { z } from 'zod';
import { isAdmin } from './contracts.mjs';
import { ServiceError } from './backend.mjs';
import { normalizedEvents, addDays, timestampKey } from './dashboards.mjs';
import { createHash } from 'node:crypto';
import { attributionFields, touchNames } from './website-attribution.mjs';

const touchSchema = z.strictObject({
  source: z.enum(attributionFields.source),
  referrerDomain: z.enum(attributionFields.referrerDomain),
  campaignSource: z.enum(attributionFields.campaignSource),
  campaignMedium: z.enum(attributionFields.campaignMedium),
  campaignName: z.enum(attributionFields.campaignName),
});
const attributionKey = z.string().refine(key => {
  const [touch, stage, field, value, extra] = key.split(':');
  return extra === undefined && touchNames.includes(touch) && stages.includes(stage) &&
    Object.hasOwn(attributionFields, field) &&
    attributionFields[/** @type {keyof typeof attributionFields} */ (field)].includes(value);
});

const stages = ['landing_view', 'primary_cta_click', 'download_click'];
const sources = ['search', 'referral', 'direct', 'campaign', 'unknown'];
const architectures = ['arm64', 'x64', 'unknown'];
const budgetSchema = z.object({
  id: z.literal('budget'), userId: z.enum(['__website_counts','__website_synthetic']),
  type: z.literal('website_budget'), schemaVersion: z.literal(1),
  accepted: z.number().int().min(0).max(10000), minute: z.number().int().min(0),
  minuteCount: z.number().int().min(0).max(30), reads: z.number().int().min(0).max(30),
  readDay: z.union([z.literal(''), z.iso.date()]), ttl: z.literal(-1), _etag: z.string(),
  recent: z.array(z.strictObject({ key: z.string().regex(/^[a-f0-9]{64}$/),
    content: z.string().regex(/^[a-f0-9]{64}$/), expires: z.number().int().min(0) })).max(180).optional(),
});
const daySchema = z.object({
  id: z.iso.date(), day: z.iso.date(), userId: z.enum(['__website_counts','__website_synthetic']),
  type: z.literal('website_daily'), schemaVersion: z.literal(1),
  counts: z.record(z.string().regex(/^(?:landing_view|primary_cta_click|download_click):(?:search|referral|direct|campaign|unknown):(?:arm64|x64|unknown)$/),
    z.number().int().min(1).max(400)),
  accepted: z.number().int().min(1).max(400), ttl: z.number().int().min(1).max(90 * 86400), _etag: z.string(),
  attributionCounts: z.record(attributionKey, z.number().int().min(1).max(400)).optional(),
}).refine(day => day.id === day.day && Object.values(day.counts).reduce((sum, count) => sum + count, 0) === day.accepted)
  .refine(day => touchNames.every(touch => stages.every(stage => Object.keys(attributionFields).every(field =>
    Object.entries(day.attributionCounts ?? {}).filter(([key]) => key.startsWith(`${touch}:${stage}:${field}:`))
      .reduce((sum, [, count]) => sum + count, 0) <=
    Object.entries(day.counts).filter(([key]) => key.startsWith(`${stage}:`)).reduce((sum, [, count]) => sum + count, 0)))));
const schema = z.strictObject({
  channel: z.literal('web'),
  event: z.enum(['landing_view', 'primary_cta_click', 'download_click']),
  source: z.enum(['search', 'referral', 'direct', 'campaign', 'unknown']),
  architecture: z.enum(['arm64', 'x64', 'unknown']),
  eventId: z.uuid(),
  synthetic: z.boolean(),
  observedAt: z.iso.datetime({ precision: 3 }).optional(),
  attribution: z.strictObject({ firstTouch: touchSchema, lastTouch: touchSchema }).optional(),
  utm: z.strictObject({
    utm_source: z.string().regex(/^[a-zA-Z0-9_-]{1,48}$/).optional(),
    utm_medium: z.string().regex(/^[a-zA-Z0-9_-]{1,48}$/).optional(),
    utm_campaign: z.string().regex(/^[a-zA-Z0-9_-]{1,48}$/).optional(),
  }).optional(),
}).refine(value => value.event === 'download_click' || value.architecture === 'unknown')
  .refine(value => !value.attribution || value.observedAt !== undefined &&
    value.source === value.attribution.lastTouch.source);

/** @param {unknown} value */
export function validateWebPayload(value) {
  const result = schema.safeParse(value);
  if (!result.success) throw new ServiceError(400, 'Invalid website observation.');
  return result.data;
}
/** @typedef {{ counts: Record<string, number>, accepted: number, attributionCounts?:Record<string,number> }} DayCounts */
/** @typedef {{id:string,userId:string,type:string,schemaVersion:1,accepted:number,minute:number,minuteCount:number,reads:number,readDay:string,ttl:number,_etag?:string,recent?:{key:string,content:string,expires:number}[]}} WebBudget */
/** @typedef {DayCounts & {id:string,userId:string,type:string,day:string,schemaVersion:1,ttl:number,_etag?:string}} WebDay */
/** @param {{days:Record<string,DayCounts>} | null} document @param {string} startDay @param {string} endDay */
export function summarizeWebCounts(document, startDay, endDay) {
  /** @type {{day:string,counts:Record<string,number>|null}[]} */
  const daily = [];
  for (let day = startDay; day <= endDay; day = addDays(day, 1)) {
    daily.push({ day, counts: document?.days[day]?.counts ?? null });
  }
  /** @param {(key:string)=>boolean} match */
  const total = match => {
    const numbers = daily.flatMap(row => Object.entries(row.counts ?? {}).filter(([key]) => match(key)).map(([, count]) => count));
    return numbers.length ? numbers.reduce((a, b) => a + b, 0) : null;
  };
  const totals = Object.fromEntries(stages.map(stage => [stage, total(key => key.split(':')[0] === stage)]));
  /** Suppress the whole dimension if a small observed cell could be subtracted from its total.
   * @param {Record<string,number|null>} values */
  const suppress = values => Object.values(values).some(value => value !== null && value < 50) ?
    Object.fromEntries(Object.keys(values).map(key => [key, null])) : values;
  const acquisition = Object.fromEntries(touchNames.map(touch => [touch,
    Object.fromEntries(stages.map(stage => [stage, Object.fromEntries(Object.entries(attributionFields).map(([field, values]) => {
      const totals = Object.fromEntries(values.map(value => {
        // Read only selected UTC dates, never lifetime or outside-window cells.
        const observed = daily.flatMap(row => {
          const count = document?.days[row.day]?.attributionCounts?.[`${touch}:${stage}:${field}:${value}`];
          return count === undefined ? [] : [count];
        });
        return [value, observed.length ? observed.reduce((a, b) => a + b, 0) : null];
      }));
      return [field, suppress(totals)];
    }))]))]));
  return { schemaVersion: 1, channel: 'web', reservedChannels: ['store'], startDay, endDay,
    acquisition: { schemaVersion: 1, scope: 'consented_page_epoch', ...acquisition,
      definition: 'Allowlisted marginal event counts only. First/last touch refer to this consented page, not unique visitors or cross-visit attribution. Unknown is explicit; legacy events have no attributable cells. All cells in a marginal dimension are withheld if any observed cell is below 50; no daily drilldown or account linkage.' },
    stages: suppress(totals),
    sources: suppress(Object.fromEntries(sources.map(source => [source, total(key => key.split(':')[0] === 'landing_view' && key.split(':')[1] === source)]))),
    architectures: suppress(Object.fromEntries(architectures.map(arch => [arch, total(key => key.split(':')[0] === 'download_click' && key.split(':')[2] === arch)]))),
    steps: [['landing_view', 'primary_cta_click'], ['primary_cta_click', 'download_click']].map(([from, to]) => {
      const denominator = totals[from], numerator = totals[to];
      const publishable = Object.values(totals).every(value => value === null || value >= 50) &&
        denominator !== null && numerator !== null && denominator >= 50 && numerator >= 50;
      return { from, to, rate: publishable ? numerator / denominator : null, reason: publishable ? null : 'events_below_50' };
    }),
    daily: daily.map(row => ({ day: row.day, counts: null })),
    definition: 'Anonymous UTC daily event counts, not unique visitors. Event conversion — not unique visitors; repeat visits and bots may be counted. Ratios may exceed 100% and do not imply same-person transitions or successful file transfers. Stages need 50 events; small dimensions are suppressed together and daily drilldown is withheld to avoid subtractable cells. Missing/opted-out observations are unknown. Timestamped retries deduplicate transactionally for five minutes across hosts; legacy retries only deduplicate in-process. Synthetic observations are excluded.' };
}

/**
 * Per-account website-attributed activation, read only from persisted, explicitly linked account events.
 * Internal: callers must aggregate with suppression before exposing anything.
 * @param {{userId:string,record:unknown}[]} rows @param {string} startDay @param {string} endDay
 */
export function attributedActivationJourneys(rows, startDay, endDay) {
  const events = normalizedEvents(rows).filter(row => row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay)
    .sort((a, b) => timestampKey(a.record.ts).localeCompare(timestampKey(b.record.ts)));
  /** @type {Map<string,{download:string,recipeCreated:string|null,firstCompletion:string|null}>} */
  const journeys = new Map();
  /** @type {Map<string,Set<string>>} */
  const habits = new Map();
  for (const row of events) {
    const { name, ts, properties } = row.record;
    const journey = journeys.get(row.userId);
    if (name === 'download_click' && properties?.measurementSource === 'website_receipt') {
      if (!journey) journeys.set(row.userId, { download: ts, recipeCreated: null, firstCompletion: null });
    } else if (journey && name === 'recipe_created' && typeof properties?.habitId === 'string') {
      journey.recipeCreated ??= ts;
      habits.set(row.userId, (habits.get(row.userId) ?? new Set()).add(properties.habitId));
    } else if (journey && journey.recipeCreated && !journey.firstCompletion && name === 'checkin' &&
        ['did', 'didMore'].includes(String(properties?.result)) && habits.get(row.userId)?.has(String(properties?.habitId))) {
      journey.firstCompletion = ts;
    }
  }
  return journeys;
}

/** @param {{userId:string,record:unknown}[]} rows @param {string} startDay @param {string} endDay */
function attributedActivation(rows, startDay, endDay) {
  const journeys = [...attributedActivationJourneys(rows, startDay, endDay).values()];
  const sizes = [journeys.length, journeys.filter(j => j.recipeCreated).length, journeys.filter(j => j.firstCompletion).length];
  const names = ['website_receipt_download', 'recipe_created', 'first_completion'];
  const count = (/** @type {number} */ size) => size >= 50 ? size : null;
  return { schemaVersion: 1, minimumContributors: 50,
    stages: Object.fromEntries(names.map((name, index) => [name, count(sizes[index])])),
    steps: names.slice(1).map((name, index) => ({ from: names[index], to: name,
      rate: sizes[index] >= 50 && sizes[index + 1] >= 50 ? sizes[index + 1] / sizes[index] : null })),
    unobservable: ['download_completed', 'install_completed', 'first_launch_time', 'signin_succeeded'],
    definition: 'Distinct opted-in accounts that explicitly linked a website receipt containing a download click, then (in timestamp order) planted a habit, then first completed that same habit (did/didMore). Linking proves the app was later used by that account, not when it was installed or first launched. Stages and rates need 50 distinct accounts; others are null (unknown), never zero. Not a share of anonymous website visitors.' };
}

/** @param {{userId:string,record:unknown}[]} rows @param {string} startDay @param {string} endDay */
export function linkedWebFunnel(rows, startDay, endDay) {
  const events = normalizedEvents(rows).filter(row => row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay);
  const orderedStages = ['landing_view', 'download_click', 'install_completed', 'first_launch', 'signin_succeeded', 'first_checkin'];
  /** @type {Set<string>[]} */
  const groups = [];
  /** @type {Map<string,string>} */
  let previous = new Map();
  for (const [index, stage] of orderedStages.entries()) {
    const current = new Map();
    for (const row of events) {
      if (row.record.name !== stage || stage === 'landing_view' && row.record.properties?.measurementSource !== 'website_receipt' ||
          stage === 'download_click' && row.record.properties?.measurementSource !== 'website_receipt' ||
          ['install_completed','first_launch'].includes(stage) && row.record.properties?.measurementSource !== 'installer_receipt' ||
          stage === 'first_checkin' && !['did','didMore'].includes(String(row.record.properties?.result))) continue;
      if (index > 0 && (!previous.has(row.userId) || timestampKey(row.record.ts) < timestampKey(String(previous.get(row.userId))))) continue;
      if (!current.has(row.userId)) current.set(row.userId, row.record.ts);
    }
    previous = current; groups.push(new Set(current.keys()));
  }
  const count = (/** @type {Set<string>} */ group) => group.size >= 50 ? group.size : null;
  return { channel: 'web', minimumContributors: 50,
    stages: Object.fromEntries(orderedStages.map((stage, index) => [stage, count(groups[index])])),
    steps: orderedStages.slice(1).map((stage, index) => ({ from: orderedStages[index], to: stage,
      rate: groups[index].size >= 50 && groups[index + 1].size >= 50 ? groups[index + 1].size / groups[index].size : null })),
    activation: attributedActivation(rows, startDay, endDay),
    definition: 'Separate self-selected, explicitly account-linked website + installer receipts, ordered under app analytics consent. 50 distinct accounts in numerator and denominator required. No automatic browser linkage, no anonymous denominator, no Store attribution; missing stages unknown.' };
}

/**
 * @param {{
 * container:()=>import('@azure/cosmos').Container,
 * authenticate:(request:import('@azure/functions').HttpRequest)=>Promise<{roles:unknown}>,
 * authenticateProof?:(request:import('@azure/functions').HttpRequest)=>Promise<{roles:unknown}>,
 * operationalEnabled?:()=>Promise<void>, clock?:()=>Date
 * }} dependencies
 */
export function createWebsiteHandlers({ container, authenticate, authenticateProof = authenticate,
  operationalEnabled = async () => {}, clock = () => new Date() }) {
  /** @type {Map<string,{expires:number,content:string}>} */
  const seen = new Map();
  let admissionMinute = -1, admissionCount = 0;
  function admit() {
    const minute = Math.floor(clock().getTime() / 60000);
    if (minute !== admissionMinute) { admissionMinute = minute; admissionCount = 0; }
    if (++admissionCount > 60) throw new ServiceError(429, 'Website observation admission cap reached.');
  }
  /** @param {boolean} synthetic */
  const partition = synthetic => synthetic ? '__website_synthetic' : '__website_counts';
  /** @param {WebBudget | null} old @param {string} userId */
  function document(old, userId) {
    return old ?? { id: 'budget', userId, type: 'website_budget', schemaVersion: 1, accepted: 0,
      minute: 0, minuteCount: 0, reads: 0, readDay: '', ttl: -1 };
  }
  /** @param {WebBudget} value @param {WebBudget | null} old @param {WebDay | undefined} daily @param {WebDay | null | undefined} oldDay */
  async function save(value, old, daily = undefined, oldDay = undefined) {
    if (old && !old._etag) throw new ServiceError(503, 'Website aggregate concurrency metadata unavailable.');
    if (oldDay && !oldDay._etag) throw new ServiceError(503, 'Website daily concurrency metadata unavailable.');
    /** @type {import('@azure/cosmos').OperationInput[]} */
    const operations = [
      old?._etag ? { operationType: 'Replace', id: 'budget', ifMatch: old._etag, resourceBody: value } :
        { operationType: 'Create', resourceBody: value },
    ];
    if (daily) operations.push(oldDay?._etag ?
      { operationType: 'Replace', id: daily.id, ifMatch: oldDay._etag, resourceBody: daily } :
      { operationType: 'Create', resourceBody: daily });
    try {
      const response = await container().items.batch(operations, value.userId);
      if (response.code === undefined) throw new ServiceError(503, 'Website aggregate transaction status unavailable.');
      if (response.code >= 400) throw Object.assign(Error('Website aggregate transaction rejected.'), { code: response.code });
    } catch (error) {
      if (typeof error === 'object' && error && 'code' in error && [409, 412, 424].includes(Number(error.code))) {
        throw new ServiceError(429, 'Concurrent website count update; do not retry automatically.');
      }
      throw error;
    }
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function ingest(request) {
    if (request.headers.get('dnt') === '1' || request.headers.get('sec-gpc') === '1') return { status: 204 };
    admit();
    if (/bot|crawler|spider/i.test(request.headers.get('user-agent') ?? '')) throw new ServiceError(429, 'Automated observations excluded.');
    if (!/^application\/json(?:;|$)/i.test(request.headers.get('content-type') ?? '')) throw new ServiceError(400, 'JSON required.');
    const declared = request.headers.get('content-length');
    if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > 2048)) throw new ServiceError(413, 'Website observation too large.');
    // Stream cap prevents allocating an unbounded chunked body before validation.
    let raw = '';
    if (request.body) {
      const reader = request.body.getReader(), decoder = new TextDecoder();
      let bytes = 0;
      try {
        while (true) {
          const result = await reader.read();
          if (result.done) break;
          bytes += result.value.byteLength;
          if (bytes > 2048) { await reader.cancel(); throw new ServiceError(413, 'Website observation too large.'); }
          raw += decoder.decode(result.value, { stream: true });
        }
        raw += decoder.decode();
      } finally { reader.releaseLock(); }
    } else raw = await request.text();
    if (Buffer.byteLength(raw) > 2048) throw new ServiceError(413, 'Website observation too large.');
    let parsed;
    try { parsed = JSON.parse(raw); } catch { throw new ServiceError(400, 'Invalid JSON.'); }
    const value = validateWebPayload(parsed);
    const now = clock().getTime(), key = `${value.synthetic}:${value.eventId}`;
    if (value.observedAt && (now - Date.parse(value.observedAt) >= 300000 || Date.parse(value.observedAt) - now > 60000)) {
      throw new ServiceError(400, 'Observation time is outside the five-minute retry window.');
    }
    for (const [id, saved] of seen) if (saved.expires <= now) seen.delete(id);
    const content = JSON.stringify([value.event, value.source, value.architecture, value.observedAt ?? null,
      value.attribution ? touchNames.map(touch => Object.keys(attributionFields).map(field =>
        value.attribution?.[/** @type {'firstTouch'|'lastTouch'} */ (touch)][/** @type {keyof typeof attributionFields} */ (field)])) : null]);
    const prior = seen.get(key);
    if (prior && prior.content !== content) throw new ServiceError(400, 'Observation retry ID reused for a different event.');
    if (prior) return { status: 204 };
    await operationalEnabled();
    const userId = partition(value.synthetic);
    const day = clock().toISOString().slice(0, 10), minute = Math.floor(now / 60000);
    const { resource } = await container().item('budget', userId).read();
    const parsedBudget = resource == null ? null : budgetSchema.safeParse(resource);
    if (parsedBudget && !parsedBudget.success) throw new ServiceError(503, 'Website budget is invalid; no count substituted.');
    const old = parsedBudget?.success ? parsedBudget.data : null;
    const doc = structuredClone(document(old, userId));
    const hash = (/** @type {string} */ text) => createHash('sha256').update(text).digest('hex');
    const retryKey = hash(key), retryContent = hash(content);
    const recent = (doc.recent ?? []).filter(row => row.expires > now);
    const retry = value.observedAt ? recent.find(row => row.key === retryKey) : undefined;
    if (retry && retry.content !== retryContent) throw new ServiceError(400, 'Observation retry ID reused for a different event.');
    if (retry) return { status: 204 };
    if (value.observedAt) {
      if (recent.length >= 180) throw new ServiceError(429, 'Website retry ledger cap reached.');
      doc.recent = [...recent, { key: retryKey, content: retryContent, expires: Date.parse(value.observedAt) + 300000 }];
    }
    const { resource: dayResource } = await container().item(day, userId).read();
    const parsedDay = dayResource == null ? null : daySchema.safeParse(dayResource);
    if (parsedDay && !parsedDay.success) throw new ServiceError(503, 'Website daily aggregate is invalid.');
    const oldDay = parsedDay?.success ? parsedDay.data : null;
    /** @type {WebDay} */
    const daily = structuredClone(oldDay ?? { id: day, day, userId, type: 'website_daily', schemaVersion: 1,
      counts: {}, accepted: 0, ttl: 1 });
    const sourceCount = Object.entries(daily.counts).filter(([key]) => key.split(':')[1] === value.source)
      .reduce((total, [, count]) => total + count, 0);
    if (doc.accepted >= (value.synthetic ? 100 : 10000) || daily.accepted >= (value.synthetic ? 20 : 400) ||
        sourceCount >= (value.synthetic ? 10 : 100) ||
        doc.minute === minute && doc.minuteCount >= 30) throw new ServiceError(429, 'Website daily/lifetime/minute cap reached.');
    const dimension = `${value.event}:${value.source}:${value.architecture}`;
    daily.counts[dimension] = (daily.counts[dimension] ?? 0) + 1; daily.accepted++;
    if (value.attribution) {
      daily.attributionCounts ??= {};
      for (const touch of ['firstTouch', 'lastTouch']) {
        for (const field of Object.keys(attributionFields)) {
          /** @type {string} */
          const label = value.attribution[/** @type {'firstTouch'|'lastTouch'} */ (touch)][/** @type {keyof typeof attributionFields} */ (field)];
          const dimension = `${touch}:${value.event}:${field}:${label}`;
          daily.attributionCounts[dimension] = (daily.attributionCounts[dimension] ?? 0) + 1;
        }
      }
    }
    doc.accepted++;
    doc.minuteCount = doc.minute === minute ? doc.minuteCount + 1 : 1; doc.minute = minute;
    daily.ttl = Math.max(1, Math.floor((Date.parse(addDays(day, 90)) - now) / 1000));
    await save(doc, old, daily, oldDay);
    if (seen.size >= 2048) seen.delete(String(seen.keys().next().value));
    seen.set(key, { expires: now + 300000, content });
    return { status: 202, jsonBody: { accepted: true, synthetic: value.synthetic } };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function metrics(request) {
    const actor = await authenticate(request);
    if (!isAdmin(actor.roles)) throw new ServiceError(403, 'Bloomstep.Admin required.');
    admit();
    const query = new URL(request.url).searchParams;
    if ([...query.keys()].some(key => !['days','synthetic'].includes(key)) || [...query.keys()].length !== new Set(query.keys()).size ||
        query.has('synthetic') && query.get('synthetic') !== 'true' || query.has('days') && !/^(?:[1-9]|[12]\d|30)$/.test(String(query.get('days')))) {
      throw new ServiceError(400, 'Invalid website metric window.');
    }
    const days = Number(query.get('days') ?? 7), synthetic = query.get('synthetic') === 'true';
    await operationalEnabled();
    const userId = partition(synthetic);
    const { resource } = await container().item('budget', userId).read();
    const parsedBudget = resource == null ? null : budgetSchema.safeParse(resource);
    if (parsedBudget && !parsedBudget.success) throw new ServiceError(503, 'Website budget is invalid; no count substituted.');
    const old = parsedBudget?.success ? parsedBudget.data : null;
    const doc = structuredClone(document(old, userId)), endDay = clock().toISOString().slice(0, 10);
    if (doc.recent) doc.recent = doc.recent.filter(row => row.expires > clock().getTime());
    if (doc.readDay !== endDay) { doc.reads = 0; doc.readDay = endDay; }
    if (doc.reads >= 30) throw new ServiceError(429, 'Website admin daily read cap reached.');
    doc.reads++; await save(doc, old);
    const startDay = addDays(endDay, 1 - days);
    const { resources: daily } = await container().items.query({
      query: 'SELECT TOP 31 c.id, c.userId, c.type, c.schemaVersion, c.day, c.counts, c.attributionCounts, c.accepted, c.ttl, c._etag FROM c WHERE c.type = "website_daily" AND c.day >= @start AND c.day <= @end',
      parameters: [{ name: '@start', value: startDay }, { name: '@end', value: endDay }],
    }, { partitionKey: userId }).fetchAll();
    if (daily.length > 30) throw new ServiceError(429, 'Website daily aggregate scan cap reached.');
    for (const row of daily) {
      if (!daySchema.safeParse(row).success) throw new ServiceError(503, 'Website report aggregate is invalid.');
    }
    const anonymous = summarizeWebCounts({ days: Object.fromEntries(daily.map(row => [row.day, row])) }, startDay, endDay);
    if (synthetic) return { jsonBody: { ...anonymous, synthetic: true, linked: null } };
    const { resources: accounts } = await container().items.query({
      query: 'SELECT TOP 1001 c.userId, c.deleted, c.deletedRecords FROM c WHERE c.type = "account"',
    }).fetchAll();
    if (accounts.length > 1000) throw new ServiceError(429, 'Website linked account scan cap reached.');
    const active = new Map(accounts.filter(row => !row.deleted).map(row => [row.userId, row]));
    const { resources: events } = await container().items.query({
      query: 'SELECT TOP 10001 c.userId, c.record FROM c WHERE c.type = "events" AND c.record.ts >= @start AND c.record.ts < @end',
      parameters: [{ name: '@start', value: startDay }, { name: '@end', value: addDays(endDay, 1) }],
    }).fetchAll();
    if (events.length > 10000) throw new ServiceError(429, 'Website linked event scan cap reached.');
    const rows = events.filter(row => {
      const account = active.get(row.userId);
      return account && !account.deletedRecords?.[`events:${row.record?.id}`] &&
        !account.deletedRecords?.[`habits:${row.record?.properties?.habitId ?? '__none'}`];
    });
    return { jsonBody: { ...anonymous, synthetic: false, linked: linkedWebFunnel(rows, startDay, endDay) } };
  }
  /** @param {import('@azure/functions').HttpRequest} request */
  async function proof(request) {
    const actor = await authenticateProof(request);
    if (!Array.isArray(actor.roles) || !actor.roles.includes('Bloomstep.AggregateWriter') || isAdmin(actor.roles)) {
      throw new ServiceError(403, 'Isolated aggregate worker proof role required.');
    }
    admit(); await operationalEnabled();
    const query = new URL(request.url).searchParams;
    if (query.size) throw new ServiceError(400, 'No synthetic proof parameters accepted.');
    const { resource: synthetic } = await container().item('budget', partition(true)).read();
    const { resource: real } = await container().item('budget', partition(false)).read();
    const numeric = (/** @type {unknown} */ value) => {
      if (value === undefined) return null;
      if (!Number.isInteger(value) || typeof value !== 'number' || value < 0 || value > 10000) {
        throw new ServiceError(503, 'Invalid website aggregate proof count.');
      }
      return value;
    };
    return { jsonBody: { schemaVersion: 1, syntheticAccepted: numeric(synthetic?.accepted), realAccepted: numeric(real?.accepted),
      definition: 'Lifetime accepted event counts only; synthetic and real partitions are isolated. No visitor identifiers or raw observations are stored.' } };
  }
  return { ingest, metrics, proof };
}
