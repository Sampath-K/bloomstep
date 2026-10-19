import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, mkdir, rename, unlink } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const defaultDirectory = join(root, '.project-status');
const states = ['planned', 'implementing', 'validating', 'blocked', 'review-ready', 'merged', 'released', 'verified', 'unknown'];
const shaPattern = /^[a-f0-9]{40}$/;
const githubBase = 'https://github.com/Sampath-K/bloomstep';

class ReadError extends Error {}

function need(condition) {
  if (!condition) throw new ReadError('GitHub returned incomplete or malformed evidence.');
}

export function validateConfig(config) {
  need(config?.repo === 'Sampath-K/bloomstep');
  need(Number.isInteger(config.maxAgeSeconds) && config.maxAgeSeconds > 0);
  need(Array.isArray(config.workstreams) && config.workstreams.length > 0);
  const ids = new Set();
  for (const row of config.workstreams) {
    need(/^[a-z][a-z0-9-]*$/.test(row.id) && !ids.has(row.id));
    ids.add(row.id);
    need(['pull', 'branch', 'release', 'workflow', 'gate', 'manual', 'site'].includes(row.kind));
    if (row.kind === 'site') {
      need(typeof row.url === 'string' && /^https:\/\/budlark\.com\/[\w./-]*$/.test(row.url));
      need(Array.isArray(row.expect) && row.expect.length > 0 && row.expect.every(text => typeof text === 'string' && text.length > 0 && text.length <= 80));
    }
    need(['title', 'owner', 'nextAction'].every(key => typeof row[key] === 'string' && row[key].length > 0));
    need(['agentNext', 'ownerNext'].every(key => row[key] === undefined || (typeof row[key] === 'string' && row[key].length > 0)));
    need(Array.isArray(row.dependencies));
    if (row.kind === 'pull') need(Number.isSafeInteger(row.number) && row.number > 0);
    if (row.kind === 'branch') need(typeof row.branch === 'string' && /^[\w.-]+$/.test(row.branch));
    if (['pull', 'branch', 'workflow'].includes(row.kind)) {
      need(/^[\w.-]+\.yml$/.test(row.workflow ?? 'ci.yml'));
      need(Array.isArray(row.requiredJobs) && row.requiredJobs.length > 0 && row.requiredJobs.every(name => typeof name === 'string'));
    }
  }
  need(ids.has(config.target));
  if (config.narrative !== undefined) {
    const n = config.narrative, text = value => typeof value === 'string' && value.length > 0 && value.length <= 160;
    need(['release', 'headline', 'candidateReadiness', 'readyReadiness'].every(key => text(n[key])) && (n.pendingNote === undefined || text(n.pendingNote)));
    need(['product', 'system'].every(key => Array.isArray(n[key]) && n[key].length > 0 && n[key].length <= 4 && n[key].every(text)));
    need(n.milestones === undefined && Array.isArray(n.resources) && n.resources.length > 0 && n.resources.length <= 8);
    need(n.notInRelease === undefined || (Array.isArray(n.notInRelease) && n.notInRelease.length <= 3 && n.notInRelease.every(text)));
    const resourceIds = new Set(n.resources.map(r => r.id));
    need(resourceIds.size === n.resources.length);
    const step = s => text(s?.label) && (s.attentionLabel === undefined || text(s.attentionLabel)) &&
      (s.source === undefined ? s.done === undefined : ids.has(s.source) && Array.isArray(s.done) && s.done.length > 0 && s.done.every(state => states.includes(state)));
    for (const r of n.resources) {
      need(/^[a-z][a-z0-9-]*$/.test(r.id) && text(r.name) && text(r.scope));
      need(Array.isArray(r.dependsOn) && r.dependsOn.every(dep => dep !== r.id && resourceIds.has(dep)));
      need(Array.isArray(r.parts) && r.parts.length > 0 && r.parts.length <= 4);
      for (const p of r.parts) need(text(p.label) && Array.isArray(p.prepare) && Array.isArray(p.verify) && p.verify.length > 0 &&
        p.prepare.length + p.verify.length <= 6 && [...p.prepare, ...p.verify].every(step));
    }
    const resources = new Map(n.resources.map(r => [r.id, r])), seen = new Set(), active = new Set();
    (function acyclic(ids) { for (const id of ids) { need(!active.has(id)); if (seen.has(id)) continue; active.add(id); acyclic(resources.get(id).dependsOn); active.delete(id); seen.add(id); } })(resourceIds);
  }
  const visiting = new Set();
  const visited = new Set();
  const byId = new Map(config.workstreams.map(row => [row.id, row]));
  function visit(id) {
    need(!visiting.has(id));
    if (visited.has(id)) return;
    visiting.add(id);
    const row = byId.get(id);
    for (const dep of row.dependencies) {
      need(ids.has(dep.id) && Array.isArray(dep.accept) && dep.accept.length > 0 && dep.accept.every(state => states.includes(state) && state !== 'unknown'));
      visit(dep.id);
    }
    if (row.kind === 'workflow') {
      need(byId.get(row.release)?.kind === 'release');
      visit(row.release);
    }
    visiting.delete(id);
    visited.add(id);
  }
  for (const id of ids) visit(id);
  return config;
}

