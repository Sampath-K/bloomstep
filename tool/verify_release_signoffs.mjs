#!/usr/bin/env node
// Release sign-off gate: every required role must explicitly approve the exact
// candidate commit, source tree and installer SHA-256 before a release stage.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SIGNOFF_PATH_PREFIXES = ['release/signoffs/', 'release/evidence/', 'release/reviews/', 'release/owner/'];
const VERDICTS = new Set(['APPROVED', 'APPROVED_WITH_ACCEPTED_RISK', 'CHANGES_REQUIRED']);
const SEVERITIES = new Set(['critical', 'high', 'medium', 'low']);
const RESOLUTIONS = new Set(['FIXED', 'ACCEPTED_RISK', 'OPEN']);
const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const ISO_SHAPE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
const DIGITS = /^[1-9]\d{0,19}$/;
const ISO = { test: (s) => typeof s === 'string' && ISO_SHAPE.test(s) && !Number.isNaN(Date.parse(s))
  && new Date(s).toISOString().slice(0, 19) === s.slice(0, 19) };

function gate(condition, message) {
  if (!condition) throw new Error(`Release sign-off gate: ${message}`);
}

const nonEmpty = (v) => typeof v === 'string' && v.trim().length > 0;

export const realGit = (cwd) => ({
  tree: (rev) => execFileSync('git', ['rev-parse', `${rev}^{tree}`], { cwd, encoding: 'utf8' }).trim(),
  changedFiles: (from, to) => execFileSync('git', ['diff', '--name-only', from, to], { cwd, encoding: 'utf8' })
    .split(/\r?\n/).filter(Boolean),
  isAncestor: (a, b) => {
    try { execFileSync('git', ['merge-base', '--is-ancestor', a, b], { cwd, stdio: 'ignore' }); return true; } catch { return false; }
  },
});

export function loadRoles(root) {
  const registry = JSON.parse(readFileSync(join(root, 'release', 'roles.json'), 'utf8'));
  gate(registry.schema === 'budlark-release-roles-v1' && Array.isArray(registry.roles), 'invalid release/roles.json');
  return registry;
}

function readRecord(file) {
  try { return JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); } catch (e) {
    throw new Error(`Release sign-off gate: Malformed sign-off record ${file}: ${e.message}`);
  }
}

function checkFinding(role, f, candidate, git) {
  gate(f && nonEmpty(f.id) && SEVERITIES.has(f.severity) && nonEmpty(f.description) && RESOLUTIONS.has(f.resolution),
    `${role} has a malformed finding ${f?.id ?? ''}`);
  gate(f.resolution !== 'OPEN', `${role} finding ${f.id} is unresolved (OPEN)`);
  if (f.resolution === 'FIXED') {
    gate(SHA1.test(f.fixedInCommit ?? '') && git.isAncestor(f.fixedInCommit, candidate),
      `${role} finding ${f.id} fix commit ${f.fixedInCommit} is not contained in the candidate`);
  } else {
    gate(f.severity === 'low', `${role} finding ${f.id}: accepted risk is allowed for only low severity`);
    const a = f.ownerAcceptance;
    gate(a && nonEmpty(a.by) && ISO.test(a.at ?? '') && nonEmpty(a.reference),
      `${role} finding ${f.id} accepted risk lacks explicit owner acceptance`);
  }
}

export function validateFunctionalRequirements(doc) {
  gate(doc?.schema === 'budlark-functional-requirements-v1' && Array.isArray(doc.requirements) && doc.requirements.length > 0,
    'invalid release/functional-requirements.json');
  gate(SHA1.test(doc.baselineCommit ?? ''), 'functional requirements need a full baselineCommit');
  const ids = new Set();
  for (const r of doc.requirements) {
    gate(nonEmpty(r.id) && !ids.has(r.id) && nonEmpty(r.flow) && nonEmpty(r.description) && Array.isArray(r.ownerItems)
      && typeof r.ui === 'boolean' && typeof r.regression === 'boolean', `malformed functional requirement ${r?.id ?? ''}`);
    ids.add(r.id);
  }
  const covered = new Set([...doc.requirements.flatMap((r) => r.ownerItems), ...Object.keys(doc.processOwnerItems ?? {}).map(Number)]);
  for (let i = 1; i <= doc.ownerItemCount; i += 1) gate(covered.has(i), `owner item ${i} is not covered by a functional requirement or process gate`);
  return { ok: true };
}

