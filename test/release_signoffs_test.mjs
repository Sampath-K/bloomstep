import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  verifySignoffs, renderEvidence, resolveCandidate, SIGNOFF_PATH_PREFIXES, verifyArtifactProvenance, verifyOwnerStatement,
  validateFunctionalRequirements,
} from '../tool/verify_release_signoffs.mjs';

const CANDIDATE = 'a'.repeat(40);
const HEAD = 'b'.repeat(40);
const TREE = 'c'.repeat(40);
const FIX = 'd'.repeat(40);
const SHA = 'e'.repeat(64);
const repoRoot = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

function fakeGit({ changed = [], ancestors = [[CANDIDATE, HEAD], [FIX, CANDIDATE]], trees = { [CANDIDATE]: TREE } } = {}) {
  return {
    tree: (rev) => { if (!trees[rev]) throw new Error(`unknown rev ${rev}`); return trees[rev]; },
    changedFiles: () => changed,
    isAncestor: (a, b) => a === b || ancestors.some(([x, y]) => x === a && y === b),
  };
}

function record(role, overrides = {}) {
  return {
    schema: 'budlark-release-signoff-v1',
    role,
    verdict: 'APPROVED',
    candidateCommit: CANDIDATE,
    sourceTree: TREE,
    installerSha256: SHA,
    artifact: { runId: '39100447327', artifactId: '12127077182' },
    scope: `Full ${role} review of the candidate tree and installer`,
    evidence: [`release/reviews/${CANDIDATE}/${role}.md`],
    findings: [],
    reviewer: { session: 'role-agent', model: 'auto' },
    reviewedAt: '2026-10-20T06:00:00Z',
    ...overrides,
  };
}

function ownerTrial(overrides = {}) {
  return {
    schema: 'budlark-owner-trial-v1', candidateCommit: CANDIDATE, installerSha256: SHA, result: 'PASS',
    by: 'Sampath-K', testedAt: '2026-10-21T06:00:00Z', reference: 'https://github.com/Sampath-K/budlark/pull/52#issuecomment-1', ...overrides,
  };
}

const FUNC = `release/evidence/${CANDIDATE}/functional`;
const BASELINE = '083f2def66c1e084c56653238b85802ff260c3c3';

function writeFunctional(root, mutate = () => {}) {
  cpSync(join(repoRoot, 'release', 'functional-requirements.json'), join(root, 'release', 'functional-requirements.json'));
  const reqs = JSON.parse(readFileSync(join(root, 'release', 'functional-requirements.json'), 'utf8')).requirements;
  mkdirSync(join(root, FUNC, 'shots'), { recursive: true });
  mkdirSync(join(root, FUNC, 'logs'), { recursive: true });
  writeFileSync(join(root, FUNC, 'README.md'), '# Functional evidence\n');
  const tests = reqs.map((r) => {
    const t = { id: `T-${r.id}`, requirement: r.id, result: 'PASS', log: `${FUNC}/logs/${r.id}.log` };
    writeFileSync(join(root, t.log), 'ok\n');
    if (r.ui) {
      t.screenshots = { light: `${FUNC}/shots/${r.id}-light.png`, dark: `${FUNC}/shots/${r.id}-dark.png` };
      writeFileSync(join(root, t.screenshots.light), 'png');
      writeFileSync(join(root, t.screenshots.dark), 'png');
    }
    if (r.regression) t.baselineResult = 'FAIL';
    return t;
  });
  const doc = {
    schema: 'budlark-functional-evidence-v1', candidateCommit: CANDIDATE, installerSha256: SHA,
    artifact: { runId: '39100447327', artifactId: '12127077182' },
    environment: { kind: 'clean-windows-vm', os: 'Windows 11 24H2' },
    run: 'https://github.com/Sampath-K/budlark/actions/runs/39100447327', executedAt: '2026-10-20T05:00:00Z',
    baseline: { commit: BASELINE, run: 'https://github.com/Sampath-K/budlark/actions/runs/39100447300' },
    tests,
  };
  mutate(doc);
  if (doc !== null) writeFileSync(join(root, FUNC, 'results.json'), JSON.stringify(doc, null, 2));
}