export function freshness(observedAt, now, maxAgeSeconds) {
  const age = Date.parse(now) - Date.parse(observedAt);
  if (!Number.isFinite(age) || age < 0) return 'unknown';
  return age <= maxAgeSeconds * 1000 ? 'fresh' : 'stale';
}

export function mapJobs(jobs, requiredJobs, verification) {
  const required = requiredJobs.map(name => jobs.filter(job => job.name === name));
  if (required.some(matches => matches.length !== 1)) return 'unknown';
  const selected = required.flat();
  if (selected.some(job => job.status === 'completed' && job.conclusion !== 'success')) return 'blocked';
  if (jobs.some(job => job.status === 'completed' && ['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure', 'stale'].includes(job.conclusion))) return 'blocked';
  if (selected.some(job => job.status !== 'completed') || jobs.some(job => job.status !== 'completed')) return 'validating';
  return verification ? 'verified' : 'review-ready';
}

export function mapPull(pull, checkState) {
  if (pull.merged_at) return 'merged';
  if (pull.state === 'closed') return 'blocked';
  if (pull.draft) return 'implementing';
  return checkState;
}

export function dependencyView(config, rows, now) {
  const byId = new Map(rows.map(row => [row.id, row]));
  const definitions = new Map(config.workstreams.map(row => [row.id, row]));
  const blockers = {};
  function blocked(id) {
    if (blockers[id]) return blockers[id];
    blockers[id] = definitions.get(id).dependencies.filter(dep => {
      const row = byId.get(dep.id);
      return !row || freshness(row.observedAt, now, config.maxAgeSeconds) !== 'fresh' ||
        !dep.accept.includes(row.state) || blocked(dep.id).length > 0;
    }).map(dep => dep.id);
    return blockers[id];
  }
  for (const definition of config.workstreams) blocked(definition.id);
  function pathsTo(id) {
    const deps = blockers[id];
    if (!deps.length) return [[id]];
    return deps.flatMap(dep => pathsTo(dep).map(path => [...path, id]));
  }
  const paths = pathsTo(config.target);
  const longest = Math.max(...paths.map(path => path.length));
  const levels = {};
  function level(id) {
    if (levels[id] !== undefined) return levels[id];
    const deps = definitions.get(id).dependencies;
    levels[id] = deps.length ? 1 + Math.max(...deps.map(dep => level(dep.id))) : 0;
    return levels[id];
  }
  config.workstreams.forEach(row => level(row.id));
  return { blockers, paths: paths.filter(path => path.length === longest), levels };
}

export async function ghRead(path, paginate = false, execute = exec, signal) {
  if (!/^repos\/Sampath-K\/bloomstep\/(?:pulls(?:\/\d+|\?)|branches\/|releases\?|git\/(?:ref\/tags\/|tags\/)|actions\/(?:workflows\/[\w.-]+\.yml\/runs\?|runs\/\d+\/attempts\/\d+\/jobs\?))/.test(path) ||
      /[\r\n\\]/.test(path)) throw new ReadError('Unsupported GitHub read path.');
  try {
    const args = ['api', '--hostname', 'github.com', '--method', 'GET', path];
    if (paginate) args.push('--paginate', '--slurp');
    const { stdout } = await execute('gh', args, { cwd: root, timeout: 20000, maxBuffer: 8 * 1024 * 1024, windowsHide: true, signal });
    return JSON.parse(stdout);
  } catch (error) {
    if (error.killed || error.code === 'ETIMEDOUT') throw new ReadError('GitHub read timed out (20-second limit).');
    const status = /HTTP (401|403|404|429|5\d\d)\b/.exec(error.stderr ?? '')?.[1];
    if (status) {
      const failure = new ReadError(`GitHub GET unavailable (HTTP ${status}; source missing, inaccessible or service unavailable).`);
      if (status === '429' || (status === '403' && /rate.limit/i.test(error.stderr ?? ''))) failure.retryAfterSeconds = 900;
      throw failure;
    }
    throw new ReadError('GitHub read failed (API, permission, transport or invalid JSON).');
  }
}

async function authenticate(signal) {
  await exec('gh', ['auth', 'status', '--hostname', 'github.com', '--active'], {
    cwd: root, timeout: 20000, maxBuffer: 1024 * 1024, windowsHide: true, signal,
  });
}

