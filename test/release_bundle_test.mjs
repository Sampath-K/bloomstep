import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('actual tag37603771331 x64 and ARM64 checksum receipt strings are recognized without weakening text', async () => {
  const { normalizeChecksumErrors } = await import('../tool/release_bundle.mjs');
  // Exact sanitized field excerpts from both failed-publication tag receipts.
  const observed = [
    { architecture: 'x64', checksumErrorLines: 'The source file is corrupted' },
    { architecture: 'arm64', checksumErrorLines: 'The source file is corrupted' },
  ];
  for (const receipt of observed) {
    assert.deepEqual(normalizeChecksumErrors(receipt.checksumErrorLines), ['The source file is corrupted']);
  }
  assert.deepEqual(normalizeChecksumErrors(['The source file is corrupted']), ['The source file is corrupted']);
  for (const bad of [undefined, null, 42, {}, [], '', [''], 'Command: universal-corrupt',
    ['The source file is corrupted', 'unrecognized'], ['The source file is corrupted', 42]]) {
    assert.throws(() => normalizeChecksumErrors(bad), /checksum/);
  }
});

test('manual trial publication binds bytes/native frames/launch blocker within one tag run', async () => {
  const { verifyReleaseEvidence } = await import('../tool/release_bundle.mjs');
  const root = mkdtempSync(join(tmpdir(), 'bloomstep-release-evidence-'));
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  const source = 'a'.repeat(40), tag = 'v0.1.0-preview.12', version = tag.slice(1);
  const options = { root, source, tag, runId: '123', genuineResult: 'failure' };
  const json = (path, value) => writeFileSync(join(root, path), JSON.stringify(value));
  const packageBytes = Buffer.from('synthetic package bytes; not genuine Windows evidence');
  const image = Buffer.from('synthetic frame bytes; hash-binding contract only');
  try {
    mkdirSync(join(root, 'universal-output'));
    const name = `Bloomstep-${version}-windows-universal-setup.exe`;
    writeFileSync(join(root, 'universal-output', name), packageBytes);
    const manifests = {};
    for (const arch of ['x64', 'arm64']) {
      const manifest = JSON.stringify({ kind: 'bloomstep-release-payload-v1', source, version, arch });
      writeFileSync(join(root, 'universal-output', `payload-manifest-${arch}.json`), manifest);
      manifests[arch] = sha(manifest);
      mkdirSync(join(root, `native-${arch}`));
      mkdirSync(join(root, `launch-${arch}`));
      writeFileSync(join(root, `native-${arch}`, 'actual-universal-welcome.png'), image);
      json(`native-${arch}/universal-native-receipt.json`, {
        source, architecture: arch, packageSha256: sha(packageBytes), outcome: 'success',
        selectedPayloadAllHashesVerified: true, nonSelectedPayloadNotInstalled: true,
        defaultOffObservationReceiptAbsent: true, uninstallVerified: true,
        corruptedEmbeddedChecksumRollbackVerified: true, corruptMarkerAndPayloadAbsent: true,
        cancelWizardExitCode: 2, cancelLauncherExitCode: 2, corruptExitCode: 5,
        checksumErrorLines: 'The source file is corrupted',
        installedPeMachine: arch === 'x64' ? 0x8664 : 0xaa64,
        nativeArchitectureProbe: { nativeArchitecture: arch, processMachine: 0x8664 },
        welcome: { file: 'actual-universal-welcome.png', sha256: sha(image) },
      });
      json(`launch-${arch}/genuine-universal-app-launch-receipt.json`, {
        source, architecture: arch, installerSha256: sha(packageBytes), outcome: 'UNVERIFIED',
        workerTokenElevated: true, workerInteractive: true, modes: [],
      });
    }
    const manifest = {
      kind: 'bloomstep-offline-universal-v1', source, version, installerFile: name,
      installerSha256: sha(packageBytes), bytes: packageBytes.length, payloadManifests: manifests,
    };
    json('universal-output/universal-manifest.json', manifest);
    writeFileSync(join(root, 'universal-output', 'SHA256-universal.txt'), `${sha(packageBytes)}  ${name}\n`);
    assert.equal(verifyReleaseEvidence(options).genuineLaunch, 'UNVERIFIED: elevated hosted worker stopped before installation; owner manual trial pending');
    assert.throws(() => verifyReleaseEvidence({ ...options, tag: 'v0.1.0-preview.13' }), /identity|exception/);
    assert.throws(() => verifyReleaseEvidence({ ...options, source: 'b'.repeat(40) }), /identity/);
    manifest.installerSha256 = 'b'.repeat(64);
    json('universal-output/universal-manifest.json', manifest);
    assert.throws(() => verifyReleaseEvidence(options), /bytes|hash/);
    manifest.installerSha256 = sha(packageBytes);
    json('universal-output/universal-manifest.json', manifest);
    writeFileSync(join(root, 'native-arm64', 'actual-universal-welcome.png'), 'different run frame');
    assert.throws(() => verifyReleaseEvidence(options), /frame/);
    writeFileSync(join(root, 'native-arm64', 'actual-universal-welcome.png'), image);
    const nativePath = 'native-x64/universal-native-receipt.json';
    const { readFileSync } = await import('node:fs');
    const native = JSON.parse(readFileSync(join(root, nativePath), 'utf8'));
    for (const valid of [['The source file is corrupted'], 'The source file is corrupted']) {
      native.checksumErrorLines = valid;
      json(nativePath, native);
      assert.ok(verifyReleaseEvidence(options));
    }
    for (const bad of [null, undefined, 42, {}, [], [''], 'Error in universal-corrupt path',
      ['The source file is corrupted', 'unknown error'], ['The source file is corrupted', 42]]) {
      native.checksumErrorLines = bad;
      json(nativePath, native);
      assert.throws(() => verifyReleaseEvidence(options), /checksum/);
    }
    native.checksumErrorLines = 'The source file is corrupted';
    native.corruptExitCode = 0;
    json(nativePath, native);
    assert.throws(() => verifyReleaseEvidence(options), /checksum/);
    native.corruptExitCode = 5;
    json(nativePath, native);
    writeFileSync(join(root, 'native-x64', 'actual-universal-destination.png'), image);
    native.entry = { page: 'destination', file: 'actual-universal-destination.png', sha256: sha(image) };
    delete native.welcome;
    json(nativePath, native);
    assert.equal(verifyReleaseEvidence(options).native.x64.entry.page, 'destination');
    for (const invalid of [
      { ...native.entry, page: 'ready' },
      { ...native.entry, file: '../actual-universal-destination.png' },
      { ...native.entry, sha256: '0'.repeat(64) },
    ]) {
      json(nativePath, { ...native, entry: invalid });
      assert.throws(() => verifyReleaseEvidence(options), /frame/);
    }
    json(nativePath, native);
    json('launch-x64/genuine-universal-app-launch-receipt.json', {
      source, architecture: 'x64', installerSha256: sha(packageBytes), outcome: 'UNVERIFIED',
      workerTokenElevated: false, modes: [],
    });
    assert.throws(() => verifyReleaseEvidence(options), /elevated|exception/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