function setup(stage = 'public-launch', mutate = () => {}) {
  const root = mkdtempSync(join(tmpdir(), 'budlark-signoffs-'));
  mkdirSync(join(root, 'release'), { recursive: true });
  cpSync(join(repoRoot, 'release', 'roles.json'), join(root, 'release', 'roles.json'));
  const roles = JSON.parse(readFileSync(join(root, 'release', 'roles.json'), 'utf8')).roles
    .filter((r) => stage === 'public-launch' || r.requiredAt === 'owner-test');
  const dir = join(root, 'release', 'signoffs', CANDIDATE);
  mkdirSync(dir, { recursive: true });
  mkdirSync(join(root, 'release', 'reviews', CANDIDATE), { recursive: true });
  mkdirSync(join(root, 'release', 'owner'), { recursive: true });
  writeFileSync(join(root, 'release', 'owner', `${CANDIDATE}.json`), JSON.stringify(ownerTrial(), null, 2));
  writeFunctional(root);
  for (const { id } of roles) {
    writeFileSync(join(root, 'release', 'reviews', CANDIDATE, `${id}.md`), `# ${id} review\n\nVerdict: APPROVED\n`);
    const rec = record(id);
    mutate(id, rec);
    if (rec !== null) writeFileSync(join(dir, `${id}.json`), JSON.stringify(rec, null, 2));
  }
  return root;
}

const run = (root, opts = {}) => verifySignoffs({
  root, stage: 'public-launch', candidate: CANDIDATE, head: HEAD, installerSha256: SHA, git: fakeGit(), ...opts,
});

test('roles registry declares 13 accountable roles (incl. brand-marketing) with valid stages', () => {
  const roles = JSON.parse(readFileSync(join(repoRoot, 'release', 'roles.json'), 'utf8'));
  assert.equal(roles.roles.length, 13);
  assert.equal(roles.roles.find((r) => r.id === 'brand-marketing')?.requiredAt, 'owner-test');
  assert.equal(new Set(roles.roles.map((r) => r.id)).size, 13);
  for (const r of roles.roles) assert.ok(roles.stages.includes(r.requiredAt), r.id);
});

