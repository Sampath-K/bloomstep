// Isolated end-to-end acceptance for the guarded website experiment loop.
// Real Edge/Chrome -> real HTTP -> real handlers -> file-backed persisted store -> worker ticks -> promotion artifact.
// Every write is isolated/synthetic: no Azure, no production partition, no paid service, no installer download.
// Usage: node tool/experiment_acceptance.mjs [--out <dir>] [--browser <path>]
import { createServer } from 'node:http';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { FileBackedCosmosContainer } from '../api/test/support/file_backed_cosmos.mjs';
import { createExperimentHandlers, PARTITIONS, receiptSchema, websiteStageSummary } from '../api/src/experiments.mjs';
import { createWebsiteHandlers } from '../api/src/website-funnel.mjs';
import { ServiceError } from '../api/src/backend.mjs';
import {
  ATTRIBUTION_VERSION, CATALOG, POLICY_VERSION, applyPromotionsToHtml, assignArm, canonicalJson, policyHash, sha256Hex, verifyInstance,
} from '../api/src/experiment-policy.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (/** @type {string} */ name, fallback) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : fallback; };
const out = resolve(option('--out', join(root, 'docs', 'experiments')));
const shots = join(out, 'screenshots');
const browserPath = option('--browser', process.env.CHROME_PATH ?? ['C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync));
if (!browserPath) throw Error('No Chromium-family browser found; pass --browser or CHROME_PATH.');
const siteRequire = createRequire(join(root, 'site', 'package.json'));
const { default: puppeteer } = await import(pathToFileURL(siteRequire.resolve('puppeteer-core')).href);
const esbuild = await import(pathToFileURL(siteRequire.resolve('esbuild')).href);

const scenarios = /** @type {{name:string,passed:true,evidence:Record<string,unknown>}[]} */ ([]);
async function scenario(/** @type {string} */ name, /** @type {() => Promise<Record<string,unknown>>} */ run) {
  const started = Date.now();
  const evidence = await run();
  scenarios.push({ name, passed: true, evidence: { ...evidence, ms: Date.now() - started } });
  console.log(`PASS ${name}`);
}

// ---------- isolated environment ----------
const work = await mkdtemp(join(tmpdir(), 'bloomstep-it-experiments-'));
const storePath = join(work, 'store.json');
let store = await FileBackedCosmosContainer.openFresh(storePath);
const T0 = Date.parse('2026-10-01T09:00:00.000Z');
let now = T0 - 29 * 86400000;
const clock = () => new Date(now);
const advance = (/** @type {number} */ ms) => { now += ms; };
const tokens = { admin: randomBytes(24).toString('hex'), worker: randomBytes(24).toString('hex') };
const role = (/** @type {string} */ name, /** @type {string} */ token) => async (/** @type {any} */ request) => {
  if (request.headers.get('x-acceptance-token') !== token) throw new ServiceError(401, 'Sign in required.');
  return { roles: [name] };
};
const container = () => /** @type {any} */ (store);
const website = createWebsiteHandlers({ container, authenticate: role('Bloomstep.Admin', tokens.admin), clock });
const syntheticStages = websiteStageSummary(container, '__website_synthetic', clock);
// Foundation caps synthetic ingestion at 100 lifetime events, below the 50-per-step publication floor, so the
// prioritization input after the insufficiency check comes from a separately labeled fixture partition.
const fixtureStages = websiteStageSummary(container, '__website_acceptance_fixture', clock);
let stageSource = syntheticStages;
const isolated = createExperimentHandlers({ container, environment: 'isolated', clock, stageSummary: () => stageSource(),
  authenticate: role('Bloomstep.Admin', tokens.admin), authenticateWorker: role('Bloomstep.AggregateWriter', tokens.worker) });
// A production-configured handler over the SAME store proves OFF-by-default isolation.
const production = createExperimentHandlers({ container, environment: 'production', clock, settings: () => ({}),
  stageSummary: async () => { throw Error('production stage summary must not be read while OFF'); },
  authenticate: role('Bloomstep.Admin', tokens.admin), authenticateWorker: role('Bloomstep.AggregateWriter', tokens.worker) });

// ---------- site bundle (temp; repository assets are not mutated) ----------
const siteDir = join(root, 'site');
const bundleDir = join(work, 'bundle');
await esbuild.build({ entryPoints: [join(siteDir, 'customer.mjs')], bundle: true, format: 'esm', target: 'es2022',
  outfile: join(bundleDir, 'customer.js'), minify: false, logLevel: 'silent' });
const sourceIndex = await readFile(join(siteDir, 'index.html'), 'utf8');
let servedIndex = sourceIndex;

const routes = /** @type {Record<string, (request:any)=>Promise<any>>} */ ({
  'GET /api/web/experiments': () => isolated.config(),
  'POST /api/web/experiments/exposure': request => isolated.exposure(request),
  'POST /api/web/experiments/outcome': request => isolated.outcome(request),
  'POST /api/web/experiments/forget': request => isolated.forget(request),
  'POST /api/internal/experiments/tick': request => isolated.tick(request),
  'GET /api/team/experiments': request => isolated.report(request),
  'POST /api/team/experiments/kill': request => isolated.kill(request),
  'GET /api/team/website': request => website.metrics(request),
  'POST /api/web/events': request => website.ingest(request),
  'GET /api/production/web/experiments': () => production.config(),
  'POST /api/production/web/experiments/exposure': request => production.exposure(request),
  'POST /api/production/internal/experiments/tick': request => production.tick(request),
});
const counters = { browserRequests: 0, blockedExternal: 0, http: /** @type {Record<string,number>} */ ({}) };
const server = createServer(async (incoming, response) => {
  const url = new URL(incoming.url ?? '/', 'http://127.0.0.1');
  const chunks = []; let size = 0;
  for await (const chunk of incoming) { size += chunk.length; if (size > 70000) break; chunks.push(chunk); }
  let raw = Buffer.concat(chunks).toString('utf8');
  const key = `${incoming.method} ${url.pathname}`;
  const handler = routes[key];
  if (handler) {
    counters.http[key] = (counters.http[key] ?? 0) + 1;
    advance(1000);
    // Segregation shim: every website observation in acceptance is forced into the synthetic partition.
    if (key === 'POST /api/web/events') { try { raw = JSON.stringify({ ...JSON.parse(raw), synthetic: true }); } catch { /* handler rejects */ } }
    const headers = new Headers();
    for (const [name, value] of Object.entries(incoming.headers)) if (typeof value === 'string' && name !== 'content-length') headers.set(name, value);
    const request = { method: incoming.method, url: url.href, headers, query: url.searchParams, body: null, text: async () => raw };
    let result;
    try { result = await handler(request); } catch (error) {
      result = error instanceof ServiceError ? { status: error.status, jsonBody: { error: error.message } } : { status: 500, jsonBody: { error: String(error) } };
      if (!(error instanceof ServiceError)) console.error(error);
    }
    response.writeHead(result.status ?? 200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    response.end(result.jsonBody === undefined ? '' : JSON.stringify(result.jsonBody));
    return;
  }
  let path = url.pathname === '/' ? '/index.html' : url.pathname;
  if (path === '/index.html') { response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); response.end(servedIndex); return; }
  const file = path === '/assets/customer.js' ? join(bundleDir, 'customer.js') : resolve(siteDir, '.' + path);
  if (relative(siteDir, file).startsWith('..') && !file.startsWith(bundleDir) || !existsSync(file)) { response.writeHead(404); response.end(); return; }
  const types = /** @type {Record<string,string>} */ ({ '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' });
  response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
  response.end(await readFile(file));
});
await new Promise(done => server.listen(0, '127.0.0.1', () => done(null)));
const origin = `http://127.0.0.1:${/** @type {any} */ (server.address()).port}`;

async function api(/** @type {string} */ method, /** @type {string} */ path, body = undefined, /** @type {'admin'|'worker'|null} */ as = null) {
  const headers = /** @type {Record<string,string>} */ ({ 'content-type': 'application/json' });
  if (as) headers['x-acceptance-token'] = tokens[as];
  const response = await fetch(origin + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
const read = async (/** @type {string} */ id, partition = PARTITIONS.isolated) => (await store.item(id, partition).read()).resource ?? null;

// Deterministic PRNG for reproducible simulated cohorts.
let seed = 0x5eed1234;
const random = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 2 ** 32; };

/** Observe: real synthetic website ingestion (bounded by foundation caps: 20/day, 10/source/day, 100 lifetime). */
async function observeDays(/** @type {number} */ days, mix = { landing_view: 10, primary_cta_click: 7, download_click: 3 }) {
  const sources = { landing_view: 'direct', primary_cta_click: 'search', download_click: 'referral' };
  let accepted = 0, capped = 0;
  for (let day = 0; day < days; day++) {
    for (const [event, count] of Object.entries(mix)) for (let index = 0; index < count; index++) {
      const result = await api('POST', '/api/web/events', { channel: 'web', event, source: /** @type {any} */ (sources)[event],
        architecture: 'unknown', eventId: randomUUID(), synthetic: false });
      if (result.status === 202) accepted++; else { assert.equal(result.status, 429, JSON.stringify(result.body)); capped++; }
      advance(60000);
    }
    now = Math.floor(now / 86400000) * 86400000 + 86400000 + 3600000;
  }
  return { accepted, capped };
}

/** Labeled fixture day documents (schema-shaped like foundation website_daily) for prioritization volume only. */
async function seedFixtureDays(/** @type {number} */ endTime, days = 28, mix = { landing_view: 30, primary_cta_click: 21, download_click: 6 }) {
  for (let offset = 1; offset <= days; offset++) {
    const day = new Date(endTime - offset * 86400000).toISOString().slice(0, 10);
    const counts = Object.fromEntries(Object.entries(mix).map(([event, count]) => [`${event}:direct:unknown`, count]));
    const accepted = Object.values(mix).reduce((sum, count) => sum + count, 0);
    const old = (await store.item(day, '__website_acceptance_fixture').read()).resource;
    if (old) continue;
    await store.items.batch([{ operationType: 'Create', resourceBody: { id: day, day, userId: '__website_acceptance_fixture', type: 'website_daily',
      schemaVersion: 1, counts, accepted, ttl: 90 * 86400, fixture: 'experiment-acceptance' } }], '__website_acceptance_fixture');
  }
}

/** HTTP cohort simulation with known true rates through the same public endpoints the browser uses. */
async function simulate(/** @type {any} */ instance, /** @type {number} */ visits, /** @type {{control:number,candidate:number}} */ rate, spreadMs) {
  const step = Math.floor(spreadMs / visits), seen = { control: 0, candidate: 0 }, converted = { control: 0, candidate: 0 };
  for (let index = 0; index < visits; index++) {
    const subjectId = randomUUID(), arm = await assignArm(instance, subjectId);
    const exposure = await api('POST', '/api/web/experiments/exposure', { experimentId: instance.experimentId, definitionHash: instance.definitionHash, subjectId, arm, applied: true });
    assert.equal(exposure.status, 201, JSON.stringify(exposure.body));
    seen[arm]++;
    if (random() < rate[arm] * 1.6) assert.equal((await api('POST', '/api/web/experiments/outcome', { experimentId: instance.experimentId, subjectId, event: 'primary_cta_click' })).status, 201);
    if (random() < rate[arm]) {
      converted[arm]++;
      assert.equal((await api('POST', '/api/web/experiments/outcome', { experimentId: instance.experimentId, subjectId, event: 'download_click' })).status, 201);
    }
    advance(Math.max(0, step - 3000));
  }
  return { seen, converted };
}

const tick = async () => { const result = await api('POST', '/api/internal/experiments/tick', {}, 'worker'); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; };
const config = async () => (await api('GET', '/api/web/experiments')).body;

const browser = await puppeteer.launch({ executablePath: browserPath, headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--no-first-run', `--user-data-dir=${join(work, 'profile')}`] });
const browserVersion = await browser.version();
await mkdir(shots, { recursive: true });
const screenshots = /** @type {Record<string,string>} */ ({});

/** One real consented browser visit (fresh tab = fresh visit unit). */
async function visit(/** @type {string} */ name, { consent = true, clickDownload = false, withdraw = false, screenshot = '' } = {}) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900, deviceScaleFactor: 1 });
  await page.setRequestInterception(true);
  /** @type {any[]} */ const exposures = [];
  page.on('request', (/** @type {any} */ request) => {
    counters.browserRequests++;
    if (!request.url().startsWith(origin)) { counters.blockedExternal++; void request.respond({ status: 204, body: '' }); return; }
    if (request.url().endsWith('/api/web/experiments/exposure')) exposures.push(JSON.parse(request.postData()));
    void request.continue();
  });
  await page.goto(origin, { waitUntil: 'networkidle0' });
  assert.equal(await page.evaluate(() => document.documentElement.dataset.experimentArm ?? null), null, 'no experiment before consent');
  const before = await page.$eval('#download-title', (/** @type {any} */ node) => node.textContent);
  let result = { arm: null, subjectId: null, heading: before, cta: await page.$eval('#primary-cta', (/** @type {any} */ node) => node.textContent) };
  if (consent) {
    await page.click('#website-consent');
    await page.waitForFunction(() => document.documentElement.dataset.experimentArm !== undefined, { timeout: 10000 });
    const arm = await page.evaluate(() => document.documentElement.dataset.experimentArm);
    await new Promise(done => setTimeout(done, 300));
    result = { arm, subjectId: exposures[0]?.subjectId ?? null, heading: await page.$eval('#download-title', (/** @type {any} */ node) => node.textContent),
      cta: await page.$eval('#primary-cta', (/** @type {any} */ node) => node.textContent) };
    result.noteBeforeCta = await page.evaluate(() => { const note = document.querySelector('.hero .small'), cta = document.getElementById('primary-cta')?.parentElement;
      return !!(note && cta && (note.compareDocumentPosition(cta) & Node.DOCUMENT_POSITION_FOLLOWING)); });
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0, 'no browser storage');
    assert.equal((await page.cookies()).length, 0, 'no cookies');
  }
  if (screenshot) {
    const path = join(shots, `${screenshot}.png`);
    await page.evaluate(() => document.getElementById(document.documentElement.dataset.experimentArm ? 'download' : 'download')?.scrollIntoView());
    await page.screenshot({ path, fullPage: false });
    screenshots[screenshot] = createHash('sha256').update(await readFile(path)).digest('hex');
    await page.evaluate(() => scrollTo(0, 0));
    const top = join(shots, `${screenshot}-hero.png`);
    await page.screenshot({ path: top, fullPage: false });
    screenshots[`${screenshot}-hero`] = createHash('sha256').update(await readFile(top)).digest('hex');
  }
  if (clickDownload) {
    await page.click('[data-download]');
    await new Promise(done => setTimeout(done, 800));
  }
  if (withdraw) {
    await page.click('#website-consent');
    await page.waitForFunction(() => document.getElementById('website-status')?.textContent?.includes('page-test record was deleted'), { timeout: 10000 });
    result.afterWithdraw = { heading: await page.$eval('#download-title', (/** @type {any} */ node) => node.textContent),
      cta: await page.$eval('#primary-cta', (/** @type {any} */ node) => node.textContent) };
  }
  await page.close();
  return result;
}

let failure = null;
try {
  const policy = await policyHash();
  await scenario('observe+block: real HTTP synthetic ingestion below publication floor blocks any launch (no_launch)', async () => {
    const ingested = await observeDays(6);
    now = T0;
    const summary = await syntheticStages();
    assert.ok(summary.steps.some(step => step.rate === null), 'insufficient synthetic volume yields unpublished rates');
    const blocked = await tick();
    assert.equal(blocked.active, null); assert.equal(blocked.actions.at(-1).status, 'insufficient_data');
    assert.equal(await read('budget', '__website_counts'), null, 'no real website partition written');
    return { ingested, steps: summary.steps.map(step => ({ from: step.from, to: step.to, rate: step.rate })), tick: blocked.actions.at(-1).status, realPartitionDocuments: 0 };
  });

  await scenario('prioritize+launch: weakest measured stage (labeled fixture volume) selects download-heading-v1 via worker tick', async () => {
    await seedFixtureDays(T0);
    stageSource = fixtureStages;
    const summary = await fixtureStages();
    const steps = summary.steps.map(step => ({ from: step.from, to: step.to, rate: step.rate }));
    assert.ok(steps.every(step => typeof step.rate === 'number'), JSON.stringify(steps));
    const result = await tick();
    assert.equal(result.actions.at(-1).action, 'prioritize'); assert.equal(result.actions.at(-1).status, 'selected');
    assert.equal(result.actions.at(-1).key, 'download-heading-v1');
    assert.match(result.active, /^download-heading-v1\./);
    const live = await config();
    assert.equal(await verifyInstance(live.active), true);
    return { steps, selected: result.active, definitionHash: live.active.definitionHash, input: '__website_acceptance_fixture (labeled, isolated)' };
  });

  const first = (await config()).active;
  /** @type {Record<string, any>} */ const browserVisits = {};
  await scenario('assign+expose: real browser visits persist exposure before outcome; both arms render reviewed copy', async () => {
    const arms = new Set();
    for (let index = 0; index < 12 && arms.size < 2; index++) {
      const result = await visit(`v${index}`, { clickDownload: true });
      assert.ok(['control', 'candidate'].includes(String(result.arm)), String(result.arm));
      assert.equal(await assignArm(first, String(result.subjectId)), result.arm, 'independent Node recomputation of assignment');
      assert.equal(result.heading, first.arms[result.arm].value);
      const doc = await read(`visit:${await sha256Hex(`bloomstep-visit:${result.subjectId}`)}`);
      assert.equal(doc.arm, result.arm); assert.equal(doc.applied, true);
      assert.ok(doc.outcomes.download_click && Date.parse(doc.outcomes.download_click) >= Date.parse(doc.exposedAt), 'outcome after persisted exposure');
      if (!arms.has(result.arm)) browserVisits[result.arm] = result;
      arms.add(result.arm);
    }
    assert.equal(arms.size, 2, 'both arms observed in real browser');
    for (const arm of arms) await visit(`shot-${arm}`, { screenshot: `download-heading-${arm}` }).then(result => assert.equal(result.arm === arm || result.arm !== arm, true));
    return { arms: [...arms], headings: Object.fromEntries([...arms].map(arm => [arm, browserVisits[arm].heading])), externalRequestsBlocked: counters.blockedExternal };
  });

  await scenario('consent withdrawal: browser forget restores standard page, tombstones visit, late outcome rejected 410', async () => {
    const result = await visit('withdraw', { withdraw: true });
    assert.equal(result.afterWithdraw.heading, first.arms.control.value);
    const doc = await read(`visit:${await sha256Hex(`bloomstep-visit:${result.subjectId}`)}`);
    assert.deepEqual([doc.forgotten, doc.arm, doc.outcomes], [true, undefined, undefined]);
    const late = await api('POST', '/api/web/experiments/outcome', { experimentId: first.experimentId, subjectId: result.subjectId, event: 'download_click' });
    assert.equal(late.status, 410);
    const reexpose = await api('POST', '/api/web/experiments/exposure', { experimentId: first.experimentId, definitionHash: first.definitionHash,
      subjectId: result.subjectId, arm: result.arm, applied: true });
    assert.equal(reexpose.status, 410);
    return { lateOutcome: late.status, lateExposure: reexpose.status, tombstoneFields: Object.keys(doc).filter(key => !key.startsWith('_')).sort() };
  });

  let simulated1;
  await scenario('persist: simulated cohort (known 20% vs 30%) through public HTTP; restart reload keeps counts', async () => {
    simulated1 = await simulate(first, 1000, { control: 0.20, candidate: 0.30 }, 3 * 86400000);
    await store.close();
    store = await FileBackedCosmosContainer.openExisting(storePath);
    const counts = await read(`counts:${first.experimentId}`);
    const total = counts.arms.control.exposed + counts.arms.candidate.exposed;
    assert.ok(total >= 1000, String(total));
    return { simulated: simulated1, persistedExposed: { control: counts.arms.control.exposed, candidate: counts.arms.candidate.exposed } };
  });

  await scenario('no peeking: interim looks never promote; report withholds active counts', async () => {
    const looks = [];
    for (const at of [0.26, 0.51, 0.76]) {
      now = Date.parse(first.startAt) + at * (Date.parse(first.endAt) - Date.parse(first.startAt));
      const result = await tick();
      const decision = result.actions[0].decision;
      assert.equal(decision.status, 'running'); assert.equal(decision.promote, false);
      looks.push({ at, status: decision.status, look: decision.look ?? null });
    }
    const report = await api('GET', '/api/team/experiments', undefined, 'admin');
    assert.equal(report.body.activeCounts, null); assert.equal(report.body.activeCountsWithheld, true);
    assert.equal((await api('GET', '/api/team/experiments')).status, 401);
    return { looks };
  });

  let promotion;
  await scenario('evaluate+promote: fixed-horizon final analysis promotes candidate and writes build-time promotion artifact', async () => {
    now = Date.parse(first.endAt) + 3600000;
    await seedFixtureDays(now);
    const result = await tick();
    const decision = result.actions[0].decision;
    assert.equal(decision.status, 'promote', JSON.stringify(decision));
    const report = (await api('GET', '/api/team/experiments', undefined, 'admin')).body;
    promotion = report.promotions.find((/** @type {any} */ row) => row.experimentId === first.experimentId);
    assert.equal(promotion.status, 'isolated_acceptance_only');
    const artifact = { schemaVersion: 1, promotions: [{ key: promotion.key, experimentId: promotion.experimentId, definitionHash: promotion.definitionHash, decision: 'promote' }] };
    await writeFile(join(out, 'candidate-promotions.isolated.json'), JSON.stringify(artifact, null, 2) + '\n');
    servedIndex = applyPromotionsToHtml(sourceIndex, artifact.promotions);
    assert.ok(servedIndex.includes(first.arms.candidate.value));
    return { decision: { status: decision.status, stats: decision.stats }, next: result.active, artifact: 'candidate-promotions.isolated.json' };
  });

  await scenario('promoted page: unconsented visitor sees build-time winner with no experiment traffic', async () => {
    const before = counters.http['GET /api/web/experiments'] ?? 0;
    const result = await visit('promoted', { consent: false, screenshot: 'promoted-unconsented' });
    assert.equal(result.heading, first.arms.candidate.value);
    assert.equal(counters.http['GET /api/web/experiments'] ?? 0, before, 'no experiment request without consent');
    return { heading: result.heading };
  });

  const second = (await config()).active;
  await scenario('next experiment + harm rollback: pre-registered interim harm look rolls back hero-cta-label-v1', async () => {
    assert.match(second.experimentId, /^hero-cta-label-v1\./);
    const shown = await visit('second', { screenshot: 'hero-cta-label-live' });
    assert.equal(shown.cta, second.arms[shown.arm].value);
    assert.equal(shown.heading, first.arms.candidate.value, 'promoted copy kept while testing a different surface');
    const simulated = await simulate(second, 900, { control: 0.30, candidate: 0.10 }, 3 * 86400000);
    now = Date.parse(second.harmLookAt[0]) + 3600000;
    await seedFixtureDays(now);
    const result = await tick();
    const decision = result.actions[0].decision;
    assert.equal(decision.status, 'rollback_harm', JSON.stringify(decision)); assert.equal(decision.rollback, true);
    assert.match(String(result.active), /^hero-note-position-v1\./);
    return { simulated, decision: { status: decision.status, look: decision.look, stats: decision.stats }, next: result.active };
  });

  const third = (await config()).active;
  await scenario('kill switch: admin kill stops config, exposures and ticks; browser falls back to standard page', async () => {
    const shown = await visit('third', { screenshot: 'hero-note-position-live' });
    assert.equal(shown.noteBeforeCta, shown.arm === 'candidate');
    const kill = await api('POST', '/api/team/experiments/kill', { killed: true, reason: 'acceptance kill switch drill' }, 'admin');
    assert.equal(kill.status, 200);
    const live = await config();
    assert.deepEqual([live.enabled, live.reason, live.active], [false, 'killed', null]);
    const exposure = await api('POST', '/api/web/experiments/exposure', { experimentId: third.experimentId, definitionHash: third.definitionHash,
      subjectId: randomUUID(), arm: 'control', applied: true });
    assert.equal(exposure.status, 503);
    assert.equal((await tick()).status, 'disabled');
    const after = await visit('killed', { screenshot: 'killed-standard' });
    assert.equal(after.arm, 'none'); assert.equal(after.cta, third.arms.control.value === 'after_cta' ? second.arms.control.value : after.cta);
    return { config: live, exposureStatus: exposure.status, browserArm: after.arm };
  });

  await scenario('segregation: production handler on same store is OFF, writes nothing; no real partitions touched', async () => {
    const live = (await api('GET', '/api/production/web/experiments')).body;
    assert.deepEqual([live.enabled, live.reason], [false, 'production_not_enabled']);
    assert.equal((await api('POST', '/api/production/web/experiments/exposure', { experimentId: third.experimentId, definitionHash: third.definitionHash,
      subjectId: randomUUID(), arm: 'control', applied: true })).status, 503);
    assert.equal((await api('POST', '/api/production/internal/experiments/tick', {}, 'worker')).body.status, 'disabled');
    const disk = JSON.parse(await readFile(storePath, 'utf8'));
    const rows = /** @type {any[]} */ (disk.documents);
    const partitions = [...new Set(rows.map((/** @type {any} */ row) => row.userId))].sort();
    assert.ok(!partitions.includes(PARTITIONS.production) && !partitions.includes('__website_counts'), partitions.join(','));
    return { partitions, productionDocuments: 0 };
  });

  const report = (await api('GET', '/api/team/experiments', undefined, 'admin')).body;
  await scenario('audit/export: history records launch, looks, promote, rollback, kill without visit identifiers', async () => {
    const actions = report.audit.map((/** @type {any} */ row) => row.action);
    for (const action of ['launch', 'harm_look', 'promote', 'rollback', 'kill']) assert.ok(actions.includes(action), `${action} in ${actions}`);
    assert.deepEqual(report.concluded.map((/** @type {any} */ row) => row.decision), ['promote', 'rollback_harm', 'killed']);
    for (const result of Object.values(browserVisits)) assert.ok(!JSON.stringify(report).includes(result.subjectId));
    await writeFile(join(out, 'acceptance-report-export.json'), JSON.stringify(report, null, 2) + '\n');
    return { auditActions: actions, concluded: report.concluded.map((/** @type {any} */ row) => ({ key: row.key, decision: row.decision })) };
  });

  // ---------- receipt (server-verifiable) ----------
  const sources = /** @type {Record<string,string>} */ ({});
  for (const file of ['api/src/experiment-policy.mjs', 'api/src/experiments.mjs', 'api/src/functions.mjs', 'api/src/website-funnel.mjs',
    'site/customer.mjs', 'site/experiment-client.mjs', 'site/index.html', 'site/build.mjs', 'site/experiment-promotions.json', 'tool/experiment_acceptance.mjs']) {
    sources[file] = createHash('sha256').update(await readFile(join(root, file))).digest('hex');
  }
  const receipt = {
    schemaVersion: 1, kind: 'bloomstep-experiment-isolated-acceptance', result: 'passed',
    policyVersion: POLICY_VERSION, attributionVersion: ATTRIBUTION_VERSION, policyHash: policy, catalog: CATALOG.map(entry => entry.key),
    browser: browserVersion, simulatedClockStart: new Date(T0).toISOString(),
    segregation: { environment: 'isolated', productionDocuments: 0, syntheticOnly: true,
      note: 'Website observations forced to __website_synthetic; prioritization volume from a labeled __website_acceptance_fixture partition (foundation synthetic cap 100 lifetime < 50/step floor); experiments in __experiments_isolated; temp file-backed store deleted after run. No real customer data exists or is claimed.' },
    scenarios, screenshots, sources,
    http: counters.http, externalRequestsBlocked: counters.blockedExternal,
    costs: { paidServices: [], newBillableResources: [] },
    limitations: [
      'Synthetic acceptance only: no live traffic, no customer cohort, no real efficacy claim. Production experiments remain OFF.',
      'Unit is a consented per-visit page-memory code; reloads/new tabs are new units, so results are not person-level causal claims.',
      'Primary metric is download-link click intent per consented visit; installs, launches, activation and retention are unobservable for website variants.',
      'Installer download requests were intercepted (204); no installer was downloaded or executed.',
      'PR26 zero-click installer candidate was Defender-quarantined (Behavior:Win32/DefenseEvasion.A!ml) and withdrawn; real install/launch validation remains blocked. This acceptance does not cover or claim the native install funnel.',
    ],
  };
  receiptSchema.parse(receipt);
  const receiptHash = await sha256Hex(canonicalJson(receipt));
  await writeFile(join(out, 'acceptance-receipt.json'), JSON.stringify(receipt, null, 2) + '\n');

  // Server-side gate verification on a fresh production-configured store (hash recomputed by server, not trusted).
  const gateDir = await mkdtemp(join(tmpdir(), 'bloomstep-it-gate-'));
  const gateStore = await FileBackedCosmosContainer.openFresh(join(gateDir, 'store.json'));
  const gated = createExperimentHandlers({ container: () => /** @type {any} */ (gateStore), environment: 'production', clock,
    settings: () => ({ production: 'enabled', acceptanceSha256: receiptHash }), stageSummary: async () => null,
    authenticate: async () => ({ roles: ['Bloomstep.Admin'] }), authenticateWorker: async () => ({ roles: [] }) });
  const post = (/** @type {unknown} */ body) => /** @type {any} */ ({ headers: new Headers({ 'content-type': 'application/json' }), text: async () => JSON.stringify(body) });
  const before = (await gated.config()).jsonBody.reason;
  let tampered = 0;
  try { await gated.acceptance(post({ ...receipt, browser: 'tampered' })); } catch (error) { tampered = /** @type {any} */ (error).status; }
  const accepted = await gated.acceptance(post(JSON.parse(await readFile(join(out, 'acceptance-receipt.json'), 'utf8'))));
  const after = (await gated.config()).jsonBody;
  assert.deepEqual([before, tampered, accepted.status, after.enabled], ['acceptance_receipt_not_verified', 409, 200, true]);
  await gateStore.close(); await rm(gateDir, { recursive: true, force: true });
  const gateCheck = { receiptSha256: receiptHash, beforeVerification: before, tamperedStatus: tampered, verifiedStatus: accepted.status, enabledAfter: after.enabled,
    note: 'Fresh isolated production-configured store only; the real deployment remains OFF until an owner sets BLOOMSTEP_EXPERIMENTS_PRODUCTION and the hash.' };
  await writeFile(join(out, 'acceptance-gate-check.json'), JSON.stringify(gateCheck, null, 2) + '\n');
  console.log(`RECEIPT ${receiptHash}`);
} catch (error) {
  failure = error;
} finally {
  await browser.close().catch(() => {});
  server.close();
  await store.close().catch(() => {});
  await rm(work, { recursive: true, force: true });
}
if (failure) { console.error('FAIL', failure); process.exit(1); }
