import { readFileSync, writeFileSync } from 'node:fs';

const [installer, marker, output] = process.argv.slice(2);
if (!installer || !marker || !output || installer === output) {
  throw Error('Usage: corrupt_fixture_payload.mjs ISOLATED_INSTALLER MARKER CORRUPTED_COPY');
}
const bytes = readFileSync(installer);
const target = readFileSync(marker);
if (target.length < 1024) throw Error('Bounded checksum marker must be at least 1024 bytes.');
const offset = bytes.indexOf(target);
if (offset < 0 || bytes.indexOf(target, offset + 1) !== -1) {
  throw Error('Isolated uncompressed marker must occur exactly once.');
}
bytes[offset + Math.floor(target.length / 2)] ^= 1;
writeFileSync(output, bytes, { flag: 'wx' });
console.log('Corrupted exactly one embedded isolated marker byte; no public package overwritten.');