export async function readSite(url, signal) {
  if (!/^https:\/\/budlark\.com\/[\w./-]*$/.test(url)) throw new ReadError('Unsupported live site read.');
  const timeout = AbortSignal.timeout(20000);
  const response = await fetch(url, { method: 'GET', redirect: 'follow', signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
    headers: { 'user-agent': 'budlark-private-status/1 (read-only)' } });
  if (!/^https:\/\/(www\.)?budlark\.com\//.test(response.url || url)) throw new ReadError('Live site redirected outside budlark.com.');
  const body = await response.text();
  return { status: response.status, body: body.slice(0, 4 * 1024 * 1024) };
}

async function siteEvidence(definition, fetchSite) {
  let page;
  try { page = await fetchSite(definition.url); } catch { throw new ReadError('Live site read failed (DNS, TLS, timeout or transport).'); }
  if (page?.status !== 200 || typeof page.body !== 'string') throw new ReadError(`Live site read failed (HTTP ${Number(page?.status) || 'unknown'}).`);
  const shown = definition.expect.every(text => page.body.includes(text));
  return {
    state: shown ? 'verified' : 'planned',
    evidence: [{ title: `Live page ${definition.url}`, url: definition.url }],
    detail: shown ? 'Live public page read back with the expected content.' : 'Live public page does not yet show the expected content.',
  };
}

function listPages(pages, key) {
  need(Array.isArray(pages) && pages.length > 0);
  if (!key) {
    need(pages.every(page => Array.isArray(page)));
    return pages.flat();
  }
  need(pages.every(page => Number.isInteger(page.total_count) && page.total_count >= 0 && Array.isArray(page[key])));
  const rows = pages.flatMap(page => page[key]);
  need(pages.every(page => page.total_count === rows.length));
  return rows;
}

function evidence(title, url) {
  need(typeof url === 'string' && url.startsWith(`${githubBase}/`) && !/[\s<>]/.test(url));
  return { title, url };
}

async function workflowEvidence(definition, sha, read, releaseTag = null) {
  need(shaPattern.test(sha));
  const workflow = definition.workflow ?? 'ci.yml';
  const branchQuery = releaseTag ? `&branch=${encodeURIComponent(releaseTag)}` : '';
  const runs = listPages(await read(`repos/Sampath-K/bloomstep/actions/workflows/${workflow}/runs?head_sha=${sha}&event=push${branchQuery}&per_page=100`, true), 'workflow_runs');
  need(runs.length > 0 && runs.every(run => run.head_sha === sha && (!releaseTag || run.head_branch === releaseTag) &&
    Number.isSafeInteger(run.id) && Number.isSafeInteger(run.run_attempt)));
  const run = runs.sort((a, b) => b.id - a.id)[0];
  const jobs = listPages(await read(`repos/Sampath-K/bloomstep/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100`, true), 'jobs');
  need(jobs.length > 0 && jobs.every(job => typeof job.name === 'string' &&
    ['queued', 'in_progress', 'completed', 'waiting', 'pending', 'requested'].includes(job.status) &&
    (job.status !== 'completed' || ['success', 'failure', 'cancelled', 'skipped', 'neutral', 'timed_out', 'action_required', 'startup_failure', 'stale'].includes(job.conclusion))));
  const state = mapJobs(jobs, definition.requiredJobs, definition.kind === 'workflow');
  if (state === 'unknown') throw new ReadError('Required exact-head workflow jobs are missing or ambiguous.');
  return {
    state, sha, runId: run.id,
    checks: jobs.map(job => ({ name: job.name, status: job.status, conclusion: job.conclusion })),
    evidence: [evidence(`Exact-head ${workflow} run ${run.id}, attempt ${run.run_attempt}`, run.html_url)],
  };
}

async function pullEvidence(definition, pull, read) {
  need(pull && ['open', 'closed'].includes(pull.state) && typeof pull.draft === 'boolean' && shaPattern.test(pull.head?.sha));
  const workflow = await workflowEvidence(definition, pull.head.sha, read);
  return {
    ...workflow, state: mapPull(pull, workflow.state), pullNumber: pull.number,
    evidence: [evidence(`PR #${pull.number}`, pull.html_url), ...workflow.evidence],
    detail: pull.merged_at ? 'Merged source only; not release or verification evidence.' :
      pull.state === 'closed' ? 'PR closed without merge.' : 'Readiness describes the configured engineering workflow, not approval or all product gates.',
  };
}

async function observe(definition, read, releaseRows) {
  const base = 'repos/Sampath-K/bloomstep';
  if (definition.kind === 'pull') {
    return pullEvidence(definition, await read(`${base}/pulls/${definition.number}`), read);
  }
  if (definition.kind === 'branch') {
    const pulls = listPages(await read(`${base}/pulls?head=Sampath-K:${encodeURIComponent(definition.branch)}&state=all&per_page=100`, true));
    need(pulls.every(pull => pull.head?.ref === definition.branch));
    const open = pulls.filter(pull => pull.state === 'open');
    need(open.length <= 1);
    const selected = open[0] ?? pulls.filter(pull => pull.merged_at).sort((a, b) => Date.parse(b.merged_at) - Date.parse(a.merged_at))[0];
    if (selected) return pullEvidence(definition, selected, read);
    const branch = await read(`${base}/branches/${encodeURIComponent(definition.branch)}`);
    need(shaPattern.test(branch.commit?.sha));
    return {
      state: 'implementing', sha: branch.commit.sha, evidence: [evidence('Remote branch (not agent activity)', `${githubBase}/tree/${encodeURIComponent(definition.branch)}`)],
      detail: 'A remote branch exists, but no open or merged PR was found. Actual agent activity and handoff are unknown.',
    };
  }
  if (definition.kind === 'release') {
    const releases = listPages(await read(`${base}/releases?per_page=100`, true));
    need(releases.every(release => typeof release.draft === 'boolean'));
    const release = releases.filter(release => !release.draft && release.published_at)
      .sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at))[0];
    need(release && typeof release.tag_name === 'string' && Number.isFinite(Date.parse(release.published_at)));
    let { object } = await read(`${base}/git/ref/tags/${encodeURIComponent(release.tag_name)}`);
    for (let depth = 0; object?.type === 'tag' && depth < 5; depth++) {
      need(shaPattern.test(object.sha));
      ({ object } = await read(`${base}/git/tags/${object.sha}`));
    }
    need(object?.type === 'commit' && shaPattern.test(object.sha));
    return {
      state: 'released', sha: object.sha, tag: release.tag_name, publishedAt: release.published_at,
      evidence: [evidence(`Published ${release.tag_name}`, release.html_url)],
      detail: 'Publication and immutable tag resolution only; no native or public-launch verification.',
    };
  }
  if (definition.kind === 'workflow') {
    const release = releaseRows.get(definition.release);
    if (release?.state !== 'released') throw new ReadError('Published release source is unavailable; exact-release verification cannot be read.');
    return workflowEvidence(definition, release.sha, read, release.tag);
  }
  throw new ReadError('No live source configured.');
}

