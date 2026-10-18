import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CATALOG, DESIGN, applyVariant, applyPromotionsToHtml, freezeInstance, verifyInstance, selectNext,
} from '../src/experiment-policy.mjs';
import { createExperimentClient } from '../../site/experiment-client.mjs';

const control = { headline: 'Build a habit small enough to start today.', cta: 'Download Windows preview' };
const summary = { steps: [
  { from: 'landing_view', to: 'primary_cta_click', rate: .2 },
  { from: 'primary_cta_click', to: 'download_click', rate: .5 },
] };
const entries = () => CATALOG.filter(entry => entry.surface === 'hero_copy_pair');
function page(copy = control) {
  const nodes = { '#intro': { textContent: copy.headline }, '#primary-cta-copy': { textContent: copy.cta } };
  return { nodes, querySelector: selector => nodes[selector] ?? null };
}
test('approved A/B then A/C pairs are frozen, baseline-bound, never simultaneous or promoted into the next control', async () => {
  const trials = entries();
  assert.equal(trials.length, 2);
  assert.deepEqual(trials.map(entry => entry.candidate.value), [
    { headline: 'A tiny habit. A little more you.', cta: 'Get the Windows preview' },
    { headline: 'Make room for one small habit.', cta: 'Try the Windows preview' },
  ]);
  for (const entry of trials) {
    assert.deepEqual(entry.control.value, control);
    assert.equal(await verifyInstance(await freezeInstance(entry, { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' })), true);
  }
  assert.equal(selectNext(summary, [], []).entry?.key, trials[0].key);
  assert.equal(selectNext(summary, [trials[0].key], ['hero_copy_pair']).entry?.key, trials[1].key);
  assert.equal(selectNext(summary, trials.map(entry => entry.key), []).status, 'catalog_exhausted');
  assert.equal(selectNext({ steps: summary.steps.map(step => ({ ...step, rate: null })) }, [], []).status, 'insufficient_data');
  assert.equal(selectNext({ steps: summary.steps.slice(0, 1) }, [], []).status, 'insufficient_data', 'missing download step cannot authorize a launch');
  assert.equal(DESIGN.horizonDays, 14);
  assert.equal(DESIGN.minSamplePerArm, 400);
  assert.equal(DESIGN.minExpectedCell, 10);
  assert.ok(DESIGN.alpha <= .025, 'two staged comparisons share an efficacy error budget of at most .05');
});
test('pair application validates both nodes before mutation and withdrawal restores both texts', () => {
  const trial = entries()[0];
  assert.ok(trial);
  const document = page();
  applyVariant(document, trial.surface, trial.control.value, trial.candidate.value);
  assert.equal(document.nodes['#intro'].textContent, trial.candidate.value.headline);
  assert.equal(document.nodes['#primary-cta-copy'].textContent, trial.candidate.value.cta);
  applyVariant(document, trial.surface, trial.candidate.value, trial.control.value);
  assert.equal(document.nodes['#intro'].textContent, control.headline);
  document.nodes['#primary-cta-copy'].textContent = 'Unexpected live copy';
  assert.throws(() => applyVariant(document, trial.surface, trial.control.value, trial.candidate.value));
  assert.equal(document.nodes['#intro'].textContent, control.headline, 'no partial pair mutation');
});
test('exposure failure restores A and remains inactive; withdrawal during enrollment cannot leave a variant', async () => {
  const instance = await freezeInstance(entries()[0], { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' });
  const document = page();
  const client = createExperimentClient({ document, uuid: () => '00000000-0000-4000-8000-000000000001', fetchJson: async path => {
    if (path === '/api/web/experiments') return { enabled: true, active: instance };
    if (path.endsWith('/exposure')) throw Error('exposure unavailable');
    return {};
  } });
  await assert.rejects(client.start(), /exposure unavailable/);
  assert.equal(client.state.active, false);
  assert.equal(document.nodes['#intro'].textContent, control.headline);
  assert.equal(document.nodes['#primary-cta-copy'].textContent, control.cta);
  assert.equal(await client.outcome('download_click'), false);
  let finish;
  const config = new Promise(resolve => { finish = resolve; });
  const pending = createExperimentClient({ document, fetchJson: async path => path === '/api/web/experiments' ? config : {} });
  const starting = pending.start();
  await pending.stop();
  finish({ enabled: true, active: instance });
  await starting;
  assert.equal(pending.state.active, false);
  assert.equal(document.nodes['#intro'].textContent, control.headline);
});
test('copy-pair wins are evidence only, never build-time public fallback replacements', () => {
  const trial = entries()[0];
  assert.ok(trial);
  const html = '<h1 id="intro">Build a habit small enough to start today.</h1>';
  assert.throws(() => applyPromotionsToHtml(html, [{
    key: trial.key, experimentId: `${trial.key}.20261001T000000`, definitionHash: 'a'.repeat(64), decision: 'promote',
  }]), /baseline|owner|pair/i);
});
test('outcomes wait for persisted exposure, serialize CTA/download writes, and navigation does not withdraw committed evidence', async () => {
  const instance = await freezeInstance(entries()[0], { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' });
  const document = page(), requests = [];
  let releaseExposure, releaseOutcome, inFlight = 0, maximum = 0;
  const exposure = new Promise(resolve => { releaseExposure = resolve; });
  const firstOutcome = new Promise(resolve => { releaseOutcome = resolve; });
  const client = createExperimentClient({ document, fetchJson: async (path, body) => {
    requests.push({ path, body });
    if (path === '/api/web/experiments') return { enabled: true, active: instance };
    if (path.endsWith('/exposure')) return exposure;
    if (path.endsWith('/outcome')) {
      inFlight++; maximum = Math.max(maximum, inFlight);
      if (body.event === 'primary_cta_click') await firstOutcome;
      inFlight--;
    }
    return {};
  } });
  const started = client.start();
  while (!requests.some(row => row.path.endsWith('/exposure'))) await new Promise(resolve => setTimeout(resolve, 1));
  assert.equal(await client.outcome('download_click'), false);
  releaseExposure({});
  await started;
  const cta = client.outcome('primary_cta_click'), download = client.outcome('download_click');
  await new Promise(resolve => setTimeout(resolve, 1));
  assert.equal(requests.filter(row => row.path.endsWith('/outcome')).length, 1);
  releaseOutcome({});
  assert.deepEqual(await Promise.all([cta, download]), [true, true]);
  assert.equal(maximum, 1);
  client.end();
  assert.deepEqual({ headline: document.nodes['#intro'].textContent, cta: document.nodes['#primary-cta-copy'].textContent }, control);
  assert.equal(client.state.active, false);
  assert.equal(requests.some(row => row.path.endsWith('/forget')), false, 'navigation is not explicit withdrawal');
});
test('withdrawal during visible-exposure wait cancels enrollment and cannot recreate a visit', async () => {
  const instance = await freezeInstance(entries()[0], { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' });
  const document = page(), paths = [];
  let waiting = false;
  const client = createExperimentClient({
    document,
    waitForExposure: signal => new Promise((resolve, reject) => {
      waiting = true;
      signal.addEventListener('abort', () => reject(Error('cancelled')));
    }),
    fetchJson: async path => { paths.push(path); return path === '/api/web/experiments' ? { enabled: true, active: instance } : {}; },
  });
  const started = client.start();
  const rejection = assert.rejects(started, /cancelled/);
  while (!waiting) await new Promise(resolve => setTimeout(resolve, 1));
  await client.stop();
  await rejection;
  assert.equal(paths.some(path => path.endsWith('/exposure')), false);
  assert.equal(paths.filter(path => path.endsWith('/forget')).length, 1);
  assert.equal(client.state.active, false);
  assert.equal(document.nodes['#intro'].textContent, control.headline);
});
test('a confirmed application-error record contributes to the guardrail until explicit withdrawal, never outcomes', async () => {
  const instance = await freezeInstance(entries()[0], { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' });
  const document = page(), requests = [];
  delete document.nodes['#primary-cta-copy'];
  const client = createExperimentClient({ document, fetchJson: async (path, body) => {
    requests.push({ path, body });
    return path === '/api/web/experiments' ? { enabled: true, active: instance } : {};
  } });
  await assert.rejects(client.start(), /pair|selector|copy/i);
  assert.equal(requests.find(row => row.path.endsWith('/exposure')).body.applied, false);
  assert.equal(requests.some(row => row.path.endsWith('/forget')), false, 'retain persisted application error for safety evaluation');
  assert.equal(client.state.active, false);
  assert.equal(await client.outcome('download_click'), false);
  await client.stop();
  assert.equal(requests.filter(row => row.path.endsWith('/forget')).length, 1, 'explicit withdrawal still removes the error contribution');
});
