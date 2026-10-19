import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stageDownloads, validateManifest } from '../stage-downloads.mjs';

const manifest = JSON.parse(readFileSync(new URL('../downloads.json', import.meta.url)));
const config = JSON.parse(readFileSync(new URL('../staticwebapp.config.json', import.meta.url)));
const entry = (overrides = {}) => ({ ...manifest.files[0], ...overrides });

test('checked-in manifest is valid and pinned to verified bytes', () => {
  const files = validateManifest(manifest);
  assert.ok(files.length >= 1);
  assert.ok(files.every(file => file.publicName.startsWith('Budlark-')));
});

test('malformed manifest entries fail closed', () => {
  for (const bad of [
    entry({ publicName: 'Setup.exe' }),
    entry({ publicName: '../Budlark-1-windows-universal-setup.exe' }),
    entry({ source: 'http://example.com/a.exe' }),
    entry({ sha256: 'abc' }),
    entry({ bytes: 0 }),
    entry({ bytes: 31 * 1024 * 1024 }),
  ]) assert.throws(() => validateManifest({ files: [bad] }));
  assert.throws(() => validateManifest({ files: [entry(), entry()] }), /Duplicate/);
  assert.throws(() => validateManifest({}), /files array/);
});

test('staging writes verified bytes and rejects tampered downloads', async () => {
  const body = Buffer.from('installer-bytes');
  const file = entry({ sha256: createHash('sha256').update(body).digest('hex'), bytes: body.length });
  const dir = await mkdtemp(join(tmpdir(), 'downloads-'));
  const manifestPath = join(dir, 'm.json');
  await writeFile(manifestPath, JSON.stringify({ files: [file] }));
  const ok = async () => new Response(body);
  await stageDownloads(manifestPath, join(dir, 'out'), ok);
  assert.deepEqual(await readFile(join(dir, 'out', file.publicName)), body);
  await assert.rejects(stageDownloads(manifestPath, join(dir, 'bad'), async () => new Response('tampered!!!!!!!')), /Integrity/);
  await assert.rejects(stageDownloads(manifestPath, join(dir, 'gone'), async () => new Response('', { status: 404 })), /Download failed/);
});

test('downloads are served as immutable binaries', () => {
  assert.equal(config.mimeTypes['.exe'], 'application/octet-stream');
  const route = config.routes.find(r => r.route === '/downloads/*');
  assert.match(route.headers['Cache-Control'], /immutable/);
});
