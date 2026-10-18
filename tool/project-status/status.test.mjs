import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get } from 'node:http';
import {
  collect, freshness, mapPull, mapJobs, dependencyView, validateConfig,
  writeSnapshot, startServer, ghRead,
} from './status.mjs';

const now = '2026-10-16T00:00:00.000Z';
const sourceConfig = JSON.parse(await readFile(new URL('./sources.json', import.meta.url), 'utf8'));
const required = ['api', 'native'];
const job = (name, conclusion = 'success', status = 'completed') => ({ name, conclusion, status });
const config = {
  repo: 'Sampath-K/bloomstep', maxAgeSeconds: 300, target: 'candidate',
  workstreams: [
    { id: 'code', title: 'Code', owner: 'Engineering', nextAction: 'Review exact head', kind: 'pull', number: 48, requiredJobs: required, dependencies: [] },
    { id: 'candidate', title: 'Candidate', owner: 'Integrator', nextAction: 'Compose after review', kind: 'gate',
      dependencies: [{ id: 'code', accept: ['review-ready', 'merged'] }] },
  ],
};

test('contract: owner-trial decision permits default-OFF hosted experiments without implying public MVP readiness', () => {
  validateConfig(sourceConfig);
  const target = sourceConfig.workstreams.find(row => row.id === sourceConfig.target);
  assert.match(target.title, /owner-trial/i);
  assert.ok(!target.dependencies.some(dep => dep.id === 'hosted'));
  const rows = sourceConfig.workstreams.map(row => ({
    id: row.id, state: row.id === 'preview' ? 'released' :
      ['continuity', 'growthbook', 'visual'].includes(row.id) ? 'merged' :
      ['candidate', 'native'].includes(row.id) ? 'verified' : 'unknown',
    observedAt: ['hosted', 'launch'].includes(row.id) ? null : now,
  }));
  const graph = dependencyView(sourceConfig, rows, now);
  assert.deepEqual(graph.blockers.launch, []);
  assert.equal(rows.find(row => row.id === 'hosted').state, 'unknown');
  assert.equal(rows.find(row => row.id === 'launch').state, 'unknown');
  assert.ok(sourceConfig.workstreams.find(row => row.id === 'hosted').dependencies.some(dep => dep.id === 'growthbook'));
  assert.match(target.note, /public.*MVP/i);
});

test('contract: configured CI next actions do not assert failures absent observed failures', () => {
  for (const row of sourceConfig.workstreams.filter(row => ['pull', 'branch', 'workflow'].includes(row.kind))) {
    assert.doesNotMatch(row.nextAction, /resolve.*failures/i);
  }
});

