import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
test('universal installer bundles exclusive native OS payloads without bootstrap or privilege changes', () => {
  const source = read('packaging/bloomstep.iss');
  assert.match(source, /#if AppArch == "universal"[\s\S]*ArchitecturesAllowed=arm64 or x64os/);
  assert.match(source, /Source: "\{#SourceDirX64\}\\\*";.*Check: UseX64Payload/);
  assert.match(source, /Source: "\{#SourceDirArm64\}\\\*";.*Check: UseArm64Payload/);
  assert.match(source, /function UseX64Payload[\s\S]*Result := ProcessorArchitecture = paX64/);
  assert.match(source, /function UseArm64Payload[\s\S]*Result := ProcessorArchitecture = paArm64/);
  assert.match(source, /PrivilegesRequired=lowest/);
  assert.match(source, /postinstall skipifsilent runasoriginaluser/);
  assert.doesNotMatch(source, /DownloadTemporaryFile|dontverifychecksum|skipifsourcedoesntexist|PrivilegesRequired=admin/);
});
test('universal packaging remains required and source-pinned, next release has no preview10 launch exception', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-installer:/);
  assert.match(workflow, /universal-native-proof:/);
  assert.match(workflow, /release_payload\.mjs verify/);
  assert.match(workflow, /payload-manifest-/);
  assert.match(workflow, /needs: \[api, test-and-build-windows, installer-launch-evidence, universal-native-proof\]/);
  assert.match(workflow, /github\.ref_name == 'v0\.1\.0-preview\.10'/);
  assert.doesNotMatch(workflow, /github\.ref_name == 'v0\.1\.0-preview\.11'/);
});
test('release inputs require exact source, version, architecture, inventory and byte hashes', async () => {
  const { createPayloadManifest, verifyPayloadManifest } = await import('../tool/release_payload.mjs');
  const root = mkdtempSync(join(tmpdir(), 'bloomstep-payload-contract-'));
  const source = 'a'.repeat(40), version = '0.1.0-preview.11';
  const pe = Buffer.alloc(128); pe.write('MZ'); pe.writeUInt32LE(64, 60);
  pe.write('PE\0\0', 64); pe.writeUInt16LE(0xaa64, 68);
  try {
    mkdirSync(join(root, 'data', 'flutter_assets'), { recursive: true });
    for (const file of ['bloomstep.exe', 'flutter_windows.dll']) writeFileSync(join(root, file), pe);
    writeFileSync(join(root, 'data', 'icudtl.dat'), 'fixture only');
    writeFileSync(join(root, 'data', 'flutter_assets', 'AssetManifest.bin'), 'fixture only');
    const manifest = createPayloadManifest(root, { arch: 'arm64', source, version });
    assert.equal(verifyPayloadManifest(root, manifest, { arch: 'arm64', source, version }).arch, 'arm64');
    assert.throws(() => verifyPayloadManifest(root, manifest, { arch: 'x64', source, version }), /identity|architecture/);
    assert.throws(() => verifyPayloadManifest(root, manifest, { arch: 'arm64', source: 'b'.repeat(40), version }), /identity/);
    assert.throws(() => verifyPayloadManifest(root, manifest, { arch: 'arm64', source, version: '0.1.0-preview.10' }), /identity/);
    writeFileSync(join(root, 'unexpected.dll'), pe);
    assert.throws(() => verifyPayloadManifest(root, manifest, { arch: 'arm64', source, version }), /inventory/);
    rmSync(join(root, 'unexpected.dll'));
    writeFileSync(join(root, 'kernel_blob.bin'), 'debug fixture');
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /debug/);
    rmSync(join(root, 'kernel_blob.bin'));
    mkdirSync(join(root, 'outside'));
    symlinkSync(join(root, 'outside'), join(root, 'linked'), 'junction');
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /symbolic/);
    rmSync(join(root, 'linked'));
    rmSync(join(root, 'outside'), { recursive: true });
    writeFileSync(join(root, 'data', 'icudtl.dat'), 'corrupt');
    assert.throws(() => verifyPayloadManifest(root, manifest, { arch: 'arm64', source, version }), /hash/);
    rmSync(join(root, 'bloomstep.exe'));
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /required|missing/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('native routing source semantics reject unsupported hosts even with a misleading process architecture (simulation only)', () => {
  const source = read('packaging/bloomstep.iss');
  const selector = name => new RegExp(`function ${name}\\(\\): Boolean;\\s*begin\\s*Result := ProcessorArchitecture = (pa\\w+);\\s*end;`).exec(source)?.[1];
  assert.equal(selector('UseX64Payload'), 'paX64');
  assert.equal(selector('UseArm64Payload'), 'paArm64');
  for (const [native, process, expected] of [
    ['paX64','paX64','x64'], ['paX64','paX86','x64'],
    ['paArm64','paArm64','arm64'], ['paArm64','paX64','arm64'], ['paArm64','paX86','arm64'],
    ['paX86','paX86',null], ['paArm32','paX86',null], ['paUnknown','paX64',null],
  ]) {
    const selected = native === selector('UseX64Payload') ? 'x64' : native === selector('UseArm64Payload') ? 'arm64' : null;
    assert.equal(selected, expected, `${native} with process ${process}`);
  }
  assert.match(source, /ArchitecturesAllowed=arm64 or x64os/);
});
test('unified customer download is fail-closed while the live public pointer remains preview9', async () => {
  const { renderDownloads, validateRelease } = await import('../site/release-downloads.mjs');
  const current = JSON.parse(read('site/customer-config.json'));
  assert.equal(current.release.tag, 'v0.1.0-preview.9');
  assert.equal(current.release.universal, undefined);
  const release = {
    ...current.release, tag: 'v0.1.0-preview.11',
    ...Object.fromEntries(['arm64','x64','universal'].map(arch => [arch, {
      url: `https://github.com/Sampath-K/bloomstep/releases/download/v0.1.0-preview.11/Bloomstep-0.1.0-preview.11-windows-${arch}-setup.exe`,
      sha256: 'a'.repeat(64),
    }])),
  };
  validateRelease(release);
  assert.throws(() => validateRelease({ ...release, universal: { ...release.universal, url: 'https://evil.example/download.exe' } }));
  assert.throws(() => validateRelease({ ...release, universal: { ...release.universal, sha256: '' } }));
  const original = read('site/index.html');
  assert.equal(renderDownloads(original, current.release), original);
  const html = renderDownloads(original, release);
  assert.match(html, /data-universal-download/);
  assert.match(html, /data-download="unknown"[^>]*>Download Bloomstep for Windows/);
  assert.match(html, /Windows selects the native x64 or ARM64 payload/);
  assert.match(html, /<details[^>]*>[\s\S]*Secondary architecture-specific downloads/);
  assert.doesNotMatch(html, /data-universal-download[\s\S]*?<div class="choices"/);
});
test('actual proof requires package and native machine authority, cancel, installed hashes and corrupt rollback', () => {
  const proof = read('tool/verify_universal_installer.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /manifest\.source -ne \$source/);
  assert.match(proof, /\/platform:x64/);
  assert.match(proof, /processMachine -ne 0x8664/);
  assert.match(proof, /cancelBeforePayload/);
  assert.match(proof, /selectedPayloadAllHashesVerified/);
  assert.match(proof, /corruptedEmbeddedChecksumRollbackVerified/);
  const source = read('packaging/bloomstep.iss');
  assert.match(source, /#ifdef UniversalIntegrityFixture[\s\S]*#ifndef OnboardingJourneyFixture[\s\S]*#error/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-integrity-fixture/);
  assert.doesNotMatch(workflow, /gh release create[^\n]*integrity/);
});