function verifyFunctional(root, candidate, installerSha256, artifact) {
  const contract = readRecord(join(root, 'release', 'functional-requirements.json'));
  validateFunctionalRequirements(contract);
  const prefix = `release/evidence/${candidate}/functional/`;
  const file = join(root, prefix, 'results.json');
  gate(existsSync(file), `functional evidence ${prefix}results.json is missing`);
  gate(existsSync(join(root, prefix, 'README.md')), `functional evidence ${prefix}README.md is missing`);
  const d = readRecord(file);
  const f = (c, m) => gate(c, `functional evidence: ${m}`);
  f(d.schema === 'budlark-functional-evidence-v1', 'unknown schema');
  f(d.candidateCommit === candidate, `candidate ${d.candidateCommit} does not match ${candidate}`);
  f(d.installerSha256 === installerSha256, 'installer SHA-256 does not match the signed bytes');
  f(d.artifact?.runId === artifact.runId && d.artifact?.artifactId === artifact.artifactId, 'artifact identity does not match the signed artifact');
  f(d.environment?.kind === 'clean-windows-vm' && nonEmpty(d.environment?.os), 'must run on a clean Windows VM');
  f(/^https:\/\//.test(d.run ?? ''), 'run must be an https link');
  f(ISO.test(d.executedAt ?? ''), 'executedAt must be an ISO-8601 UTC timestamp');
  f(d.baseline?.commit === contract.baselineCommit && /^https:\/\//.test(d.baseline?.run ?? ''),
    `baseline must be ${contract.baselineCommit} with an https run link`);
  f(Array.isArray(d.tests) && d.tests.length > 0, 'tests list is empty');
  const reqs = new Map(contract.requirements.map((r) => [r.id, r]));
  const path = (p, what) => {
    f(typeof p === 'string' && p.startsWith(prefix) && !p.includes('..'), `${what} path ${p} must be under ${prefix}`);
    f(existsSync(join(root, p)), `${what} ${p} does not exist`);
  };
  for (const t of d.tests) {
    const r = reqs.get(t?.requirement);
    f(r, `unknown requirement ${t?.requirement}`);
    f(nonEmpty(t.id), `${r.id} test id is missing`);
    f(t.result === 'PASS', `${t.id} (${r.id}) did not pass: ${t.result}`);
    path(t.log, `${t.id} log`);
    if (r.ui) {
      f(t.screenshots?.light, `${t.id} needs a light screenshot`);
      f(t.screenshots?.dark, `${t.id} needs a dark screenshot`);
      path(t.screenshots.light, `${t.id} light screenshot`);
      path(t.screenshots.dark, `${t.id} dark screenshot`);
    }
    if (r.regression) f(t.baselineResult === 'FAIL', `${t.id} (${r.id}) must prove it failed on the baseline build`);
  }
  const missing = [...reqs.keys()].filter((id) => !d.tests.some((t) => t.requirement === id));
  f(missing.length === 0, `no passing test for ${missing.join(', ')}`);
  return { tests: d.tests.length, requirements: reqs.size, environment: d.environment.os, run: d.run, executedAt: d.executedAt };
}

export function verifySignoffs({ root, stage, candidate, head, installerSha256, checkEvidence = false, git = realGit(root) }) {
  gate(['owner-test', 'public-launch'].includes(stage), `unknown stage ${stage}`);
  gate(SHA1.test(candidate ?? ''), 'candidate must be a full 40-hex commit SHA');
  gate(installerSha256 === undefined || SHA256.test(installerSha256), 'installer SHA-256 must be 64 lowercase hex');
  const registry = loadRoles(root);
  const known = new Map(registry.roles.map((r) => [r.id, r]));
  const required = registry.roles.filter((r) => stage === 'public-launch' || r.requiredAt === 'owner-test').map((r) => r.id);
  const sourceTree = git.tree(candidate);

  if (head && head !== candidate) {
    gate(git.isAncestor(candidate, head), `candidate ${candidate} is not an ancestor of head ${head}`);
    const drift = git.changedFiles(candidate, head).filter((p) => !SIGNOFF_PATH_PREFIXES.some((x) => p.startsWith(x)));
    gate(drift.length === 0, `files changed after the reviewed candidate: ${drift.join(', ')}`);
  }

  const dir = join(root, 'release', 'signoffs', candidate);
  const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.json')).sort() : [];
  const records = [];
  for (const file of files) {
    const id = file.slice(0, -5);
    gate(known.has(id), `Unknown role sign-off ${file}`);
    const r = readRecord(join(dir, file));
    gate(r.schema === 'budlark-release-signoff-v1', `${id} has an unknown schema`);
    gate(r.role === id, `${file} role field "${r.role}" does not match its file name`);
    gate(VERDICTS.has(r.verdict), `${id} has an invalid verdict`);
    gate(r.verdict !== 'CHANGES_REQUIRED', `${id} verdict is CHANGES_REQUIRED`);
    gate(r.candidateCommit === candidate, `${id} candidate ${r.candidateCommit} does not match ${candidate}`);
    gate(r.sourceTree === sourceTree, `${id} source tree ${r.sourceTree} does not match candidate tree ${sourceTree}`);
    gate(SHA256.test(r.installerSha256 ?? ''), `${id} installer SHA-256 is missing or malformed`);
    gate(installerSha256 === undefined || r.installerSha256 === installerSha256,
      `${id} installer SHA-256 ${r.installerSha256} does not match released bytes ${installerSha256}`);
    gate(r.artifact && DIGITS.test(r.artifact.runId ?? '') && DIGITS.test(r.artifact.artifactId ?? ''), `${id} artifact identity is missing`);
    gate(nonEmpty(r.scope), `${id} scope is missing`);
    gate(Array.isArray(r.evidence) && r.evidence.length > 0 && r.evidence.every(nonEmpty), `${id} evidence list is empty`);
    const review = `release/reviews/${candidate}/${id}.md`;
    gate(r.evidence.includes(review), `${id} evidence must cite release/reviews/${candidate}/${id}.md`);
    gate(existsSync(join(root, review)) && readFileSync(join(root, review), 'utf8').trim().length > 0,
      `${id} review file ${review} is missing or empty`);
    for (const e of r.evidence.filter((x) => !/^https:\/\//.test(x))) {
      gate(!e.includes('..') && existsSync(join(root, e)), `${id} evidence path ${e} does not exist`);
    }
    gate(r.reviewer && nonEmpty(r.reviewer.session) && nonEmpty(r.reviewer.model), `${id} reviewer identity is missing`);
    gate(ISO.test(r.reviewedAt ?? ''), `${id} reviewedAt must be an ISO-8601 UTC timestamp`);
    gate(Array.isArray(r.findings), `${id} findings must be an array`);
    for (const f of r.findings) checkFinding(id, f, candidate, git);
    const hasAccepted = r.findings.some((f) => f.resolution === 'ACCEPTED_RISK');
    gate(hasAccepted === (r.verdict === 'APPROVED_WITH_ACCEPTED_RISK'), `${id} verdict must reflect accepted-risk findings`);
    records.push(r);
  }
  const missing = required.filter((id) => !records.some((r) => r.role === id));
  gate(missing.length === 0, `Missing required sign-off(s) for ${stage}: ${missing.join(', ')}`);

  let ownerTrial;
  if (stage === 'public-launch') {
    const file = join(root, 'release', 'owner', `${candidate}.json`);
    gate(existsSync(file), `owner trial record release/owner/${candidate}.json is missing`);
    ownerTrial = readRecord(file);
    gate(ownerTrial.schema === 'budlark-owner-trial-v1' && ownerTrial.candidateCommit === candidate, 'owner trial record does not bind the candidate');
    gate(ownerTrial.result === 'PASS', `owner trial result is ${ownerTrial.result}`);
    gate(ownerTrial.installerSha256 === records[0]?.installerSha256, 'owner trial installer SHA-256 does not match the signed bytes');
    gate(nonEmpty(ownerTrial.by) && ISO.test(ownerTrial.testedAt) && /^https:\/\//.test(ownerTrial.reference ?? ''),
      'owner trial record needs by, testedAt and an https reference to the owner statement');
  }

  const shas = new Set(records.map((r) => r.installerSha256));
  gate(shas.size === 1, `installer SHA-256 differs across sign-offs: ${[...shas].join(', ')}`);
  const runs = new Set(records.map((r) => `${r.artifact.runId}/${r.artifact.artifactId}`));
  gate(runs.size === 1, `artifact identity differs across sign-offs: ${[...runs].join(', ')}`);
  const functional = verifyFunctional(root, candidate, records[0].installerSha256, records[0].artifact);

  const result = {
    ok: true,
    kind: 'budlark-release-signoff-gate-v1',
    stage,
    candidate,
    head: head ?? candidate,
    sourceTree,
    installerSha256: records[0].installerSha256,
    artifact: records[0].artifact,
    ownerTrial,
    functional,
    required,
    records: records.sort((a, b) => registry.roles.findIndex((x) => x.id === a.role) - registry.roles.findIndex((x) => x.id === b.role)),
    roles: registry.roles,
  };
  if (checkEvidence) {
    const file = evidencePath(root, candidate);
    gate(existsSync(file), `Evidence README missing at ${file}`);
    const onDisk = readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
    gate(onDisk === renderEvidence(result), `Evidence README is stale; regenerate with --write-evidence (${file})`);
  }
  return result;
}

export const evidencePath = (root, candidate) => join(root, 'release', 'evidence', candidate, 'README.md');

export function renderEvidence(result) {
  const title = new Map(result.roles.map((r) => [r.id, r.title]));
  const findings = result.records.flatMap((r) => r.findings.map((f) => ({ role: r.role, ...f })));
  const accepted = findings.filter((f) => f.resolution === 'ACCEPTED_RISK');
  const lines = [
    `# Release evidence — candidate ${result.candidate}`,
    '',
    'Generated by `tool/verify_release_signoffs.mjs`. Do not edit by hand; CI rejects stale copies.',
    '',
    '## Identity',
    '',
    '| Item | Value |',
    '|---|---|',
    `| Candidate commit | \`${result.candidate}\` |`,
    `| Source tree | \`${result.sourceTree}\` |`,
    `| Installer SHA-256 | \`${result.installerSha256}\` |`,
    `| CI run | [${result.artifact.runId}](https://github.com/Sampath-K/budlark/actions/runs/${result.artifact.runId}) |`,
    `| Artifact id | ${result.artifact.artifactId} |`,
    `| Gate stage verified | ${result.stage} |`,
    `| Functional tests | ${result.functional.tests} passing tests covering ${result.functional.requirements} requirements on a clean ${result.functional.environment} VM at ${result.functional.executedAt} ([run](${result.functional.run}); \`functional/README.md\`) |`,
    `| Owner trial | ${result.ownerTrial ? `${result.ownerTrial.result} by ${result.ownerTrial.by} at ${result.ownerTrial.testedAt} (${result.ownerTrial.reference})` : 'Not required at this stage (owner-test sign-off precedes the owner trial)'} |`,
    '',
    '## Role sign-offs',
    '',
    '| Role | Verdict | Reviewer | Reviewed (UTC) | Scope | Evidence |',
    '|---|---|---|---|---|---|',
    ...result.records.map((r) => `| ${title.get(r.role)} (\`${r.role}\`) | ${r.verdict} | ${r.reviewer.session} / ${r.reviewer.model} | ${r.reviewedAt} | ${r.scope.replace(/\|/g, '/')} | ${r.evidence.map((e) => `\`${e}\``).join('<br>')} |`),
    '',
    '## Findings and fixes',
    '',
    ...(findings.length === 0 ? ['No findings recorded.'] : [
      '| Role | Id | Severity | Resolution | Fix commit | Description |',
      '|---|---|---|---|---|---|',
      ...findings.map((f) => `| ${f.role} | ${f.id} | ${f.severity} | ${f.resolution} | ${f.fixedInCommit ? `\`${f.fixedInCommit.slice(0, 12)}\`` : '—'} | ${f.description.replace(/\|/g, '/')} |`),
    ]),
    '',
    '## Residual risks',
    '',
    ...(accepted.length === 0 ? ['No owner-accepted risks.'] : accepted.map((f) => `- ${f.role} ${f.id} (${f.severity}): ${f.description} — accepted by ${f.ownerAcceptance.by} at ${f.ownerAcceptance.at} (${f.ownerAcceptance.reference})`)),
    '- The installer is unsigned unless a signing record states otherwise; a matching SHA-256 proves byte identity, not safety. SmartScreen/Defender are never bypassed.',
    '',
    '## Gate rules enforced',
    '',
    '- Every required role recorded an explicit APPROVED/APPROVED_WITH_ACCEPTED_RISK verdict for this exact candidate, tree and installer SHA-256.',
    '- No CHANGES_REQUIRED verdicts and no OPEN findings; FIXED findings cite commits contained in the candidate; accepted risk is low severity with explicit owner acceptance.',
    '- Every functional requirement passed on a clean Windows VM against these exact installer bytes, with light/dark screenshots and baseline-failure proof for owner-reported bugs.',
    `- Only ${SIGNOFF_PATH_PREFIXES.join(', ')} may change between the candidate and the released head.`,
    '',
  ];
  return lines.join('\n');
}

export function verifyArtifactProvenance({ candidate, artifact, repository, run, artifacts }) {
  const p = (c, m) => gate(c, `artifact provenance: ${m}`);
  p(SHA1.test(candidate ?? '') && DIGITS.test(artifact?.runId ?? '') && DIGITS.test(artifact?.artifactId ?? ''), 'malformed candidate or artifact identity');
  p(String(run?.id) === artifact.runId, `run ${run?.id} is not the signed run ${artifact.runId}`);
  p(run.head_sha === candidate, `run built ${run.head_sha}, not the candidate`);
  p(run.event === 'push' && run.conclusion === 'success', 'signed run must be a successful push run');
  p(run.path === '.github/workflows/ci.yml' && run.repository?.full_name === repository, "signed run is not this repository's ci workflow");
  const match = (artifacts?.artifacts ?? []).filter((a) => a.name === 'budlark-universal-installer');
  p(match.length === 1 && String(match[0].id) === artifact.artifactId, "signed artifact id is not the run's universal installer");
  p(match[0].expired === false, 'signed artifact has expired');
  return { ok: true };
}

export function verifyOwnerStatement({ trial, comment, repository, owner }) {
  const o = (c, m) => gate(c, `owner statement: ${m}`);
  const m = /^https:\/\/github\.com\/([^/]+\/[^/]+)\/(?:issues|pull)\/\d+#issuecomment-([1-9]\d{0,19})$/.exec(trial?.reference ?? '');
  o(m && m[1] === repository, 'reference must be an issue or PR comment URL in this repository');
  o(String(comment?.id) === m[2], 'fetched comment is not the referenced comment');
  o(nonEmpty(owner) && comment.user?.login === owner && comment.user?.type === 'User' && comment.author_association === 'OWNER',
    'comment is not authored by the repository owner');
  o(trial.by === owner, 'record attributes the trial to someone other than the owner');
  const ts = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(v) && !Number.isNaN(Date.parse(v));
  o(ts(comment.created_at) && ts(comment.updated_at), 'comment must carry valid created_at and updated_at');
  o(comment.updated_at === comment.created_at, 'comment was edited after posting');
  const body = comment.body ?? '';
  o(body.includes(trial.candidateCommit) && body.includes(trial.installerSha256), 'comment must name the exact candidate commit and installer SHA-256');
  o(/\bPASS\b/.test(body) && !/\bFAIL\b/i.test(body), 'comment must state PASS and no FAIL');
  return { ok: true, commentId: m[2] };
}

export function resolveCandidate({ root, head, git = realGit(root) }) {
  const base = join(root, 'release', 'signoffs');
  const candidates = existsSync(base) ? readdirSync(base).filter((d) => SHA1.test(d)
    && readdirSync(join(base, d)).some((f) => f.endsWith('.json')) && git.isAncestor(d, head)) : [];
  gate(candidates.length > 0, `No signed candidate is an ancestor of ${head}`);
  const clean = candidates.filter((c) => c === head
    || git.changedFiles(c, head).every((p) => SIGNOFF_PATH_PREFIXES.some((x) => p.startsWith(x))));
  gate(clean.length === 1, `Expected exactly one signed candidate matching ${head}; found ${clean.length}`);
  return clean[0];
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (['--write-evidence', '--check-evidence', '--resolve-candidate', '--emit-artifact', '--emit-owner-comment'].includes(key)) args[key.slice(2)] = true;
    else if (key.startsWith('--')) { args[key.slice(2)] = argv[i + 1]; i += 1; }
  }
  return args;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  const root = resolve(args.root ?? '.');
  const git = realGit(root);
  const head = args.head ? execFileSync('git', ['rev-parse', args.head], { cwd: root, encoding: 'utf8' }).trim() : undefined;
  try {
    if (args['resolve-candidate']) {
      process.stdout.write(`${resolveCandidate({ root, head: head ?? 'HEAD', git })}\n`);
      process.exit(0);
    }
    if (args['provenance-run']) {
      const r = verifySignoffs({ root, stage: args.stage, candidate: args.candidate, head, git });
      verifyArtifactProvenance({
        candidate: r.candidate, artifact: r.artifact, repository: args.repository,
        run: JSON.parse(readFileSync(args['provenance-run'], 'utf8')),
        artifacts: JSON.parse(readFileSync(args['provenance-artifacts'], 'utf8')),
      });
      process.stdout.write(`PASS provenance run ${r.artifact.runId} artifact ${r.artifact.artifactId} built ${r.candidate}\n`);
      process.exit(0);
    }
    if (args['owner-comment']) {
      const r = verifySignoffs({ root, stage: 'public-launch', candidate: args.candidate, head, git });
      const v = verifyOwnerStatement({ trial: r.ownerTrial, repository: args.repository, owner: args.owner,
        comment: JSON.parse(readFileSync(args['owner-comment'], 'utf8')) });
      process.stdout.write(`PASS owner statement comment ${v.commentId} by ${args.owner}\n`);
      process.exit(0);
    }
    if (args['emit-owner-comment']) {
      const r = verifySignoffs({ root, stage: 'public-launch', candidate: args.candidate, head, git });
      const id = /#issuecomment-([1-9]\d{0,19})$/.exec(r.ownerTrial.reference ?? '');
      gate(id, 'owner trial reference is not a GitHub comment URL');
      process.stdout.write(`comment=${id[1]}\n`);
      process.exit(0);
    }
    if (args['emit-artifact']) {
      const r = verifySignoffs({ root, stage: args.stage, candidate: args.candidate, head, git });
      process.stdout.write(`run=${r.artifact.runId}\nartifact=${r.artifact.artifactId}\n`);
      process.exit(0);
    }
    let installerSha256 = args['installer-sha256'];
    if (args.installer) installerSha256 = createHash('sha256').update(readFileSync(args.installer)).digest('hex');
    const result = verifySignoffs({
      root, stage: args.stage, candidate: args.candidate, head, installerSha256,
      checkEvidence: Boolean(args['check-evidence']), git,
    });
    if (args['write-evidence']) {
      const file = evidencePath(root, result.candidate);
      mkdirSync(join(file, '..'), { recursive: true });
      writeFileSync(file, renderEvidence(result));
      process.stdout.write(`Evidence README: ${file}\n`);
    }
    if (args.out) writeFileSync(args.out, `${JSON.stringify({ ...result, roles: undefined }, null, 2)}\n`);
    process.stdout.write(`PASS ${result.stage}: ${result.records.length} sign-offs bind ${result.candidate} / tree ${result.sourceTree} / installer ${result.installerSha256}\n`);
  } catch (error) {
    process.stderr.write(`FAIL ${error.message}\n`);
    process.exit(1);
  }
}