export async function collect(config, { now = new Date().toISOString(), previous = null, auth = authenticate, read = ghRead, fetchSite = readSite } = {}) {
  validateConfig(config);
  need(Number.isFinite(Date.parse(now)));
  const rows = new Map();
  let authError = false;
  try { await auth(); } catch { authError = true; }
  const previousRows = new Map((previous?.workstreams ?? []).map(row => [row.id, row]));
  function failed(definition, error) {
    const old = previousRows.get(definition.id);
    const lastKnown = old?.observedAt && old.state !== 'unknown'
      ? { state: old.state, observedAt: old.observedAt, evidence: old.evidence, sha: old.sha, tag: old.tag }
      : old?.lastKnown ?? null;
    return {
      id: definition.id, state: 'unknown', observedAt: null, evidence: [], lastKnown,
      error: error instanceof ReadError ? error.message : 'GitHub read failed (API, timeout, permission or malformed response).',
      retryAfterSeconds: error instanceof ReadError ? error.retryAfterSeconds ?? 0 : 0,
    };
  }
  async function capture(definition) {
    if (['gate', 'manual'].includes(definition.kind)) return;
    try {
      if (definition.kind === 'site') {
        rows.set(definition.id, { id: definition.id, ...await siteEvidence(definition, fetchSite), observedAt: now, lastKnown: null, error: null });
        return;
      }
      if (authError) throw new ReadError('GitHub authentication unavailable. Run gh auth status locally.');
      const result = await observe(definition, read, rows);
      rows.set(definition.id, { id: definition.id, ...result, observedAt: now, lastKnown: null, error: null });
    } catch (error) { rows.set(definition.id, failed(definition, error)); }
  }
  // Release-dependent workflows read only this collection's resolved immutable tag.
  await Promise.all(config.workstreams.filter(row => row.kind !== 'workflow').map(capture));
  await Promise.all(config.workstreams.filter(row => row.kind === 'workflow').map(capture));
  for (const definition of config.workstreams.filter(row => ['gate', 'manual'].includes(row.kind))) {
    rows.set(definition.id, {
      id: definition.id, state: definition.kind === 'gate' ? 'planned' : 'unknown',
      observedAt: definition.kind === 'gate' ? now : null, evidence: [], lastKnown: null,
      error: definition.kind === 'manual' ? 'No live evidence source configured; current state is unknown.' : null,
    });
  }
  const workstreams = config.workstreams.map(definition => rows.get(definition.id));
  const graph = dependencyView(config, workstreams, now);
  for (const definition of config.workstreams.filter(row => row.kind === 'gate')) {
    if (graph.blockers[definition.id].length) rows.get(definition.id).state = 'blocked';
  }
  const sourceRows = config.workstreams.filter(row => !['manual', 'gate'].includes(row.kind)).map(row => rows.get(row.id));
  const errors = sourceRows.filter(row => row.error).length;
  const changesSincePrevious = previous ? detectChanges(config, previous, workstreams, now) : [];
  const snapshot = {
    schemaVersion: 1, collectedAt: now,
    lastCompleteAt: errors === 0 ? now : previous?.lastCompleteAt ?? null,
    lastSourceSuccessAt: sourceRows.some(row => !row.error && row.observedAt) ? now : previous?.lastSourceSuccessAt ?? null,
    collectionState: errors === 0 ? 'complete' : errors === sourceRows.length ? 'failed' : 'partial',
    agentStatus: 'unavailable',
    retryAfterSeconds: Math.max(0, ...sourceRows.map(row => row.retryAfterSeconds ?? 0)),
    agentDetail: 'No supported agent-session API is connected. GitHub evidence is point-in-time, not real-time agent progress.',
    changeBaseline: !previous, changesSincePrevious,
    changes: [...changesSincePrevious, ...(Array.isArray(previous?.changes) ? previous.changes : [])].slice(0, 50),
    config, workstreams, graph: dependencyView(config, workstreams, now),
  };
  snapshot.executive = executiveSummary(config, snapshot);
  if (config.narrative) snapshot.narrative = releaseNarrative(config, snapshot);
  return snapshot;
}

