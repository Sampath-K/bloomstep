import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { FileBackedCosmosContainer } from './support/file_backed_cosmos.mjs';
import { createExperimentHandlers, PARTITIONS } from '../src/experiments.mjs';
import {
  CATALOG, DESIGN, applyPromotionsToHtml, assignArm, canonicalJson, eligibility, evaluate, freezeInstance, lintEntry,
  policyHash, sampleRatio, selectNext, sha256Hex, twoProportion, verifyInstance,
} from '../src/experiment-policy.mjs';
import { ServiceError } from '../src/backend.mjs';

const start = '2026-10-01T00:00:00.000Z';
const at = (/** @type {number} */ days) => new Date(Date.parse(start) + days * 86400000);
const arm = (exposed, download, errors = 0, cta = 0) => ({ exposed, converted: { download_click: download, primary_cta_click: cta }, errors });
const summary = (a, b) => ({ steps: [{ from: 'landing_view', to: 'primary_cta_click', rate: a }, { from: 'primary_cta_click', to: 'download_click', rate: b }] });

test('catalog is finite, truthful-lint clean, and limited to allowed copy/layout surfaces', () => {
  assert.equal(CATALOG.length, 3);
  for (const entry of CATALOG) assert.deepEqual(lintEntry(entry), [], entry.key);
  const bad = { ...CATALOG[0], candidate: { id: 'x', value: 'Scientifically proven to build habits!' } };
  assert.ok(lintEntry(/** @type {any} */ (bad)).some(problem => problem.includes('claim')));
  assert.ok(lintEntry(/** @type {any} */ ({ ...CATALOG[0], surface: 'consent_label' }))[0].includes('surface not allowed'));
  for (const claim of ['Sign in to win', 'No SmartScreen warning', 'Safe and signed download', '50% more habits', 'Hurry, last chance'])
    assert.ok(lintEntry(/** @type {any} */ ({ ...CATALOG[0], candidate: { id: 'x', value: claim } })).length, claim);
});

test('frozen instances are immutable, hash-bound to the bundled catalog and policy', async () => {
  const instance = await freezeInstance(CATALOG[0], { startAt: start, environment: 'isolated' });
  assert.equal(instance.endAt, at(14).toISOString());
  assert.equal(instance.harmLookAt.length, 3);
  assert.equal(await verifyInstance(instance), true);
  assert.equal(await verifyInstance({ ...instance, endAt: at(30).toISOString() }), false, 'horizon tamper');
  assert.equal(await verifyInstance({ ...instance, arms: { ...instance.arms, candidate: { id: 'x', value: 'Injected copy' } } }), false);
  const rehashed = { ...instance, design: { ...instance.design, alpha: 0.2 } };
  const { definitionHash, ...body } = rehashed;
  assert.equal(await verifyInstance({ ...body, definitionHash: await sha256Hex(canonicalJson(body)) }), false, 'catalog design binding');
  await assert.rejects(freezeInstance(CATALOG[0], { startAt: '2026-10-01', environment: 'isolated' }));
  assert.match(await policyHash(), /^[a-f0-9]{64}$/);
});

test('assignment is deterministic, roughly balanced, and eligibility blocks non-consented or privacy-signal visits', async () => {
  const instance = await freezeInstance(CATALOG[0], { startAt: start, environment: 'isolated' });
  const id = randomUUID();
  assert.equal(await assignArm(instance, id), await assignArm(instance, id));
  let candidate = 0;
  for (let index = 0; index < 2000; index++) if (await assignArm(instance, randomUUID()) === 'candidate') candidate++;
  assert.ok(candidate > 900 && candidate < 1100, String(candidate));
  assert.deepEqual(eligibility({ consent: false }), { eligible: false, reason: 'no_consent' });
  assert.equal(eligibility({ consent: true, dnt: '1' }).reason, 'privacy_signal');
  assert.equal(eligibility({ consent: true, gpc: true }).reason, 'privacy_signal');
  assert.equal(eligibility({ consent: true, killed: true }).reason, 'killed');
  assert.equal(eligibility({ consent: true }).eligible, true);
});

test('statistics: small or zero cells are insufficient, SRM and z-test behave', () => {
  assert.equal(twoProportion(0, 500, 0, 500, 10), null);
  assert.equal(twoProportion(3, 30, 9, 30, 10), null);
  const result = twoProportion(100, 500, 150, 500, 10);
  assert.ok(result && result.z > 3 && result.pTwoSided < 0.001 && result.ci95[0] > 0);
  assert.throws(() => twoProportion(6, 5, 1, 5, 1));
  assert.equal(sampleRatio({ control: arm(40, 0), candidate: arm(40, 0) }, DESIGN.allocation), null);
  assert.ok(/** @type {any} */ (sampleRatio({ control: arm(600, 0), candidate: arm(400, 0) }, DESIGN.allocation)).p < 0.001);
});