test('complete approved set passes and binds candidate, tree and installer', () => {
  const root = setup();
  try {
    const result = run(root);
    assert.equal(result.ok, true);
    assert.equal(result.records.length, 13);
    assert.equal(result.sourceTree, TREE);
    assert.equal(result.installerSha256, SHA);
    assert.equal(result.artifact.runId, '39100447327');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('owner-test stage requires only owner-test roles; public-launch requires all', () => {
  const root = setup('owner-test');
  try {
    assert.equal(run(root, { stage: 'owner-test' }).ok, true);
    assert.throws(() => run(root), /Missing required sign-off.*legal-compliance/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('missing role, unknown role, malformed JSON and role/file mismatch fail closed', () => {
  let root = setup('public-launch', (id, rec) => { if (id === 'security-privacy') rec.role = 'engineering'; });
  try { assert.throws(() => run(root), /role field/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup();
  try {
    writeFileSync(join(root, 'release', 'signoffs', CANDIDATE, 'mystery.json'), JSON.stringify(record('mystery')));
    assert.throws(() => run(root), /Unknown role/);
  } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup();
  try {
    writeFileSync(join(root, 'release', 'signoffs', CANDIDATE, 'qa-release.json'), '{not json');
    assert.throws(() => run(root), /Malformed/);
  } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup();
  try {
    rmSync(join(root, 'release', 'signoffs', CANDIDATE, 'architect.json'));
    assert.throws(() => run(root), /Missing required sign-off.*architect/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('CHANGES_REQUIRED and OPEN findings block release', () => {
  let root = setup('public-launch', (id, rec) => { if (id === 'engineering') rec.verdict = 'CHANGES_REQUIRED'; });
  try { assert.throws(() => run(root), /engineering.*CHANGES_REQUIRED/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => {
    if (id === 'security-privacy') rec.findings = [{ id: 'SEC-1', severity: 'high', description: 'x', resolution: 'OPEN' }];
  });
  try { assert.throws(() => run(root), /SEC-1.*unresolved/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('accepted risk only for low severity with explicit owner acceptance', () => {
  const low = { id: 'UX-2', severity: 'low', description: 'minor', resolution: 'ACCEPTED_RISK' };
  let root = setup('public-launch', (id, rec) => {
    if (id === 'ux-content-accessibility') { rec.verdict = 'APPROVED_WITH_ACCEPTED_RISK'; rec.findings = [low]; }
  });
  try { assert.throws(() => run(root), /UX-2.*owner acceptance/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => {
    if (id === 'ux-content-accessibility') {
      rec.verdict = 'APPROVED_WITH_ACCEPTED_RISK';
      rec.findings = [{ ...low, ownerAcceptance: { by: 'Sampath-K', at: '2026-10-20T07:00:00Z', reference: 'PR52 comment' } }];
    }
  });
  try { assert.equal(run(root).ok, true); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => {
    if (id === 'security-privacy') {
      rec.verdict = 'APPROVED_WITH_ACCEPTED_RISK';
      rec.findings = [{ ...low, severity: 'medium', ownerAcceptance: { by: 'Sampath-K', at: '2026-10-20T07:00:00Z', reference: 'x' } }];
    }
  });
  try { assert.throws(() => run(root), /only low severity/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('FIXED findings must cite a fix commit contained in the candidate', () => {
  let root = setup('public-launch', (id, rec) => {
    if (id === 'engineering') rec.findings = [{ id: 'ENG-1', severity: 'medium', description: 'branding', resolution: 'FIXED', fixedInCommit: FIX }];
  });
  try { assert.equal(run(root).ok, true); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => {
    if (id === 'engineering') rec.findings = [{ id: 'ENG-1', severity: 'medium', description: 'branding', resolution: 'FIXED', fixedInCommit: 'f'.repeat(40) }];
  });
  try { assert.throws(() => run(root), /ENG-1.*not contained/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('tree, installer SHA, candidate and artifact identity mismatches fail', () => {
  let root = setup('public-launch', (id, rec) => { if (id === 'qa-release') rec.sourceTree = '9'.repeat(40); });
  try { assert.throws(() => run(root), /qa-release.*source tree/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => { if (id === 'qa-release') rec.installerSha256 = '1'.repeat(64); });
  try { assert.throws(() => run(root), /qa-release.*installer SHA-256/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup();
  try { assert.throws(() => run(root, { installerSha256: '2'.repeat(64) }), /installer SHA-256/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => { if (id === 'architect') rec.candidateCommit = FIX; });
  try { assert.throws(() => run(root), /architect.*candidate/); } finally { rmSync(root, { recursive: true, force: true }); }
  root = setup('public-launch', (id, rec) => { if (id === 'support') rec.artifact = { runId: '1', artifactId: '2' }; });
  try { assert.throws(() => run(root), /artifact identity/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('missing reviewer, evidence or timestamp fails', () => {
  for (const [field, value, pattern] of [
    ['reviewer', {}, /reviewer/], ['evidence', [], /evidence/], ['reviewedAt', 'yesterday', /reviewedAt/], ['scope', '', /scope/],
  ]) {
    const root = setup('public-launch', (id, rec) => { if (id === 'product') rec[field] = value; });
    try { assert.throws(() => run(root), pattern); } finally { rmSync(root, { recursive: true, force: true }); }
  }
});

test('head may differ from candidate only by sign-off records and evidence', () => {
  const root = setup();
  try {
    const okPaths = SIGNOFF_PATH_PREFIXES.map((p) => `${p}${CANDIDATE}/x.md`);
    assert.equal(run(root, { git: fakeGit({ changed: okPaths }) }).ok, true);
    assert.throws(() => run(root, { git: fakeGit({ changed: ['lib/main.dart'] }) }), /after the reviewed candidate: lib\/main\.dart/);
    assert.throws(() => run(root, { git: fakeGit({ ancestors: [] }) }), /not an ancestor/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('evidence README is deterministic and stale copies are rejected', () => {
  const root = setup();
  try {
    const result = run(root);
    const md = renderEvidence(result);
    assert.equal(md, renderEvidence(run(root)));
    for (const s of [CANDIDATE, TREE, SHA, '39100447327', 'security-privacy', 'APPROVED', 'Residual risks']) assert.ok(md.includes(s), s);
    const evidenceDir = join(root, 'release', 'evidence', CANDIDATE);
    mkdirSync(evidenceDir, { recursive: true });
    writeFileSync(join(evidenceDir, 'README.md'), md);
    assert.equal(run(root, { checkEvidence: true }).ok, true);
    writeFileSync(join(evidenceDir, 'README.md'), `${md}\nedited by hand\n`);
    assert.throws(() => run(root, { checkEvidence: true }), /Evidence README is stale/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('candidate resolution picks the single signed candidate reachable from head', () => {
  const root = setup();
  try {
    assert.equal(resolveCandidate({ root, head: HEAD, git: fakeGit() }), CANDIDATE);
    assert.throws(() => resolveCandidate({ root, head: HEAD, git: fakeGit({ ancestors: [] }) }), /No signed candidate/);
    mkdirSync(join(root, 'release', 'signoffs', FIX), { recursive: true });
    assert.equal(resolveCandidate({ root, head: HEAD, git: fakeGit() }), CANDIDATE, 'non-ancestor/empty dirs ignored');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('invalid inputs are rejected before reading records', () => {
  assert.throws(() => verifySignoffs({ root: '.', stage: 'beta', candidate: CANDIDATE, git: fakeGit() }), /stage/);
  assert.throws(() => verifySignoffs({ root: '.', stage: 'owner-test', candidate: 'abc', git: fakeGit() }), /candidate/);
  assert.throws(() => verifySignoffs({ root: '.', stage: 'owner-test', candidate: CANDIDATE, installerSha256: 'XYZ', git: fakeGit() }), /installer/);
});

test('release workflow promotes the signed candidate and enforces the public-launch gate', () => {
  const ci = readFileSync(join(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf8').replace(/\r\n/g, '\n');
  const release = ci.slice(ci.indexOf('\n  release:'));
  assert.match(release, /verify_release_signoffs\.mjs --resolve-candidate --head "\$GITHUB_SHA"/);
  assert.match(release, /gh run download "\$RUN_ID"/);
  assert.match(release, /--stage public-launch --candidate "\$CANDIDATE" --head "\$GITHUB_SHA" --installer "\$installer" --check-evidence/);
  assert.match(release, /release_bundle\.mjs \. "\$CANDIDATE"/);
  assert.doesNotMatch(release, /release_bundle\.mjs \. "\$GITHUB_SHA"/);
  assert.doesNotMatch(release, /actions\/download-artifact/, 'tag runs must not publish rebuilt bits');
  assert.ok(release.indexOf('--stage public-launch') < release.indexOf('gh release create'));
});
test('ARCH-1: referenced review file must exist and be listed as evidence', () => {
  const root = setup();
  try {
    rmSync(join(root, 'release', 'reviews', CANDIDATE, 'security-privacy.md'));
    assert.throws(() => run(root), /security-privacy review file .* is missing/);
  } finally { rmSync(root, { recursive: true, force: true }); }
  const root2 = setup('public-launch', (id, r) => { if (id === 'qa-release') r.evidence = ['https://example.com/x']; });
  try { assert.throws(() => run(root2), /qa-release evidence must cite release\/reviews/); } finally { rmSync(root2, { recursive: true, force: true }); }
  const root3 = setup('public-launch', (id, r) => { if (id === 'architect') r.evidence.push('docs/does-not-exist.md'); });
  try { assert.throws(() => run(root3), /architect evidence path docs\/does-not-exist\.md does not exist/); } finally { rmSync(root3, { recursive: true, force: true }); }
});

test('ENG-1: impossible timestamps are rejected', () => {
  const root = setup('public-launch', (id, r) => { if (id === 'engineering') r.reviewedAt = '2026-02-30T25:61:00Z'; });
  try { assert.throws(() => run(root), /engineering reviewedAt must be an ISO-8601 UTC timestamp/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('SEC-1: run and artifact ids must be digits-only before any shell use', () => {
  const root = setup('public-launch', (id, r) => { r.artifact.runId = '1"; curl evil #'; });
  try { assert.throws(() => run(root), /artifact identity is missing/); } finally { rmSync(root, { recursive: true, force: true }); }
});

test('QA: public launch requires a passing owner trial bound to the same bytes; owner-test does not', () => {
  const root = setup();
  try {
    rmSync(join(root, 'release', 'owner', `${CANDIDATE}.json`));
    assert.throws(() => run(root), /owner trial record .* is missing/);
    assert.equal(run(root, { stage: 'owner-test' }).ok, true);
    writeFileSync(join(root, 'release', 'owner', `${CANDIDATE}.json`), JSON.stringify(ownerTrial({ result: 'FAIL' })));
    assert.throws(() => run(root), /owner trial result is FAIL/);
    writeFileSync(join(root, 'release', 'owner', `${CANDIDATE}.json`), JSON.stringify(ownerTrial({ installerSha256: 'f'.repeat(64) })));
    assert.throws(() => run(root), /owner trial installer SHA-256 does not match/);
    writeFileSync(join(root, 'release', 'owner', `${CANDIDATE}.json`), JSON.stringify(ownerTrial()));
    const result = run(root);
    assert.equal(result.ownerTrial.result, 'PASS');
    assert.match(renderEvidence(result), /Owner trial \| PASS by Sampath-K/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('ARCH-2: artifact provenance must match the signed run and artifact', () => {
  const good = {
    run: { id: 39100447327, head_sha: CANDIDATE, event: 'push', conclusion: 'success', path: '.github/workflows/ci.yml', repository: { full_name: 'Sampath-K/budlark' } },
    artifacts: { artifacts: [{ id: 12127077182, name: 'budlark-universal-installer', expired: false }] },
  };
  const args = { candidate: CANDIDATE, artifact: { runId: '39100447327', artifactId: '12127077182' }, repository: 'Sampath-K/budlark' };
  assert.equal(verifyArtifactProvenance({ ...args, ...good }).ok, true);
  const bad = (patch) => assert.throws(() => verifyArtifactProvenance({ ...args, ...good, ...patch }), /provenance/);
  bad({ run: { ...good.run, head_sha: HEAD } });
  bad({ run: { ...good.run, event: 'pull_request' } });
  bad({ run: { ...good.run, conclusion: 'failure' } });
  bad({ run: { ...good.run, id: 1 } });
  bad({ run: { ...good.run, path: '.github/workflows/other.yml' } });
  bad({ artifacts: { artifacts: [{ id: 999, name: 'budlark-universal-installer', expired: false }] } });
  bad({ artifacts: { artifacts: [{ id: 12127077182, name: 'budlark-universal-installer', expired: true }] } });
});

test('SEC-1/SEC-2: release job never interpolates record data into shell and requires the owner-approved environment', () => {
  const ci = readFileSync(join(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf8').replace(/\r\n/g, '\n');
  const release = ci.slice(ci.indexOf('\n  release:'));
  const unsafe = release.split('\n').filter((l) => /\$\{\{ steps\./.test(l) && !/^\s+[A-Z_]+: \$\{\{ steps\.candidate\.outputs\.[a-z]+ \}\}$/.test(l));
  assert.deepEqual(unsafe, [], 'step outputs must flow through env, not template interpolation');
  assert.match(release, /environment: public-launch/);
  assert.match(release, /--provenance-run run\.json --provenance-artifacts artifacts\.json/);
  assert.ok(release.indexOf('--provenance-run') < release.indexOf('gh run download'));
});
test('QA-1: owner trial reference must resolve to an owner-authored comment in this repo naming the exact bytes', () => {
  const trial = { candidateCommit: CANDIDATE, installerSha256: SHA, result: 'PASS', by: 'Sampath-K',
    reference: 'https://github.com/Sampath-K/budlark/pull/52#issuecomment-123' };
  const comment = { id: 123, html_url: trial.reference, user: { login: 'Sampath-K', type: 'User' }, author_association: 'OWNER',
    created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z',
    body: `Installer test PASS for ${CANDIDATE} installer ${SHA}` };
  const args = { trial, comment, repository: 'Sampath-K/budlark', owner: 'Sampath-K' };
  assert.equal(verifyOwnerStatement(args).ok, true);
  const bad = (patch, re = /owner statement/) => assert.throws(() => verifyOwnerStatement({ ...args, ...patch }), re);
  bad({ trial: { ...trial, reference: 'https://example.com/x#issuecomment-123' } });
  bad({ trial: { ...trial, reference: 'https://github.com/other/repo/pull/52#issuecomment-123' } });
  bad({ comment: { ...comment, id: 999 } });
  bad({ comment: { ...comment, user: { login: 'someone-else', type: 'User' } } });
  bad({ comment: { ...comment, author_association: 'CONTRIBUTOR' } });
  bad({ trial: { ...trial, by: 'someone-else' } });
  bad({ comment: { ...comment, body: `PASS for ${CANDIDATE}` } });
  bad({ comment: { ...comment, body: `Installer ${SHA} ${CANDIDATE} FAIL` } });
  bad({ comment: { ...comment, body: `PASS ${SHA} ${CANDIDATE} edited`, updated_at: '2026-10-22T00:00:00Z', created_at: '2026-10-21T00:00:00Z' } });
  bad({ comment: { ...comment, created_at: undefined } });
  bad({ comment: { ...comment, updated_at: undefined } });
  bad({ comment: { ...comment, created_at: 'not-a-date', updated_at: 'not-a-date' } });
});

test('QA-1: release job authenticates the owner statement via the API before promotion', () => {
  const wf = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const job = wf.slice(wf.indexOf('environment: public-launch'));
  const verifyAt = job.indexOf('--owner-comment');
  assert.ok(verifyAt > 0, 'owner comment verification missing');
  assert.ok(verifyAt < job.indexOf('gh release create'), 'owner statement must be verified before publishing');
  assert.match(job, /issues\/comments\/\$COMMENT_ID/);
});

test('FUNC: requirements cover every owner-reported item 1..N exactly by a requirement or a named process gate', () => {
  const doc = JSON.parse(readFileSync(join(repoRoot, 'release', 'functional-requirements.json'), 'utf8'));
  assert.equal(doc.baselineCommit, BASELINE);
  const covered = new Set([...doc.requirements.flatMap((r) => r.ownerItems), ...Object.keys(doc.processOwnerItems).map(Number)]);
  for (let i = 1; i <= doc.ownerItemCount; i += 1) assert.ok(covered.has(i), `owner item ${i} uncovered`);
  assert.equal(validateFunctionalRequirements(doc).ok, true);
  assert.throws(() => validateFunctionalRequirements({ ...doc, processOwnerItems: {}, requirements: doc.requirements.filter((r) => !r.ownerItems.includes(7)) }), /owner item/);
});

test('FUNC: owner-test and public launch both require passing functional evidence on the exact installer', () => {
  for (const stage of ['owner-test', 'public-launch']) {
    const root = setup(stage);
    try {
      assert.equal(run(root, { stage }).ok, true);
      const bad = (mutate, re) => { writeFunctional(root, mutate); assert.throws(() => run(root, { stage }), re); writeFunctional(root); };
      bad((d) => { d.schema = 'x'; }, /functional evidence/);
      bad((d) => { d.installerSha256 = 'f'.repeat(64); }, /functional evidence.*installer/);
      bad((d) => { d.candidateCommit = HEAD; }, /functional evidence.*candidate/);
      bad((d) => { d.artifact.artifactId = '1'; }, /functional evidence.*artifact/);
      bad((d) => { d.environment.kind = 'developer-laptop'; }, /clean Windows VM/);
      bad((d) => { d.run = 'http://x'; }, /run/);
      bad((d) => { d.executedAt = '2026-13-01T00:00:00Z'; }, /executedAt/);
      bad((d) => { d.tests[0].result = 'FAIL'; }, /did not pass/);
      bad((d) => { d.tests[0].result = 'SKIP'; }, /did not pass/);
      bad((d) => { d.tests = d.tests.filter((t) => t.requirement !== 'FR-INVITE-QR'); }, /FR-INVITE-QR/);
      bad((d) => { delete d.tests.find((t) => t.requirement === 'FR-SETTINGS').screenshots.dark; }, /dark/);
      bad((d) => { d.tests.find((t) => t.requirement === 'FR-SETTINGS').screenshots.light = 'README.md'; }, /path/);
      bad((d) => { d.tests.find((t) => t.requirement === 'FR-PASTE').screenshots.light = `${FUNC}/../x.png`; }, /path/);
      bad((d) => { d.tests.find((t) => t.requirement === 'FR-SETTINGS').log = `${FUNC}/logs/missing.log`; }, /does not exist/);
      bad((d) => { delete d.tests.find((t) => t.requirement === 'FR-REMINDER-TOGGLE').baselineResult; }, /baseline/);
      bad((d) => { d.baseline.commit = CANDIDATE; }, /baseline/);
      bad((d) => { d.tests.push({ ...d.tests[0], requirement: 'FR-UNKNOWN' }); }, /unknown requirement/);
    } finally { rmSync(root, { recursive: true, force: true }); }
  }
  const root = setup('owner-test');
  try {
    rmSync(join(root, FUNC, 'results.json'));
    assert.throws(() => run(root, { stage: 'owner-test' }), /functional evidence .*missing/);
    writeFunctional(root);
    rmSync(join(root, FUNC, 'README.md'));
    assert.throws(() => run(root, { stage: 'owner-test' }), /README/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