// Only evidence differences count; collection timestamps, polling and unchanged reads never do.
export function detectChanges(config, previous, workstreams, now) {
  const previousRows = new Map((previous.workstreams ?? []).map(row => [row.id, row]));
  const kinds = new Map(config.workstreams.map(row => [row.id, row.kind]));
  const changes = [];
  for (const row of workstreams) {
    if (['gate', 'manual'].includes(kinds.get(row.id))) continue;
    const prior = previousRows.get(row.id);
    const add = (kind, from, to, progress, name) => changes.push({
      id: row.id, kind, ...(name ? { name } : {}), from: from ?? null, to: to ?? null, progress,
      observedAt: now, evidence: row.evidence?.[0]?.url ?? prior?.evidence?.[0]?.url ?? prior?.lastKnown?.evidence?.[0]?.url ?? null,
    });
    if (!prior) { add('added', null, row.state, false); continue; }
    if (row.error) {
      if (!prior.error) add('read-error', prior.state, 'unknown', false);
      continue;
    }
    if (prior.error) add('read-recovered', 'unknown', row.state, false);
    const base = prior.error ? prior.lastKnown : prior;
    if (!base) continue;
    if (base.state !== row.state) add('state', base.state, row.state, true);
    if (base.sha && row.sha && base.sha !== row.sha) add('sha', base.sha, row.sha, true);
    if ((base.tag || row.tag) && base.tag !== row.tag) add('release', base.tag, row.tag, true);
    if (base.sha === row.sha && Array.isArray(base.checks) && Array.isArray(row.checks)) {
      const outcome = job => job ? `${job.status}${job.conclusion ? `/${job.conclusion}` : ''}` : 'absent';
      const before = new Map(base.checks.map(job => [job.name, job]));
      const after = new Map(row.checks.map(job => [job.name, job]));
      for (const name of new Set([...before.keys(), ...after.keys()])) {
        const from = outcome(before.get(name)), to = outcome(after.get(name));
        if (from !== to) add('check', from, to, true, name);
      }
    }
  }
  return changes;
}

export function executiveSummary(config, snapshot) {
  const definitions = new Map(config.workstreams.map(row => [row.id, row]));
  const rows = new Map(snapshot.workstreams.map(row => [row.id, row]));
  const { blockers, levels } = snapshot.graph;
  const blocking = new Set();
  (function walk(id) { for (const dep of blockers[id] ?? []) { if (!blocking.has(dep)) { blocking.add(dep); walk(dep); } } })(config.target);
  const list = [...blocking].map(id => {
    const row = rows.get(id), definition = definitions.get(id);
    const fresh = row.observedAt && freshness(row.observedAt, snapshot.collectedAt, config.maxAgeSeconds) === 'fresh';
    const failedJobs = (row.checks ?? []).filter(job => job.status === 'completed' && job.conclusion !== 'success' &&
      ((definition.requiredJobs ?? []).includes(job.name) || !['skipped', 'neutral'].includes(job.conclusion)));
    const pendingJobs = (row.checks ?? []).filter(job => job.status !== 'completed');
    const observed = failedJobs.length ? ` Observed ${failedJobs.map(job => `${job.name}: ${job.conclusion}`).join('; ')}.` :
      pendingJobs.length ? ` ${pendingJobs.length} job(s) pending.` : '';
    const reason = row.error ? row.error : !fresh ? 'Evidence is stale or unavailable.' :
      blockers[id].length ? `Waiting on ${blockers[id].map(dep => definitions.get(dep).title).join(', ')}.` : `Current state is ${row.state}.${observed}`;
    return { id, title: definition.title, state: row.state, owner: definition.owner, reason, root: blockers[id].length === 0,
      known: !row.error && row.state !== 'unknown' && Boolean(fresh), level: levels[id],
      agentNext: definition.agentNext ?? definition.nextAction, ownerNext: definition.ownerNext ?? null,
      evidence: row.evidence?.[0]?.url ?? row.lastKnown?.evidence?.[0]?.url ?? null };
  }).sort((a, b) => Number(b.root) - Number(a.root) || a.level - b.level);
  const readiness = snapshot.collectionState === 'failed' ? 'unknown' : list.length === 0 ? 'ready-for-decision' :
    list.some(row => row.root && row.known) ? 'not-ready' : 'unknown';
  const agent = list.find(row => row.agentNext), owner = list.find(row => row.ownerNext);
  // Only the target and its transitive prerequisites gate the decision; everything else is context.
  const gating = new Set([config.target]);
  (function closure(id) { for (const dep of definitions.get(id).dependencies) { gating.add(dep.id); closure(dep.id); } })(config.target);
  const tally = include => {
    const subset = snapshot.workstreams.filter(include);
    return {
      error: subset.filter(row => row.error && !['manual', 'gate'].includes(definitions.get(row.id).kind)).length,
      unknown: subset.filter(row => row.state === 'unknown').length,
      blocked: subset.filter(row => row.state === 'blocked').length,
    };
  };
  return {
    target: config.target, targetTitle: definitions.get(config.target).title, readiness,
    blockers: list.map(({ known, level, ...row }) => row),
    nextAgent: agent ? { id: agent.id, title: agent.title, action: agent.agentNext } : null,
    nextOwner: owner ? { id: owner.id, title: owner.title, action: owner.ownerNext } : null,
    counts: tally(row => gating.has(row.id)),
    nonGating: tally(row => !gating.has(row.id)),
    lastSourceSuccessAt: snapshot.lastSourceSuccessAt, lastCompleteAt: snapshot.lastCompleteAt, collectionState: snapshot.collectionState,
  };
}

