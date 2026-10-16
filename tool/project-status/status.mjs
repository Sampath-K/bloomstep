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
    need(['pull', 'branch', 'release', 'workflow', 'gate', 'manual'].includes(row.kind));
    need(['title', 'owner', 'nextAction'].every(key => typeof row[key] === 'string' && row[key].length > 0));
    need(Array.isArray(row.dependencies));
    if (row.kind === 'pull') need(Number.isSafeInteger(row.number) && row.number > 0);
    if (row.kind === 'branch') need(typeof row.branch === 'string' && /^[\w.-]+$/.test(row.branch));
    if (['pull', 'branch', 'workflow'].includes(row.kind)) {
      need(/^[\w.-]+\.yml$/.test(row.workflow ?? 'ci.yml'));
      need(Array.isArray(row.requiredJobs) && row.requiredJobs.length > 0 && row.requiredJobs.every(name => typeof name === 'string'));
    }
  }
  need(ids.has(config.target));
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

export async function ghRead(path, paginate = false, execute = exec) {
  if (!/^repos\/Sampath-K\/bloomstep\/(?:pulls(?:\/\d+|\?)|branches\/|releases\?|git\/(?:ref\/tags\/|tags\/)|actions\/(?:workflows\/[\w.-]+\.yml\/runs\?|runs\/\d+\/attempts\/\d+\/jobs\?))/.test(path) ||
      /[\r\n\\]/.test(path)) throw new ReadError('Unsupported GitHub read path.');
  try {
    const args = ['api', '--hostname', 'github.com', '--method', 'GET', path];
    if (paginate) args.push('--paginate', '--slurp');
    const { stdout } = await execute('gh', args, { cwd: root, timeout: 20000, maxBuffer: 8 * 1024 * 1024, windowsHide: true });
    return JSON.parse(stdout);
  } catch (error) {
    if (error.killed || error.code === 'ETIMEDOUT') throw new ReadError('GitHub read timed out (20-second limit).');
    const status = /HTTP (401|403|404|429|5\d\d)\b/.exec(error.stderr ?? '')?.[1];
    if (status) throw new ReadError(`GitHub GET unavailable (HTTP ${status}; source missing, inaccessible or service unavailable).`);
    throw new ReadError('GitHub read failed (API, permission, transport or invalid JSON).');
  }
}

async function authenticate() {
  await exec('gh', ['auth', 'status', '--hostname', 'github.com', '--active'], {
    cwd: root, timeout: 20000, maxBuffer: 1024 * 1024, windowsHide: true,
  });
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

export async function collect(config, { now = new Date().toISOString(), previous = null, auth = authenticate, read = ghRead } = {}) {
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
    };
  }
  async function capture(definition) {
    if (['gate', 'manual'].includes(definition.kind)) return;
    try {
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
  return {
    schemaVersion: 1, collectedAt: now,
    lastCompleteAt: errors === 0 ? now : previous?.lastCompleteAt ?? null,
    collectionState: errors === 0 ? 'complete' : errors === sourceRows.length ? 'failed' : 'partial',
    agentStatus: 'unavailable',
    agentDetail: 'No supported agent-session API is connected. GitHub evidence is point-in-time, not real-time agent progress.',
    config, workstreams, graph: dependencyView(config, workstreams, now),
  };
}

export async function writeSnapshot(directory, snapshot) {
  await mkdir(directory, { recursive: true });
  const temporary = join(directory, `snapshot.${process.pid}.${Date.now()}.tmp`);
  try {
    await writeFile(temporary, JSON.stringify(snapshot, null, 2), { flag: 'wx', mode: 0o600 });
    await rename(temporary, join(directory, 'snapshot.json'));
  } catch (error) {
    try { await unlink(temporary); } catch (cleanupError) { if (cleanupError.code !== 'ENOENT') throw cleanupError; }
    throw error;
  }
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
    if (request.url !== '/snapshot.json') return send(404, 'Not found.');
    try { send(200, await readFile(join(directory, 'snapshot.json')), 'application/json; charset=utf-8'); }
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

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'collect' && args.length === 0) {
    const config = JSON.parse(await readFile(new URL('./sources.json', import.meta.url), 'utf8'));
    let previous = null;
    try { previous = JSON.parse(await readFile(join(defaultDirectory, 'snapshot.json'), 'utf8')); }
    catch (error) {
      if (error.code !== 'ENOENT') throw Error('Existing snapshot is unreadable or corrupt; preserve it and correct it before collecting.');
    }
    const snapshot = await collect(config, { previous });
    await writeSnapshot(defaultDirectory, snapshot);
    console.log(`Collection ${snapshot.collectionState}: ${join(defaultDirectory, 'snapshot.json')}`);
    if (snapshot.collectionState !== 'complete') process.exitCode = 1;
    return;
  }
  if (command === 'serve' && (args.length === 0 || (args.length === 2 && args[0] === '--port' && /^\d+$/.test(args[1])))) {
    const server = await startServer({ port: args.length ? Number(args[1]) : 8791 });
    console.log(`Private project status: http://127.0.0.1:${server.address().port}/ (Ctrl+C to stop)`);
    return;
  }
  throw Error('Usage: node tool\\project-status\\status.mjs collect | serve [--port 8791]');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