test('contract: polling starts immediately, never overlaps, backs off on partial errors and stops cleanly', async () => {
  const { startPolling } = await import('./status.mjs');
  const scheduled = [], observations = [];
  let calls = 0, release;
  const poller = startPolling({
    seconds: 60, clock: () => now,
    schedule: (callback, delay) => { scheduled.push({ callback, delay }); return scheduled.length; },
    cancel: handle => { observations.push({ cancelled: handle }); },
    publish: async state => observations.push(structuredClone(state)),
    refresh: async signal => {
      assert.equal(signal.aborted, false);
      calls++;
      if (calls === 1) await new Promise(resolve => { release = resolve; });
      return { collectionState: calls === 1 ? 'partial' : 'complete', collectedAt: now,
        lastCompleteAt: calls === 1 ? null : now,
        workstreams: [{ observedAt: now, error: null }, { observedAt: null, error: calls === 1 ? 'HTTP404' : null }] };
    },
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 1);
  assert.equal(scheduled.length, 0);
  assert.equal(observations[0].status, 'collecting');
  release();
  await poller.ready;
  assert.equal(scheduled[0].delay, 120000);
  assert.equal(observations.at(-1).status, 'partial');
  assert.equal(observations.at(-1).lastSourceSuccessAt, now);
  assert.equal(observations.at(-1).errors[0], 'HTTP404');
  await scheduled[0].callback();
  assert.equal(calls, 2);
  assert.equal(scheduled[1].delay, 60000);
  assert.equal(observations.at(-1).lastCompleteAt, now);
  await poller.stop();
  await scheduled[1].callback();
  assert.equal(calls, 2);
  assert.equal(observations.at(-1).status, 'stopped');
});

test('contract: polling bounds, rate-limit backoff and abort preserve failure visibility', async () => {
  const { startPolling } = await import('./status.mjs');
  assert.throws(() => startPolling({ seconds: 1 }), /60/);
  const scheduled = [], observations = [];
  const poller = startPolling({
    seconds: 60, clock: () => now, schedule: (callback, delay) => { scheduled.push({ callback, delay }); return 1; },
    cancel: () => {}, publish: async state => observations.push(structuredClone(state)),
    refresh: async () => ({ collectionState: 'failed', collectedAt: now, lastCompleteAt: null,
      retryAfterSeconds: 900, workstreams: [{ observedAt: null, error: 'GitHub rate limited' }, { observedAt: now, error: null }] }),
  });
  await poller.ready;
  assert.equal(scheduled[0].delay, 900000);
  assert.equal(observations.at(-1).lastSourceSuccessAt, null);
  assert.deepEqual(observations.at(-1).errors, ['GitHub rate limited']);
  await poller.stop();
  let aborted = false;
  const active = startPolling({ seconds: 60, publish: async () => {}, refresh: async signal =>
    new Promise((resolve, reject) => signal.addEventListener('abort', () => { aborted = true; reject(Error('abort')); }, { once: true })) });
  await new Promise(resolve => setImmediate(resolve));
  await active.stop();
  assert.equal(aborted, true);
});

test('contract: unexpected local polling failures publish errors without replacing last-known success', async () => {
  const { startPolling } = await import('./status.mjs');
  const scheduled = [], observations = [];
  let calls = 0;
  const poller = startPolling({ seconds: 60, clock: () => now,
    schedule: (callback, delay) => { scheduled.push({ callback, delay }); return 1; }, cancel: () => {},
    publish: async state => observations.push(structuredClone(state)),
    refresh: async () => {
      if (++calls === 2) throw Error('private filesystem details');
      return { collectionState: 'complete', collectedAt: now, lastCompleteAt: now, workstreams: [{ observedAt: now }] };
    },
  });
  await poller.ready;
  await scheduled[0].callback();
  assert.equal(observations.at(-1).status, 'failed');
  assert.equal(observations.at(-1).lastSourceSuccessAt, now);
  assert.equal(observations.at(-1).lastCompleteAt, now);
  assert.ok(!JSON.stringify(observations).includes('private filesystem details'));
  assert.equal(scheduled[1].delay, 120000);
  await poller.stop();
});

test('contract: lifecycle states remain distinct and merge never means verified', () => {
  assert.equal(mapPull({ state: 'open', draft: true }, 'review-ready'), 'implementing');
  assert.equal(mapPull({ state: 'open', draft: false }, 'validating'), 'validating');
  assert.equal(mapPull({ state: 'open', draft: false }, 'review-ready'), 'review-ready');
  assert.equal(mapPull({ state: 'closed', merged_at: now }, 'verified'), 'merged');
  assert.equal(mapPull({ state: 'closed', merged_at: null }, 'review-ready'), 'blocked');
  assert.equal(mapJobs([job('api'), job('native')], required, false), 'review-ready');
  assert.equal(mapJobs([job('api'), job('native')], required, true), 'verified');
  assert.equal(mapJobs([job('api')], required, true), 'unknown');
  assert.equal(mapJobs([job('api'), job('native', 'skipped')], required, true), 'blocked');
  assert.equal(mapJobs([job('api'), job('native', null, 'queued')], required, true), 'validating');
  assert.equal(mapJobs([job('api', 'failure'), job('native')], required, false), 'blocked');
});

test('contract: freshness expires, invalid/future timestamps are unknown', () => {
  assert.equal(freshness(now, now, 300), 'fresh');
  assert.equal(freshness(now, '2026-10-16T00:05:01Z', 300), 'stale');
  assert.equal(freshness(null, now, 300), 'unknown');
  assert.equal(freshness('invalid', now, 300), 'unknown');
  assert.equal(freshness('2026-10-17T00:00:00Z', now, 300), 'unknown');
});

test('contract: auth failure retains last-known evidence but never current success', async () => {
  const previous = { workstreams: [{ id: 'code', state: 'merged', observedAt: now, evidence: [{ title: 'PR', url: 'https://github.com/Sampath-K/bloomstep/pull/48' }] }] };
  let reads = 0;
  const result = await collect(config, { now, previous, auth: async () => { throw Error('secret token'); }, read: async () => { reads++; } });
  assert.equal(reads, 0);
  assert.equal(result.collectionState, 'failed');
  assert.equal(result.workstreams[0].state, 'unknown');
  assert.equal(result.workstreams[0].lastKnown.state, 'merged');
  assert.equal(result.workstreams[0].lastKnown.observedAt, now);
  assert.match(result.workstreams[0].error, /authentication/i);
  assert.ok(!JSON.stringify(result).includes('secret token'));
});

const pull = { number: 48, state: 'open', draft: false, head: { sha: 'a'.repeat(40) }, html_url: 'https://github.com/Sampath-K/bloomstep/pull/48' };
const run = { id: 42, head_sha: pull.head.sha, html_url: 'https://github.com/Sampath-K/bloomstep/actions/runs/42', run_attempt: 1 };
function reader(path) {
  if (path.endsWith('/pulls/48')) return pull;
  if (path.includes('/actions/workflows/ci.yml/runs?')) return [{ total_count: 1, workflow_runs: [run] }];
  if (path.includes('/actions/runs/42/attempts/1/jobs?')) return [{ total_count: 2, jobs: [job('api'), job('native')] }];
  throw Error(`Unexpected read: ${path}`);
}

test('contract: complete exact-head evidence unblocks a planned integration, not completion', async () => {
  const result = await collect(config, { now, auth: async () => {}, read: async path => reader(path) });
  assert.equal(result.collectionState, 'complete');
  assert.equal(result.workstreams[0].state, 'review-ready');
  assert.equal(result.workstreams[1].state, 'planned');
  assert.equal(result.agentStatus, 'unavailable');
  assert.equal(result.workstreams[0].sha, pull.head.sha);
});

test('contract: partial API failure keeps successful independent reads and blocks dependents', async () => {
  const second = { ...config.workstreams[0], id: 'other', number: 49 };
  const result = await collect({ ...config, workstreams: [...config.workstreams, second] }, {
    now, auth: async () => {}, read: async path => {
      if (path.endsWith('/pulls/49')) throw Error('private raw response');
      return reader(path);
    },
  });
  assert.equal(result.collectionState, 'partial');
  assert.equal(result.workstreams.find(row => row.id === 'code').state, 'review-ready');
  assert.equal(result.workstreams.find(row => row.id === 'other').state, 'unknown');
  assert.ok(!JSON.stringify(result).includes('private raw response'));
});

test('contract: jobs failure invalidates even an observed merged PR; prior timestamps survive repeated failures', async () => {
  const previous = { workstreams: [{ id: 'code', state: 'unknown', observedAt: null, lastKnown: { state: 'merged', observedAt: now, evidence: [] } }] };
  const result = await collect(config, { now, previous, auth: async () => {}, read: async path => {
    if (path.endsWith('/pulls/48')) return { ...pull, state: 'closed', merged_at: now };
    throw Error('API timeout');
  } });
  assert.equal(result.workstreams[0].state, 'unknown');
  assert.equal(result.workstreams[0].lastKnown.observedAt, now);
});

test('contract: stale, released and merged do not satisfy verified dependencies; path uses depth not time', () => {
  const c = { ...config, workstreams: [
    { ...config.workstreams[0], id: 'code' },
    { ...config.workstreams[1], dependencies: [{ id: 'code', accept: ['verified'] }] },
  ] };
  const rows = [{ id: 'code', state: 'merged', observedAt: now }, { id: 'candidate', state: 'planned', observedAt: now }];
  let graph = dependencyView(c, rows, now);
  assert.deepEqual(graph.blockers.candidate, ['code']);
  assert.deepEqual(graph.paths, [['code', 'candidate']]);
  rows[0].state = 'verified';
  graph = dependencyView(c, rows, now);
  assert.deepEqual(graph.blockers.candidate, []);
  graph = dependencyView(c, rows, '2026-10-16T00:06:00Z');
  assert.deepEqual(graph.blockers.candidate, ['code']);
});

test('contract: release resolves immutable annotated tag, never target_commitish branch', async () => {
  const c = { ...config, target: 'release', workstreams: [{ ...config.workstreams[0], id: 'release', kind: 'release' }] };
  const result = await collect(c, { now, auth: async () => {}, read: async path => {
    if (path.includes('/releases?')) return [[{ tag_name: 'v1', draft: false, published_at: now, html_url: 'https://github.com/Sampath-K/bloomstep/releases/tag/v1', target_commitish: 'main' }]];
    if (path.includes('/git/ref/tags/v1')) return { object: { type: 'tag', sha: 'b'.repeat(40) } };
    if (path.includes('/git/tags/')) return { object: { type: 'commit', sha: 'c'.repeat(40) } };
    throw Error('Unexpected read');
  } });
  assert.equal(result.workstreams[0].state, 'released');
  assert.equal(result.workstreams[0].sha, 'c'.repeat(40));
});

test('contract: missing/empty/malformed evidence fails closed', async () => {
  for (const bad of [[], [{}], [{ workflow_runs: [] }], [{ total_count: 2, workflow_runs: [run] }]]) {
    const result = await collect(config, { now, auth: async () => {}, read: async path => path.endsWith('/pulls/48') ? pull : bad });
    assert.equal(result.workstreams[0].state, 'unknown');
    assert.equal(result.workstreams[1].state, 'blocked');
  }
  assert.throws(() => validateConfig({ ...config, target: 'missing' }));
  assert.throws(() => validateConfig({ ...config, workstreams: [{ ...config.workstreams[0], dependencies: [{ id: 'code', accept: ['merged'] }] }] }));
  assert.throws(() => validateConfig({ ...config, workstreams: [{ ...config.workstreams[0], id: 'candidate', dependencies: [{ id: 'missing', accept: ['verified'] }] }] }));
});

test('contract: all pages and exact run attempt are used; an unrelated SHA is never accepted', async () => {
  const result = await collect(config, { now, auth: async () => {}, read: async (path, paginate) => {
    if (path.includes('/jobs?')) {
      assert.equal(paginate, true);
      return [{ total_count: 2, jobs: [job('api')] }, { total_count: 2, jobs: [job('native')] }];
    }
    return reader(path);
  } });
  assert.equal(result.workstreams[0].state, 'review-ready');
  const wrong = await collect(config, { now, auth: async () => {}, read: async path => {
    if (path.includes('/runs?')) return [{ total_count: 1, workflow_runs: [{ ...run, head_sha: 'b'.repeat(40) }] }];
    return reader(path);
  } });
  assert.equal(wrong.workstreams[0].state, 'unknown');
});

test('contract: remote branch without PR means implementing, never live agent activity', async () => {
  const definition = { ...config.workstreams[0], kind: 'branch', branch: 'visual' };
  const result = await collect({ ...config, workstreams: [definition, config.workstreams[1]] }, {
    now, auth: async () => {}, read: async path => {
      if (path.includes('/pulls?')) return [[]];
      if (path.includes('/branches/visual')) return { commit: { sha: 'd'.repeat(40) } };
      throw Error('Unexpected read');
    },
  });
  assert.equal(result.workstreams[0].state, 'implementing');
  assert.equal(result.agentStatus, 'unavailable');
  assert.equal(result.workstreams[1].state, 'blocked');
});

test('contract: a satisfied direct state cannot bypass unmet transitive prerequisites', () => {
  const c = { ...config, workstreams: [
    config.workstreams[0],
    { ...config.workstreams[1], id: 'middle' },
    { ...config.workstreams[1], dependencies: [{ id: 'middle', accept: ['verified'] }] },
  ] };
  const graph = dependencyView(c, [
    { id: 'code', state: 'blocked', observedAt: now },
    { id: 'middle', state: 'verified', observedAt: now },
    { id: 'candidate', state: 'planned', observedAt: now },
  ], now);
  assert.deepEqual(graph.blockers.candidate, ['middle']);
  assert.deepEqual(graph.paths, [['code', 'middle', 'candidate']]);
});

test('contract: gh transport is GET-only, bounded and sanitizes timeout failures', async () => {
  await assert.rejects(ghRead('https://example.org/token'), /path/i);
  await assert.rejects(ghRead('repos/another/repo/issues'), /path/i);
  await assert.rejects(ghRead('repos/Sampath-K/bloomstep/pulls/48', false, async () => { throw Object.assign(Error('secret'), { code: 'ETIMEDOUT' }); }), /timed out/i);
  await assert.rejects(ghRead('repos/Sampath-K/bloomstep/pulls/48', false, async () => {
    throw Object.assign(Error('secret'), { stderr: 'gh: private details (HTTP 404)' });
  }), error => error.message.includes('HTTP 404') && !error.message.includes('private details'));
  await ghRead('repos/Sampath-K/bloomstep/pulls/48', true, async (file, args, options) => {
    assert.equal(file, 'gh');
    assert.deepEqual(args, ['api', '--hostname', 'github.com', '--method', 'GET', 'repos/Sampath-K/bloomstep/pulls/48', '--paginate', '--slurp']);
    assert.equal(options.timeout, 20000);
    assert.equal(options.windowsHide, true);
    return { stdout: '[[]]' };
  });
});

test('contract: protected verification requires current published tag SHA and every named job', async () => {
  const c = { ...config, target: 'native', workstreams: [
    { ...config.workstreams[0], id: 'release', kind: 'release' },
    { ...config.workstreams[0], id: 'native', kind: 'workflow', release: 'release',
      dependencies: [{ id: 'release', accept: ['released'] }] },
  ] };
  for (const [jobs, expected] of [
    [[job('api'), job('native')], 'verified'],
    [[job('api'), job('native', 'cancelled')], 'blocked'],
    [[job('api'), job('native', 'skipped')], 'blocked'],
    [[job('api')], 'unknown'],
  ]) {
    const result = await collect(c, { now, auth: async () => {}, read: async path => {
      if (path.includes('/releases?')) return [[{ tag_name: 'v1', draft: false, published_at: now, html_url: 'https://github.com/Sampath-K/bloomstep/releases/tag/v1' }]];
      if (path.includes('/git/ref/tags/')) return { object: { type: 'commit', sha: pull.head.sha } };
      if (path.includes('/runs?')) {
        assert.ok(path.includes('branch=v1'));
        return [{ total_count: 1, workflow_runs: [{ ...run, head_branch: 'v1' }] }];
      }
      if (path.includes('/jobs?')) return [{ total_count: jobs.length, jobs }];
      throw Error('Unexpected read');
    } });
    assert.equal(result.workstreams[1].state, expected);
    assert.equal(result.workstreams[0].state, 'released');
  }
});

test('contract: no published releases is unknown, and manual gates never auto-verify', async () => {
  const c = { ...config, target: 'manual', workstreams: [
    { ...config.workstreams[0], id: 'release', kind: 'release' },
    { ...config.workstreams[1], id: 'manual', kind: 'manual', dependencies: [{ id: 'release', accept: ['released'] }] },
  ] };
  const result = await collect(c, { now, auth: async () => {}, read: async () => [[]] });
  assert.equal(result.collectionState, 'failed');
  assert.equal(result.workstreams[0].state, 'unknown');
  assert.equal(result.workstreams[1].state, 'unknown');
  assert.deepEqual(result.graph.blockers.manual, ['release']);
});

test('contract: atomic snapshot and loopback server expose only fixed read-only routes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'bloomstep-status-'));
  let server;
  try {
    await writeSnapshot(dir, { schemaVersion: 1, collectedAt: now, workstreams: [] });
    assert.equal(JSON.parse(await readFile(join(dir, 'snapshot.json'), 'utf8')).collectedAt, now);
    server = await startServer({ port: 0, directory: dir });
    const base = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(base)).status, 200);
    assert.equal((await fetch(`${base}/?scoutTheme=dark`)).status, 200);
    assert.equal((await fetch(`${base}/snapshot.json`)).status, 200);
    assert.equal((await fetch(`${base}/polling.json`)).status, 503);
    assert.equal((await fetch(`${base}/status.mjs`)).status, 404);
    assert.equal((await fetch(`${base}/snapshot.json`, { method: 'POST' })).status, 405);
    const foreignHostStatus = await new Promise((resolve, reject) => {
      get(base, { headers: { Host: 'evil.example' } }, response => { response.resume(); resolve(response.statusCode); }).on('error', reject);
    });
    assert.equal(foreignHostStatus, 403);
    assert.equal((await fetch(base, { headers: { Origin: 'https://evil.example' } })).status, 403);
    assert.equal((await fetch(`${base}/snapshot.json`)).headers.get('cache-control'), 'no-store');
    await rm(join(dir, 'snapshot.json'));
    assert.equal((await fetch(`${base}/snapshot.json`)).status, 503);
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await rm(dir, { recursive: true });
  }
});