test('evaluation matrix: no peeking, harm-only interim looks, fixed-horizon promotion, blocking states', async () => {
  const instance = await freezeInstance(CATALOG[0], { startAt: start, environment: 'isolated' });
  const strong = { control: arm(500, 100), candidate: arm(500, 170) };
  assert.equal((await evaluate(instance, strong, at(1))).status, 'running');
  const look = await evaluate(instance, strong, at(4));
  assert.equal(look.status, 'running'); assert.equal(look.look, 0); assert.equal(look.promote, false, 'strong interim effect never promotes');
  assert.equal((await evaluate(instance, strong, at(4), [0])).reason.includes('No pre-registered look'), true, 'each look used once');
  const harm = await evaluate(instance, { control: arm(500, 150), candidate: arm(500, 60) }, at(4));
  assert.equal(harm.status, 'rollback_harm'); assert.equal(harm.rollback, true);
  const mild = await evaluate(instance, { control: arm(500, 150), candidate: arm(500, 125) }, at(4));
  assert.equal(mild.status, 'running', 'mild harm below Bonferroni look boundary continues');
  assert.equal((await evaluate(instance, { control: arm(100, 1, 5), candidate: arm(100, 1) }, at(1))).status, 'rollback_variant_errors');
  assert.equal((await evaluate(instance, { control: arm(700, 100), candidate: arm(400, 100) }, at(15))).status, 'invalid_sample_ratio');
  assert.equal((await evaluate(instance, { control: arm(0, 0), candidate: arm(0, 0) }, at(15))).status, 'no_data');
  assert.equal((await evaluate(instance, { control: arm(300, 60), candidate: arm(300, 90) }, at(15))).status, 'insufficient');
  assert.equal((await evaluate(instance, { control: arm(500, 3), candidate: arm(500, 4) }, at(15))).status, 'insufficient');
  const promote = await evaluate(instance, strong, at(15));
  assert.equal(promote.status, 'promote'); assert.equal(promote.promote, true);
  assert.equal((await evaluate(instance, { control: arm(500, 100), candidate: arm(500, 104) }, at(15))).status, 'inconclusive');
  assert.equal((await evaluate(instance, { control: arm(500, 170), candidate: arm(500, 100) }, at(15))).status, 'candidate_worse');
  assert.equal((await evaluate(instance, { control: { exposed: 'x' } }, at(15))).status, 'error_invalid_counts');
  assert.equal((await evaluate({ ...instance, endAt: at(1).toISOString() }, strong, at(15))).status, 'error_invalid_definition');
});

test('prioritization uses only publishable step rates and never repeats or overrides promoted surfaces', () => {
  assert.equal(selectNext(null, [], []).status, 'no_data');
  assert.equal(selectNext(summary(0.4, null), [], []).status, 'insufficient_data');
  assert.equal(selectNext(summary(0.4, 0.3), [], []).entry?.key, 'download-heading-v1');
  assert.equal(selectNext(summary(0.4, 0.3), ['download-heading-v1'], []).entry?.key, 'hero-cta-label-v1');
  assert.equal(selectNext(summary(0.2, 0.3), [], ['hero_cta_label']).entry?.key, 'hero-note-position-v1');
  assert.equal(selectNext(summary(0.2, 0.3), CATALOG.map(entry => entry.key), []).status, 'catalog_exhausted');
});

test('build-time promotions only accept reviewed catalog winners against exact control markup', () => {
  const html = '<h2 id="download-title">Bring a tiny garden to your Windows day.</h2>';
  const record = { key: 'download-heading-v1', experimentId: 'download-heading-v1.20261001T000000', definitionHash: 'a'.repeat(64), decision: 'promote' };
  assert.equal(applyPromotionsToHtml(html, [record]), '<h2 id="download-title">Download Bloomstep for your Windows PC.</h2>');
  assert.throws(() => applyPromotionsToHtml(html, [{ ...record, decision: 'inconclusive' }]));
  assert.throws(() => applyPromotionsToHtml('<h2 id="download-title">Edited</h2>', [record]));
});