const plainState = { planned: 'next', implementing: 'in progress', validating: 'checks running', blocked: 'needs attention',
  'review-ready': 'passing', merged: 'approved', released: 'released', verified: 'verified', unknown: 'not yet evidenced' };

// Executive one-slide view: plain-language milestones only; no links, commits, jobs or workstream internals.
export function releaseNarrative(config, snapshot) {
  const n = config.narrative;
  const definitions = new Map(config.workstreams.map(row => [row.id, row]));
  const rows = new Map(snapshot.workstreams.map(row => [row.id, row]));
  const failed = snapshot.collectionState === 'failed';
  const stepStatus = step => {
    if (failed) return 'unknown';
    if (!step.source) return 'not-evidenced';
    const row = rows.get(step.source), manual = ['manual', 'gate'].includes(definitions.get(step.source).kind);
    const fresh = row?.observedAt && freshness(row.observedAt, snapshot.collectedAt, config.maxAgeSeconds) === 'fresh';
    return !row || (row.error && !manual) || (!manual && !fresh) ? 'unknown' :
      step.done.includes(row.state) ? 'done' : (snapshot.graph.blockers[step.source] ?? []).length ? 'waiting' :
      row.state === 'unknown' ? 'not-evidenced' : row.state === 'blocked' ? 'attention' : row.state === 'planned' ? 'next' : 'in-progress';
  };
  // Live verification supersedes preparation; a part is done only when every verify step is evidenced.
  const evaluate = parts => parts.map(p => {
    const prepare = p.prepare.map(s => ({ ...s, status: stepStatus(s) })), verify = p.verify.map(s => ({ ...s, status: stepStatus(s) }));
    const done = verify.every(s => s.status === 'done'), prepared = done || (prepare.length > 0 && prepare.every(s => s.status === 'done'));
    return { label: p.label, steps: [...prepare, ...verify], prepare, verify, done, prepared };
  });
  const summarize = parts => {
    const steps = parts.flatMap(p => p.steps);
    return steps.some(s => s.status === 'unknown') ? { tone: 'unknown', label: 'Unknown' } :
      parts.every(p => p.done) ? { tone: 'ready', label: 'Ready' } :
      steps.some(s => s.status === 'attention') ? { tone: 'attention', label: 'Needs attention' } :
      parts.every(p => p.prepared) ? { tone: 'prepared', label: 'Prepared; live check pending' } :
      steps.some(s => ['done', 'in-progress', 'next'].includes(s.status)) ? { tone: 'in-progress', label: 'In preparation' } :
      { tone: 'none', label: 'No evidence yet' };
  };
  const evaluated = new Map(n.resources.map(r => [r.id, { resource: r, parts: evaluate(r.parts) }]));
  const ready = new Map([...evaluated].map(([id, e]) => [id, summarize(e.parts).tone === 'ready']));
  const resources = n.resources.map(r => {
    const { parts } = evaluated.get(r.id), status = summarize(parts);
    const waitingOn = r.dependsOn.filter(dep => !ready.get(dep)).map(dep => evaluated.get(dep).resource.name);
    if (status.tone === 'prepared' && waitingOn.length) status.label = `Prepared; waits for ${waitingOn.join(', ')}`;
    const open = parts.find(p => !p.done), step = open && (open.prepared ? open.verify : open.steps).find(s => s.status !== 'done');
    const next = status.tone === 'unknown' ? 'Evidence could not be read' : !open ? null :
      `${parts.length > 1 ? `${open.label}: ` : ''}${step.label}`;
    return { id: r.id, name: r.name, scope: r.scope, ...status, next, waitingOn,
      parts: parts.map(p => { const part = summarize([p]); return { label: p.label, tone: part.tone, status: part.label }; }) };
  });
  const allSteps = [...evaluated.values()].flatMap(e => e.parts.flatMap(p => p.steps));
  const labels = new Map();
  for (const s of allSteps) if (s.source && !labels.has(s.source)) labels.set(s.source, s.label);
  const recent = (snapshot.changes ?? []).filter(change => change.kind === 'state' && change.progress && labels.has(change.id))
    .slice(0, 3).map(change => ({ text: `${labels.get(change.id)}: ${plainState[change.from] ?? 'unknown'} → ${plainState[change.to] ?? 'unknown'}`, observedAt: change.observedAt }));
  const attention = [...new Set(allSteps.filter(s => s.status === 'attention').map(s => s.attentionLabel ?? s.label.toLowerCase()))];
  const unknown = resources.filter(r => r.tone === 'unknown').map(r => r.name);
  const readiness = failed ? { tone: 'unknown', label: 'Readiness unknown: sources could not be read' } :
    resources.every(r => r.tone === 'ready') ? { tone: 'ready', label: n.readyReadiness } :
    attention.length ? { tone: 'not-ready', label: `Not ready: ${attention.join(', ')} ${attention.length > 1 ? 'need' : 'needs'} attention${n.pendingNote ? `; ${n.pendingNote}` : ''}` } :
    unknown.length ? { tone: 'unknown', label: `Readiness unknown: ${unknown.join(', ')} could not be verified` } :
    { tone: 'in-progress', label: n.candidateReadiness };
  return { release: n.release, headline: n.headline, readiness, product: n.product, system: n.system, resources,
    resourcesReady: { ready: resources.filter(r => r.tone === 'ready').length, total: resources.length },
    notInRelease: n.notInRelease ?? [], recent,
    lastSourceSuccessAt: snapshot.lastSourceSuccessAt, collectionState: snapshot.collectionState, collectedAt: snapshot.collectedAt };
}

