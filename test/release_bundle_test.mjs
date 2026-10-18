import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('checksum diagnostics accept only exact recognized installer errors', async () => {
  const { normalizeChecksumErrors } = await import('../tool/release_bundle.mjs');
  for (const message of [
    'The source file is corrupted',
    'Verification of the source file failed: The hash of the file is incorrect',
  ]) {
    assert.deepEqual(normalizeChecksumErrors(message), [message]);
    assert.deepEqual(normalizeChecksumErrors([message]), [message]);
  }
  for (const invalid of [undefined, null, 42, {}, [], '', [''], 'unknown error',
    ['The source file is corrupted', 'unknown error'], ['The source file is corrupted', 42]]) {
    assert.throws(() => normalizeChecksumErrors(invalid), /checksum/);
  }
});

test('owner installer verification remains pending and is bound to exact package bytes', async () => {
  const { verifyReleaseEvidence } = await import('../tool/release_bundle.mjs');
  const root = mkdtempSync(join(tmpdir(), 'budlark-release-evidence-'));
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  const source = 'a'.repeat(40), tag = 'v0.1.0-preview.15', version = tag.slice(1);
  const runId = '123';
  const packageBytes = Buffer.from('fixture installer bytes; not a genuine Windows installer');
  const packageDir = join(root, 'universal-output');
  const writeJson = (path, value) => writeFileSync(join(root, path), JSON.stringify(value));

  try {
    mkdirSync(packageDir);
    const installerFile = `Budlark-${version}-windows-universal-setup.exe`;
    writeFileSync(join(packageDir, installerFile), packageBytes);
    const payloadManifests = {};
    for (const arch of ['x64', 'arm64']) {
      const payload = JSON.stringify({ kind: 'budlark-release-payload-v1', source, version, arch });
      const path = `universal-output/payload-manifest-${arch}.json`;
      writeFileSync(join(root, path), payload);
      payloadManifests[arch] = sha(payload);
    }
    writeJson('universal-output/universal-manifest.json', {
      kind: 'budlark-offline-universal-v1', source, version, installerFile,
      installerSha256: sha(packageBytes), bytes: packageBytes.length, payloadManifests,
    });
    writeFileSync(join(packageDir, 'SHA256-universal.txt'), `${sha(packageBytes)}  ${installerFile}\n`);

    const options = { root, source, tag, runId };
    const evidence = verifyReleaseEvidence(options);
    assert.equal(evidence.source, source);
    assert.equal(evidence.tag, tag);
    assert.equal(evidence.actionsRunId, runId);
    assert.equal(evidence.ownerManualVerification.status, 'PENDING');
    assert.equal(evidence.ownerManualVerification.installerFile, installerFile);
    assert.equal(evidence.ownerManualVerification.installerSha256, sha(packageBytes));
    assert.equal(evidence.ownerManualVerification.requiredBeforeCustomerLaunch, true);
    assert.equal(evidence.ownerManualVerification.recordedResult, null);
    assert.match(evidence.installerAcceptance, /UNVERIFIED/);
    assert.doesNotMatch(JSON.stringify(evidence.ownerManualVerification), /PASS|SUCCESS/i);

    assert.throws(() => verifyReleaseEvidence({ ...options, source: 'b'.repeat(40) }), /identity/);
    assert.throws(() => verifyReleaseEvidence({ ...options, tag: 'v0.1.0-preview.16' }), /identity/);

    writeFileSync(join(packageDir, installerFile), 'tampered');
    assert.throws(() => verifyReleaseEvidence(options), /bytes|hash/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