async function harness({ environment = 'isolated', settings = () => ({}), stage = summary(0.4, 0.3) } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  const store = await FileBackedCosmosContainer.openFresh(join(directory, 'store.json'));
  let now = at(0);
  const role = (/** @type {string} */ name) => async (/** @type {any} */ request) => {
    if (request.headers.get('x-role') !== name) throw new ServiceError(401, 'no');
    return { roles: [name] };
  };
  const handlers = createExperimentHandlers({ container: () => /** @type {any} */ (store), environment, settings,
    authenticate: role('Bloomstep.Admin'), authenticateWorker: role('Bloomstep.AggregateWriter'),
    stageSummary: async () => stage, clock: () => now });
  const request = (/** @type {unknown} */ body, headers = {}) => /** @type {any} */ ({
    headers: new Headers({ 'content-type': 'application/json', ...headers }), text: async () => typeof body === 'string' ? body : JSON.stringify(body) });
  const call = async (/** @type {Promise<any>} */ promise) => {
    try { const result = await promise; return { status: result.status ?? 200, body: result.jsonBody }; }
    catch (error) { if (error instanceof ServiceError) return { status: error.status, body: { error: error.message } }; throw error; }
  };
  return { store, handlers, request, call, set: (/** @type {Date} */ value) => { now = value; },
    worker: () => call(handlers.tick(request({}, { 'x-role': 'Bloomstep.AggregateWriter' }))),
    admin: () => request({}, { 'x-role': 'Bloomstep.Admin' }),
    close: async () => { await store.close(); await rm(directory, { recursive: true, force: true }); } };
}

test('production is OFF by default: config disabled, tick no-op, writes rejected, no production documents', async () => {
  const h = await harness({ environment: 'production' });
  try {
    const config = await h.call(h.handlers.config());
    assert.deepEqual([config.body.enabled, config.body.reason, config.body.active], [false, 'production_not_enabled', null]);
    assert.equal((await h.worker()).body.status, 'disabled');
    const exposure = await h.call(h.handlers.exposure(h.request({ experimentId: 'download-heading-v1.20261001T000000',
      definitionHash: 'a'.repeat(64), subjectId: randomUUID(), arm: 'control', applied: true })));
    assert.equal(exposure.status, 503);
    assert.equal((await h.store.items.query({ query: 'SELECT * FROM c WHERE c.type = "account"' }).fetchAll()).resources.length, 0);
  } finally { await h.close(); }
});

test('production gate requires deployment hash + server-verified receipt for this exact policy', async () => {
  const receipt = { schemaVersion: 1, kind: 'bloomstep-experiment-isolated-acceptance', result: 'passed', policyVersion: 'x', policyHash: await policyHash(),
    segregation: { environment: 'isolated', productionDocuments: 0, syntheticOnly: true },
    scenarios: Array.from({ length: 6 }, (_, index) => ({ name: `s${index}`, passed: true })), costs: { declaration: 'run_dependencies_only', paidServices: [], newBillableResources: [], actualHostingBill: 'not_measured' } };
  const hash = await sha256Hex(canonicalJson(receipt));
  const h = await harness({ environment: 'production', settings: () => ({ production: 'enabled', acceptanceSha256: hash }) });
  try {
    assert.equal((await h.call(h.handlers.config())).body.reason, 'acceptance_receipt_not_verified');
    const admin = (/** @type {unknown} */ body) => /** @type {any} */ ({ headers: new Headers({ 'x-role': 'Bloomstep.Admin' }), text: async () => JSON.stringify(body) });
    assert.equal((await h.call(h.handlers.acceptance(admin({ ...receipt, result: 'failed' })))).status, 400);
    assert.equal((await h.call(h.handlers.acceptance(admin({ ...receipt, policyVersion: 'tampered' })))).status, 409);
    assert.equal((await h.call(h.handlers.acceptance(admin({ ...receipt, policyHash: 'b'.repeat(64) })))).status, 409);
    assert.equal((await h.call(h.handlers.acceptance({ headers: new Headers(), text: async () => JSON.stringify(receipt) }))).status, 401);
    assert.equal((await h.call(h.handlers.acceptance(admin(receipt)))).status, 200);
    assert.equal((await h.call(h.handlers.config())).body.enabled, true);
  } finally { await h.close(); }
});