async function writeJson(directory, name, snapshot) {
  await mkdir(directory, { recursive: true });
  const temporary = join(directory, `${name}.${process.pid}.${Date.now()}.tmp`);
  try {
    await writeFile(temporary, JSON.stringify(snapshot, null, 2), { flag: 'wx', mode: 0o600 });
    await rename(temporary, join(directory, name));
  } catch (error) {
    try { await unlink(temporary); } catch (cleanupError) { if (cleanupError.code !== 'ENOENT') throw cleanupError; }
    throw error;
  }
}

export async function writeSnapshot(directory, snapshot) {
  await writeJson(directory, 'snapshot.json', snapshot);
}

export function startPolling({ seconds, refresh, publish, clock = () => new Date().toISOString(),
  schedule = setTimeout, cancel = clearTimeout }) {
  if (!Number.isInteger(seconds) || seconds < 60 || seconds > 3600) throw Error('Polling interval must be 60 to 3600 seconds.');
  const controller = new AbortController();
  let timer, stopped = false, failures = 0, running;
  let state = { mode: 'polling', intervalSeconds: seconds, status: 'starting', lastAttemptAt: null,
    lastFinishedAt: null, lastSourceSuccessAt: null, lastCompleteAt: null, nextAttemptAt: null, errors: [] };
  function queue(delay) {
    timer = schedule(() => {
      running = tick();
      running.catch(() => { console.error('Polling status could not be persisted; automatic collection stopped. Check local file permissions and restart.'); });
      return running;
    }, delay);
  }
  async function tick() {
    if (stopped) return;
    state = { ...state, status: 'collecting', lastAttemptAt: clock(), nextAttemptAt: null };
    try {
      await publish(state);
      if (stopped) return;
      const snapshot = await refresh(controller.signal);
      if (stopped) return;
      const complete = snapshot.collectionState === 'complete';
      failures = complete ? 0 : failures + 1;
      const delay = Math.max(seconds * 1000 * 2 ** Math.min(failures, 3), (snapshot.retryAfterSeconds ?? 0) * 1000);
      state = { ...state, status: snapshot.collectionState, lastFinishedAt: clock(),
        lastSourceSuccessAt: snapshot.collectionState !== 'failed' && snapshot.workstreams.some(row => row.observedAt) ? snapshot.collectedAt : state.lastSourceSuccessAt,
        lastCompleteAt: snapshot.lastCompleteAt ?? state.lastCompleteAt,
        errors: snapshot.workstreams.filter(row => row.error).map(row => row.error),
        nextAttemptAt: new Date(Date.parse(clock()) + delay).toISOString() };
      await publish(state);
      if (!stopped) queue(delay);
    } catch {
      if (stopped) return;
      failures++;
      const delay = seconds * 1000 * 2 ** Math.min(failures, 3);
      state = { ...state, status: 'failed', lastFinishedAt: clock(),
        errors: ['Local collection or status persistence failed; snapshot may be stale. Check local files and gh access.'],
        nextAttemptAt: new Date(Date.parse(clock()) + delay).toISOString() };
      console.error(state.errors[0]);
      await publish(state);
      if (!stopped) queue(delay);
    }
  }
  running = tick();
  return {
    ready: running,
    async stop() {
      stopped = true;
      if (timer !== undefined) cancel(timer);
      controller.abort();
      await running;
      state = { ...state, status: 'stopped', nextAttemptAt: null };
      await publish(state);
    },
  };
}

