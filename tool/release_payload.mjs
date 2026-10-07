import { createHash } from 'node:crypto';
import { lstatSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
function identity({ arch, source, version }) {
  if (!['arm64', 'x64'].includes(arch) || !/^[a-f0-9]{40}$/.test(source) ||
      !/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(version)) {
    throw Error('Invalid release payload identity.');
  }
}
function files(root, prefix = '') {
  return readdirSync(join(root, prefix)).sort().flatMap(name => {
    const relative = prefix ? `${prefix}/${name}` : name;
    const stat = lstatSync(join(root, relative));
    if (stat.isSymbolicLink()) throw Error('Release payload must not contain symbolic links.');
    if (stat.isDirectory()) return files(root, relative);
    if (!stat.isFile() || stat.size === 0) throw Error(`Invalid payload file: ${relative}`);
    if (/(?:^|\/)(?:kernel_blob\.bin|installer-receipt\.json|server\.json)$/.test(relative)) {
      throw Error(`Synthetic/debug payload is not a genuine Release input: ${relative}`);
    }
    return [relative];
  });
}
export function peMachine(bytes) {
  if (bytes.length < 64 || bytes.subarray(0, 2).toString() !== 'MZ') throw Error('Invalid PE payload.');
  const offset = bytes.readUInt32LE(60);
  if (offset + 6 > bytes.length || bytes.subarray(offset, offset + 4).toString() !== 'PE\0\0') {
    throw Error('Invalid PE header.');
  }
  return bytes.readUInt16LE(offset + 4);
}
export function createPayloadManifest(root, expected) {
  identity(expected);
  const inventory = files(root);
  for (const required of ['bloomstep.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin']) {
    if (!inventory.includes(required)) throw Error(`Missing required Release payload: ${required}`);
  }
  const machine = expected.arch === 'arm64' ? 0xaa64 : 0x8664;
  for (const file of inventory.filter(file => /\.(exe|dll)$/i.test(file))) {
    if (peMachine(readFileSync(join(root, file))) !== machine) throw Error(`Wrong payload architecture: ${file}`);
  }
  return {
    kind: 'bloomstep-release-payload-v1',
    arch: expected.arch, source: expected.source, version: expected.version,
    files: inventory.map(path => {
      const bytes = readFileSync(join(root, path));
      return { path, bytes: bytes.length, sha256: sha256(bytes) };
    }),
  };
}
export function verifyPayloadManifest(root, manifest, expected) {
  identity(expected);
  if (manifest.kind !== 'bloomstep-release-payload-v1' || manifest.arch !== expected.arch ||
      manifest.source !== expected.source || manifest.version !== expected.version) {
    throw Error('Release payload identity mismatch.');
  }
  const actual = createPayloadManifest(root, expected);
  if (!Array.isArray(manifest.files) ||
      JSON.stringify(actual.files.map(file => file.path)) !== JSON.stringify(manifest.files.map(file => file.path))) {
    throw Error('Release payload inventory mismatch.');
  }
  for (let i = 0; i < actual.files.length; i++) {
    if (actual.files[i].bytes !== manifest.files[i].bytes || actual.files[i].sha256 !== manifest.files[i].sha256) {
      throw Error(`Release payload hash mismatch: ${actual.files[i].path}`);
    }
  }
  return actual;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [operation, root, manifestPath, arch, source, version] = process.argv.slice(2);
  if (!root || !manifestPath || !['create', 'verify'].includes(operation)) {
    throw Error('Usage: release_payload.mjs create|verify DIRECTORY MANIFEST ARCH SOURCE_SHA VERSION');
  }
  const expected = { arch, source, version };
  if (operation === 'create') {
    writeFileSync(manifestPath, `${JSON.stringify(createPayloadManifest(root, expected), null, 2)}\n`, { flag: 'wx' });
  } else {
    verifyPayloadManifest(root, JSON.parse(readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/, '')), expected);
  }
  console.log(`Verified ${arch} Release payload identity, native PE and complete byte inventory.`);
}