test('isolated loop: launch, exposure-before-outcome, idempotence, forget tombstone, caps, kill switch, audit', async () => {
  const h = await harness();
  try {
    assert.equal((await h.call(h.handlers.tick(h.request({})))).status, 401);
    const launched = await h.worker();
    assert.equal(launched.body.active?.startsWith('download-heading-v1.'), true);
    const { active } = (await h.call(h.handlers.config())).body;
    assert.equal(await verifyInstance(active), true);
    const subjectId = randomUUID(), assigned = await assignArm(active, subjectId);
    const base = { experimentId: active.experimentId, subjectId };
    assert.equal((await h.call(h.handlers.outcome(h.request({ ...base, event: 'download_click' })))).status, 409, 'outcome before exposure');
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned === 'control' ? 'candidate' : 'control', applied: true })))).status, 400);
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: 'f'.repeat(64), arm: assigned, applied: true })))).status, 409);
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned, applied: true, extra: 1 })))).status, 400);
    assert.equal((await h.call(h.handlers.exposure(h.request('x'.repeat(2000))))).status, 413);
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned, applied: true }, { 'sec-gpc': '1' })))).status, 204);
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned, applied: true })))).status, 201);
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned, applied: true })))).body.duplicate, true);
    assert.equal((await h.call(h.handlers.outcome(h.request({ ...base, event: 'download_click' })))).status, 201);
    assert.equal((await h.call(h.handlers.outcome(h.request({ ...base, event: 'download_click' })))).body.duplicate, true);
    const counts = async () => (await h.store.item(`counts:${active.experimentId}`, PARTITIONS.isolated).read()).resource.arms[assigned];
    assert.deepEqual(await counts(), arm(1, 1));
    assert.equal((await h.call(h.handlers.forget(h.request({ subjectId })))).body.deleted, true);
    assert.deepEqual(await counts(), arm(0, 0), 'withdrawn visit removed from aggregates');
    const visit = (await h.store.item(`visit:${await sha256Hex(`bloomstep-visit:${subjectId}`)}`, PARTITIONS.isolated).read()).resource;
    assert.deepEqual(Object.keys(visit).filter(key => !key.startsWith('_')).sort(), ['forgotten', 'id', 'schemaVersion', 'ttl', 'type', 'userId']);
    assert.equal((await h.call(h.handlers.outcome(h.request({ ...base, event: 'primary_cta_click' })))).status, 410, 'late outcome cannot recreate');
    assert.equal((await h.call(h.handlers.exposure(h.request({ ...base, definitionHash: active.definitionHash, arm: assigned, applied: true })))).status, 410);
    const report = (await h.call(h.handlers.report(h.admin()))).body;
    assert.equal(report.activeCounts, null, 'interim counts withheld');
    assert.ok(!JSON.stringify(report).includes(subjectId));
    assert.equal((await h.call(h.handlers.report(h.request({})))).status, 401);
    h.set(at(15));
    const late = randomUUID();
    assert.equal((await h.call(h.handlers.exposure(h.request({ experimentId: active.experimentId, subjectId: late, definitionHash: active.definitionHash,
      arm: await assignArm(active, late), applied: true })))).status, 409, 'outside horizon');
    const concluded = await h.worker();
    assert.equal(concluded.body.actions[0].decision.status, 'no_data');
    assert.equal(concluded.body.active?.startsWith('hero-cta-label-v1.'), true, 'next experiment launched');
    const kill = await h.call(h.handlers.kill(/** @type {any} */ ({ headers: new Headers({ 'x-role': 'Bloomstep.Admin', 'content-type': 'application/json' }),
      text: async () => JSON.stringify({ killed: true, reason: 'test kill' }) })));
    assert.equal(kill.body.killed, true);
    assert.deepEqual([(await h.call(h.handlers.config())).body.active, (await h.call(h.handlers.config())).body.reason], [null, 'killed']);
    assert.equal((await h.worker()).body.status, 'disabled');
    const audit = (await h.call(h.handlers.report(h.admin()))).body;
    assert.deepEqual(audit.concluded.map((/** @type {any} */ row) => row.decision), ['no_data', 'killed']);
    assert.ok(['launch', 'retain_control', 'kill'].every(action => audit.audit.some((/** @type {any} */ row) => row.action === action)));
  } finally { await h.close(); }
});

test('admission cap fails visibly', async () => {
  const h = await harness();
  try {
    let last;
    for (let index = 0; index < 121; index++) last = await h.call(h.handlers.config());
    assert.equal(last?.status, 429);
  } finally { await h.close(); }
});

test('insufficient website data blocks any launch', async () => {
  const h = await harness({ stage: summary(null, null) });
  try {
    const result = await h.worker();
    assert.equal(result.body.active, null);
    assert.equal(result.body.actions[0].status, 'insufficient_data');
  } finally { await h.close(); }
});