export async function startServer({ port = 8791, directory = defaultDirectory } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw Error('Port must be an integer from 0 to 65535.');
  const html = await readFile(new URL('./index.html', import.meta.url));
  const server = createServer(async (request, response) => {
    const origin = `http://127.0.0.1:${server.address().port}`;
    const headers = {
      'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
      'Referrer-Policy': 'no-referrer',
    };
    const send = (status, body, type = 'text/plain; charset=utf-8') => {
      response.writeHead(status, { ...headers, 'Content-Type': type });
      response.end(body);
    };
    if (request.headers.host !== origin.slice(7) || (request.headers.origin && request.headers.origin !== origin)) return send(403, 'Loopback same-origin requests only.');
    if (request.method !== 'GET') return send(405, 'Read-only server. Run the explicit local collect command to refresh sources.');
    if (/^\/(?:index\.html)?(?:\?scoutTheme=(?:light|dark))?$/.test(request.url)) return send(200, html, 'text/html; charset=utf-8');
    if (!['/snapshot.json', '/polling.json'].includes(request.url)) return send(404, 'Not found.');
    try { send(200, await readFile(join(directory, request.url === '/polling.json' ? 'polling.json' : 'snapshot.json')), 'application/json; charset=utf-8'); }
    catch (error) { send(503, JSON.stringify({ error: error.code === 'ENOENT' ? 'No snapshot yet. Run the local collect command.' : 'Snapshot read failed. Check local file permissions.' }), 'application/json; charset=utf-8'); }
  });
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  return server;
}

async function refreshLocal(signal) {
    const config = JSON.parse(await readFile(new URL('./sources.json', import.meta.url), 'utf8'));
    let previous = null;
    try { previous = JSON.parse(await readFile(join(defaultDirectory, 'snapshot.json'), 'utf8')); }
    catch (error) {
      if (error.code !== 'ENOENT') throw Error('Existing snapshot is unreadable or corrupt; preserve it and correct it before collecting.');
    }
    const snapshot = await collect(config, { previous, auth: () => authenticate(signal),
      read: (path, paginate) => ghRead(path, paginate, exec, signal) });
    if (signal?.aborted) throw Error('Collection stopped.');
    await writeSnapshot(defaultDirectory, snapshot);
    return snapshot;
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'collect' && args.length === 0) {
    const snapshot = await refreshLocal();
    console.log(`Collection ${snapshot.collectionState}: ${join(defaultDirectory, 'snapshot.json')}`);
    if (snapshot.collectionState !== 'complete') process.exitCode = 1;
    return;
  }
  if (command === 'serve') {
    const options = new Map();
    for (let i = 0; i < args.length; i += 2) {
      if (!['--port', '--poll-seconds'].includes(args[i]) || options.has(args[i]) || !/^\d+$/.test(args[i + 1] ?? '')) throw Error('Expected --port N and/or --poll-seconds N.');
      options.set(args[i], Number(args[i + 1]));
    }
    const seconds = options.get('--poll-seconds');
    if (seconds !== undefined && (seconds < 60 || seconds > 3600)) throw Error('Polling interval must be 60 to 3600 seconds.');
    const server = await startServer({ port: options.get('--port') ?? 8791 });
    let polling;
    if (seconds !== undefined) {
      polling = startPolling({ seconds, refresh: refreshLocal, publish: state => writeJson(defaultDirectory, 'polling.json', state) });
      polling.ready.catch(error => { console.error(`Polling persistence failed: ${error.message}`); process.exitCode = 1; server.close(); });
    } else {
      await writeJson(defaultDirectory, 'polling.json', { mode: 'manual', status: 'disabled' });
    }
    let stopping = false;
    const stop = async () => {
      if (stopping) return;
      stopping = true;
      try { if (polling) await polling.stop(); }
      catch { console.error('Could not persist stopped polling status.'); process.exitCode = 1; }
      server.close();
    };
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    console.log(`Private project status: http://127.0.0.1:${server.address().port}/ (Ctrl+C to stop)`);
    return;
  }
  throw Error('Usage: node tool\\project-status\\status.mjs collect | serve [--port 8791] [--poll-seconds 60]');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
