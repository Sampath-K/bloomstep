import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile, rm, access } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { stageDownloads, validateManifest, verifySource } from '../stage-downloads.mjs';

const manifest = JSON.parse(readFileSync(new URL('../downloads.json', import.meta.url)));
const workflow = readFileSync(new URL('../../.github/workflows/azure.yml', import.meta.url), 'utf8');
const config = JSON.parse(readFileSync(new URL('../staticwebapp.config.json', import.meta.url)));
const copy = () => structuredClone(manifest);

test('dogfood manifest pins the authorized source and exact installer', () => {
  validateManifest(manifest);
  assert.deepEqual(manifest.source, {
    repositoryId: 1404357574, runId: 39134443648, artifactId: 12140076664,
    artifactName: 'budlark-universal-installer',
    headSha: '2d762c487e496ca2d856e8b160390fe3e9a7b2b7',
  });
  assert.equal(manifest.files[0].bytes, 22392273);
  assert.equal(manifest.files[0].sha256, 'b53767c405fa9b704fb828d221f883b81d14231e3ebf65dd8820d3812fd42a2c');
  assert.equal(manifest.files[0].publicName, 'Budlark-0.1.0-windows-universal-setup.exe');
  assert.match(workflow, new RegExp(`run-id: ${manifest.source.runId}`));
  assert.match(workflow, new RegExp(`artifact-ids: ${manifest.source.artifactId}`));
  assert.match(workflow, /repository: \$\{\{ github\.repository \}\}/);
  assert.ok(workflow.indexOf('--verify-source') < workflow.indexOf('uses: actions/download-artifact'));
  assert.ok(workflow.indexOf('deploy-site/downloads') < workflow.indexOf('uses: Azure/static-web-apps-deploy'));
});

test('manifest rejects release promotion, traversal, duplicates, invalid hashes and sizes', () => {
  for (const mutate of [
    m => { m.channel = 'stable'; },
    m => { m.acceptance = 'PASS'; },
    m => { m.source.repositoryId = '1404357574'; },
    m => { m.source.repositoryId = 1; },
    m => { m.source.runId = 'latest'; },
    m => { m.source.artifactId = 0; },
    m => { m.source.headSha = 'main'; },
    m => { m.files = []; },
    m => { m.files[0].publicName = '../Budlark-1-windows-universal-setup.exe'; },
    m => { m.files[0].sourceName = '../source.exe'; },
    m => { m.files[0].sha256 = 'abc'; },
    m => { m.files[0].bytes = 31 * 1024 * 1024; },
    m => { m.files.push(m.files[0]); },
  ]) {
    const bad = copy();
    mutate(bad);
    assert.throws(() => validateManifest(bad));
  }
});

function metadata() {
  const source = manifest.source;
  return {
    artifact: { id: source.artifactId, name: source.artifactName, expired: false,
      workflow_run: { id: source.runId, head_sha: source.headSha,
        repository_id: 1404357574, head_repository_id: 1404357574 } },
    run: { id: source.runId, head_sha: source.headSha, status: 'completed', conclusion: 'success',
      path: '.github/workflows/ci.yml', repository: { id: 1404357574 } },
  };
}

test('source verification binds artifact ID, run, repository, commit and successful CI', async () => {
  const fetchMetadata = data => async (url, options) => {
    assert.ok(url.startsWith('https://api.github.com/repositories/1404357574/actions/'));
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer test-token');
    return Response.json(url.includes('/artifacts/') ? data.artifact : data.run);
  };
  await verifySource(manifest, 'test-token', fetchMetadata(metadata()));
  for (const mutate of [
    d => { d.artifact.id++; },
    d => { d.artifact.name = 'replacement'; },
    d => { d.artifact.expired = true; },
    d => { d.artifact.workflow_run.id++; },
    d => { d.artifact.workflow_run.head_sha = '0'.repeat(40); },
    d => { d.artifact.workflow_run.head_repository_id++; },
    d => { d.run.id++; },
    d => { d.run.head_sha = '0'.repeat(40); },
    d => { d.run.repository.id++; },
    d => { d.run.path = '.github/workflows/other.yml'; },
    d => { d.run.status = 'in_progress'; },
    d => { d.run.conclusion = 'failure'; },
  ]) {
    const data = metadata();
    mutate(data);
    await assert.rejects(verifySource(manifest, 'test-token', fetchMetadata(data)), /provenance/);
  }
  await assert.rejects(verifySource(manifest, ''), /token/);
  await assert.rejects(verifySource(manifest, 'test-token', async () => new Response('', { status: 403 })), /HTTP 403/);
});

test('staging publishes only exact bytes and fails before writing mismatches', async () => {
  const dir = await mkdtemp(join(process.cwd(), '.dogfood-test-'));
  try {
    const body = Buffer.from('verified installer fixture');
    const fixture = copy();
    fixture.files[0].bytes = body.length;
    fixture.files[0].sha256 = createHash('sha256').update(body).digest('hex');
    await writeFile(join(dir, fixture.files[0].sourceName), body);
    await stageDownloads(fixture, dir, join(dir, 'out'));
    assert.deepEqual(await readFile(join(dir, 'out', fixture.files[0].publicName)), body);
    await writeFile(join(dir, fixture.files[0].sourceName), Buffer.alloc(body.length));
    await assert.rejects(stageDownloads(fixture, dir, join(dir, 'bad')), /Integrity/);
    await assert.rejects(access(join(dir, 'bad')));
    await writeFile(join(dir, fixture.files[0].sourceName), body.subarray(1));
    await assert.rejects(stageDownloads(fixture, dir, join(dir, 'bad')), /Integrity/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('reserved URL is binary, unindexed, and not cached as an immutable general release', () => {
  assert.equal(config.mimeTypes['.exe'], 'application/octet-stream');
  const route = config.routes.find(r => r.route === '/downloads/*');
  assert.equal(route.headers['Cache-Control'], 'no-store');
  assert.match(route.headers['X-Robots-Tag'], /noindex/);
});
