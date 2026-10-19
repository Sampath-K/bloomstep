import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function validateManifest(manifest) {
  if (manifest?.channel !== 'internal-dogfood' ||
      manifest.acceptance !== 'manual-FAIL-not-an-accepted-release') {
    throw Error('Only explicitly unaccepted internal dogfood downloads may be staged.');
  }
  const source = manifest.source;
  if (source?.repositoryId !== 1404357574 ||
      !Number.isSafeInteger(source.runId) || source.runId <= 0 ||
      !Number.isSafeInteger(source.artifactId) || source.artifactId <= 0 ||
      source.artifactName !== 'budlark-universal-installer' ||
      !/^[a-f0-9]{40}$/.test(source.headSha ?? '')) {
    throw Error('Immutable Actions source binding required.');
  }
  if (!Array.isArray(manifest.files) || !manifest.files.length) throw Error('Download files required.');
  const names = new Set();
  let total = 0;
  for (const file of manifest.files) {
    for (const name of [file.sourceName, file.publicName]) {
      if (!/^Budlark-[0-9A-Za-z.-]+-windows-universal-setup\.exe$/.test(name ?? '')) {
        throw Error('Invalid installer filename.');
      }
    }
    if (names.has(file.publicName)) throw Error('Duplicate public filename.');
    names.add(file.publicName);
    if (!Number.isSafeInteger(file.bytes) || file.bytes <= 0 || file.bytes > 30 * 1024 * 1024 ||
        !/^[a-f0-9]{64}$/.test(file.sha256 ?? '')) throw Error('Invalid size or SHA-256.');
    total += file.bytes;
  }
  if (total > 150 * 1024 * 1024) throw Error('Free SWA download budget exceeded.');
  return manifest;
}

export async function verifySource(manifest, token, fetchImpl = fetch) {
  const { source } = validateManifest(manifest);
  if (!token) throw Error('Actions read token required.');
  const get = async path => {
    const response = await fetchImpl(`https://api.github.com/repositories/${source.repositoryId}/${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28' },
      redirect: 'error',
    });
    if (!response.ok) throw Error(`Actions metadata request failed: HTTP ${response.status}`);
    return response.json();
  };
  const [artifact, run] = await Promise.all([
    get(`actions/artifacts/${source.artifactId}`),
    get(`actions/runs/${source.runId}`),
  ]);
  if (artifact.id !== source.artifactId || artifact.name !== source.artifactName ||
      artifact.expired !== false || artifact.workflow_run?.id !== source.runId ||
      artifact.workflow_run?.head_sha !== source.headSha ||
      artifact.workflow_run?.repository_id !== run.repository?.id ||
      artifact.workflow_run?.head_repository_id !== run.repository?.id ||
      run.repository?.id !== source.repositoryId ||
      run.id !== source.runId || run.head_sha !== source.headSha ||
      run.path !== '.github/workflows/ci.yml' ||
      run.status !== 'completed' || run.conclusion !== 'success') {
    throw Error('Actions artifact/run provenance mismatch or expired artifact.');
  }
}

export async function stageDownloads(manifest, inputDir, outputDir) {
  validateManifest(manifest);
  const verified = [];
  for (const file of manifest.files) {
    const body = await readFile(join(inputDir, file.sourceName));
    const sha256 = createHash('sha256').update(body).digest('hex');
    if (body.length !== file.bytes || sha256 !== file.sha256) {
      throw Error(`Integrity mismatch: ${file.publicName}`);
    }
    verified.push({ file, body });
  }
  await mkdir(outputDir, { recursive: true });
  for (const { file, body } of verified) await writeFile(join(outputDir, file.publicName), body);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const manifest = JSON.parse(await readFile('site/downloads.json', 'utf8'));
  if (process.argv[2] === '--verify-source') {
    await verifySource(manifest, process.env.GH_TOKEN);
  } else {
    if (process.argv.length !== 4) throw Error('Usage: stage-downloads.mjs INPUT_DIR OUTPUT_DIR');
    await stageDownloads(manifest, process.argv[2], process.argv[3]);
  }
}
