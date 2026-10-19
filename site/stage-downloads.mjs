import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const MAX_TOTAL_BYTES = 150 * 1024 * 1024;
const MAX_FILE_BYTES = 30 * 1024 * 1024;

export function validateManifest(manifest) {
  if (!manifest || !Array.isArray(manifest.files)) throw new Error('Download manifest needs a files array.');
  const names = new Set();
  let total = 0;
  for (const file of manifest.files) {
    if (!/^Budlark-[0-9A-Za-z.-]+-windows-(universal|x64|arm64)-setup\.exe$/.test(file?.publicName ?? '')) {
      throw new Error(`Invalid public download name: ${file?.publicName}`);
    }
    if (names.has(file.publicName)) throw new Error(`Duplicate public download name: ${file.publicName}`);
    names.add(file.publicName);
    if (!/^https:\/\/github\.com\/Sampath-K\/[^/]+\/releases\/download\/[^/]+\/[^/]+\.exe$/.test(file.source ?? '')) {
      throw new Error(`Download source must be a GitHub release asset: ${file.publicName}`);
    }
    if (!/^[0-9a-f]{64}$/.test(file.sha256 ?? '')) throw new Error(`Invalid sha256: ${file.publicName}`);
    if (!Number.isInteger(file.bytes) || file.bytes <= 0 || file.bytes > MAX_FILE_BYTES) {
      throw new Error(`Invalid size (Free SWA file limit is 30 MB): ${file.publicName}`);
    }
    total += file.bytes;
  }
  if (total > MAX_TOTAL_BYTES) throw new Error('Hosted downloads exceed the 150 MB budget of the 250 MB Free SWA quota.');
  return manifest.files;
}

export async function stageDownloads(manifestPath, outputDir, fetchImpl = fetch) {
  const files = validateManifest(JSON.parse(await readFile(manifestPath, 'utf8')));
  await mkdir(outputDir, { recursive: true });
  for (const file of files) {
    const response = await fetchImpl(file.source);
    if (!response.ok) throw new Error(`Download failed (${response.status}): ${file.source}`);
    const body = Buffer.from(await response.arrayBuffer());
    const sha256 = createHash('sha256').update(body).digest('hex');
    if (body.length !== file.bytes || sha256 !== file.sha256) {
      throw new Error(`Integrity mismatch for ${file.publicName}: ${body.length} bytes, ${sha256}`);
    }
    await writeFile(join(outputDir, file.publicName), body);
  }
  return files;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [manifestPath = 'site/downloads.json', outputDir = 'deploy-site/downloads'] = process.argv.slice(2);
  const files = await stageDownloads(manifestPath, outputDir);
  for (const file of files) console.log(`${file.publicName} ${file.bytes} ${file.sha256}`);
}