const later = '2026-10-16T00:01:00.000Z';
const execConfig = { ...config, workstreams: [
  { ...config.workstreams[0], agentNext: 'Await exact-head CI for PR48.', ownerNext: 'Review PR48 when CI is green.' },
  { ...config.workstreams[1], ownerNext: 'Approve candidate composition.' },
] };

test('contract: first collection is a baseline, not a list of changes', async () => {
  const result = await collect(execConfig, { now, auth: async () => {}, read: async path => reader(path) });
  assert.equal(result.changeBaseline, true);
  assert.deepEqual(result.changesSincePrevious, []);
  assert.deepEqual(result.changes, []);
});

test('contract: unchanged evidence and heartbeat collections never count as progress', async () => {
  const first = await collect(execConfig, { now, auth: async () => {}, read: async path => reader(path) });
  const second = await collect(execConfig, { now: later, previous: first, auth: async () => {}, read: async path => reader(path) });
  assert.equal(second.changeBaseline, false);
  assert.deepEqual(second.changesSincePrevious, []);
  assert.deepEqual(second.changes, []);
});

test('contract: concrete state, SHA and job-outcome changes are recorded with evidence and history is bounded', async () => {
  const pending = path => path.includes('/jobs?') ? [{ total_count: 2, jobs: [job('api'), job('native', null, 'in_progress')] }] : reader(path);
  const first = await collect(execConfig, { now, auth: async () => {}, read: async path => pending(path) });
  assert.equal(first.workstreams[0].state, 'validating');
  const second = await collect(execConfig, { now: later, previous: first, auth: async () => {}, read: async path => reader(path) });
  const kinds = second.changesSincePrevious.map(change => `${change.id}:${change.kind}`);
  assert.ok(kinds.includes('code:state'));
  assert.ok(kinds.includes('code:check'));
  const state = second.changesSincePrevious.find(change => change.kind === 'state' && change.id === 'code');
  assert.equal(state.from, 'validating');
  assert.equal(state.to, 'review-ready');
  assert.equal(state.observedAt, later);
  assert.match(state.evidence, /^https:\/\/github\.com\/Sampath-K\/bloomstep\//);
  const moved = await collect(execConfig, { now: '2026-10-16T00:02:00.000Z', previous: second, auth: async () => {}, read: async path =>
    path.endsWith('/pulls/48') ? { ...pull, head: { sha: 'e'.repeat(40) } } :
    path.includes('/runs?') ? [{ total_count: 1, workflow_runs: [{ ...run, head_sha: 'e'.repeat(40) }] }] : reader(path) });
  assert.ok(moved.changesSincePrevious.some(change => change.kind === 'sha' && change.to === 'e'.repeat(40)));
  assert.ok(!moved.changesSincePrevious.some(change => change.kind === 'check'));
  assert.ok(moved.changes.length >= 3);
  const padded = { ...moved, changes: Array.from({ length: 60 }, (_, i) => ({ id: 'code', kind: 'state', from: 'a', to: 'b', observedAt: now, n: i })) };
  const bounded = await collect(execConfig, { now: '2026-10-16T00:03:00.000Z', previous: padded, auth: async () => {}, read: async path =>
    path.endsWith('/pulls/48') ? { ...pull, draft: true } : reader(path) });
  assert.equal(bounded.changes.length, 50);
  assert.equal(bounded.changes[0].kind, 'state');
  assert.equal(bounded.changes[0].to, 'implementing');
});

test('contract: failed reads never fabricate source changes; recovery is reported separately from progress', async () => {
  const first = await collect(execConfig, { now, auth: async () => {}, read: async path => reader(path) });
  const failed = await collect(execConfig, { now: later, previous: first, auth: async () => {}, read: async () => { throw Error('timeout'); } });
  assert.ok(!failed.changesSincePrevious.some(change => change.progress));
  assert.ok(failed.changesSincePrevious.every(change => change.kind === 'read-error'));
  assert.equal(failed.lastSourceSuccessAt, now);
  const recovered = await collect(execConfig, { now: '2026-10-16T00:02:00.000Z', previous: failed, auth: async () => {}, read: async path => reader(path) });
  assert.ok(recovered.changesSincePrevious.some(change => change.kind === 'read-recovered' && change.progress === false));
  assert.ok(!recovered.changesSincePrevious.some(change => change.kind === 'state'));
  assert.equal(recovered.lastSourceSuccessAt, '2026-10-16T00:02:00.000Z');
});

test('contract: executive readiness is never green by default and orders AGENT before OWNER actions', async () => {
  const pending = path => path.includes('/jobs?') ? [{ total_count: 2, jobs: [job('api'), job('native', 'failure')] }] : reader(path);
  const blocked = await collect(execConfig, { now, auth: async () => {}, read: async path => pending(path) });
  assert.equal(blocked.executive.readiness, 'not-ready');
  assert.equal(blocked.executive.blockers[0].id, 'code');
  assert.match(blocked.executive.blockers[0].reason, /Observed native: failure/);
  assert.equal(blocked.executive.nextAgent.id, 'code');
  assert.match(blocked.executive.nextAgent.action, /Await exact-head CI/);
  assert.equal(blocked.executive.nextOwner.id, 'code');
  assert.equal(blocked.executive.counts.error, 0);
  const failed = await collect(execConfig, { now, auth: async () => { throw Error('x'); }, read: async () => {} });
  assert.equal(failed.executive.readiness, 'unknown');
  assert.equal(failed.executive.counts.error, 1);
  assert.equal(failed.executive.counts.unknown, 1);
  const ready = await collect(execConfig, { now, auth: async () => {}, read: async path => reader(path) });
  assert.equal(ready.executive.readiness, 'ready-for-decision');
  assert.deepEqual(ready.executive.blockers, []);
  assert.equal(ready.executive.lastSourceSuccessAt, now);
  assert.equal(ready.executive.lastCompleteAt, now);
});

test('contract: live config observes Budlark release and website PRs read-only without changing owner-trial gates', () => {
  const ids = Object.fromEntries(sourceConfig.workstreams.map(row => [row.id, row]));
  assert.equal(ids.release.kind, 'pull');
  assert.equal(ids.release.number, 52);
  assert.equal(ids.website.number, 54);
  for (const row of sourceConfig.workstreams) {
    assert.ok(!row.dependencies.some(dep => ['release', 'website'].includes(dep.id)));
  }
  assert.deepEqual(ids.launch.dependencies.map(dep => dep.id), ['candidate', 'native']);
  assert.ok(ids.native.ownerNext && /manual/i.test(ids.native.ownerNext));
  assert.ok(sourceConfig.workstreams.every(row => !/Bloomstep/.test(row.title)));
});
