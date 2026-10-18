import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const readJson = path => JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
const requireEvidence = (condition, message) => { if (!condition) throw new Error(message); };

export function normalizeChecksumErrors(value) {
  const lines = typeof value === 'string' ? [value] : value;
  const allowed = ['The source file is corrupted',
    'Verification of the source file failed: The hash of the file is incorrect'];
  requireEvidence(Array.isArray(lines) && lines.length > 0 &&
    lines.every(line => typeof line === 'string' && allowed.includes(line)),
  'Native checksum evidence must contain only exact recognized error strings.');
  return lines;
}

export function verifyReleaseEvidence({ root, source, tag, runId, auditOnly = false }) {
  requireEvidence(/^[a-f0-9]{40}$/.test(source) && /^\d+$/.test(runId), 'Invalid release source/run identity.');
  requireEvidence(!auditOnly || tag === 'v0.1.0-preview.11', 'Audit-only mode is restricted to the historical preview11 tag.');
  const packageDir = join(root, 'universal-output');
  const manifest = readJson(join(packageDir, 'universal-manifest.json'));
  const expectedName = `Budlark-${tag.slice(1)}-windows-universal-setup.exe`;
  requireEvidence(manifest.kind === 'budlark-offline-universal-v1' && manifest.source === source &&
    tag === `v${manifest.version}` && manifest.installerFile === expectedName,
  'Release package source/version/name identity mismatch.');
  const bytes = readFileSync(join(packageDir, expectedName));
  requireEvidence(bytes.length === manifest.bytes && digest(bytes) === manifest.installerSha256,
    'Release package bytes/hash mismatch.');
  const checksum = readFileSync(join(packageDir, 'SHA256-universal.txt'), 'utf8').replace(/^\uFEFF/, '').trim();
  requireEvidence(checksum === `${manifest.installerSha256}  ${expectedName}`, 'Release checksum authority mismatch.');
  for (const arch of ['x64', 'arm64']) {
    const payloadFile = join(packageDir, `payload-manifest-${arch}.json`);
    const payload = readJson(payloadFile);
    requireEvidence(digest(readFileSync(payloadFile)) === manifest.payloadManifests[arch] &&
      payload.kind === 'budlark-release-payload-v1' && payload.source === source &&
      payload.version === manifest.version && payload.arch === arch,
    `Same-run ${arch} payload manifest identity/hash mismatch.`);
  }
  return {
    kind: 'budlark-owner-trial-release-evidence-v1',
    source,
    tag,
    actionsRunId: runId,
    publicationAuthorized: !auditOnly,
    origin: `https://github.com/Sampath-K/budlark/actions/runs/${runId}`,
    package: manifest,
    installerAcceptance: 'UNVERIFIED: owner manual installer verification pending',
    ownerManualVerification: {
      status: 'PENDING',
      installerFile: expectedName,
      installerSha256: manifest.installerSha256,
      requiredBeforeCustomerLaunch: true,
      recordedResult: null,
    },
    publicPointer: 'v0.1.0-preview.14',
    ownerAcceptance: 'PENDING',
    crossRunBinaryEquivalence: 'Not asserted. Package bytes and both architecture manifests are bound to this run.',
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [, , root, source, tag, runId, mode] = process.argv;
  requireEvidence(mode === undefined || mode === '--audit-failed-preview11',
    'Unknown publication/audit mode.');
  const receipt = verifyReleaseEvidence({ root, source, tag, runId, auditOnly: mode !== undefined });
  const output = join(root, mode ? 'release-proof-audit-NOT-FOR-PUBLICATION' : 'release-proof');
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'release-evidence.json'), `${JSON.stringify(receipt, null, 2)}\n`);
  const url = `https://github.com/Sampath-K/budlark/releases/download/${tag}`;
  const checklist = `# Budlark owner manual installer verification — ${tag}\n\n` +
    `Status: **PENDING**. The owner must verify this exact installer before customer launch. CI did not install or launch it; this record does not imply a pass.\n\n` +
    `- Installer: \`${receipt.ownerManualVerification.installerFile}\`\n` +
    `- SHA-256: \`${receipt.ownerManualVerification.installerSha256}\`\n` +
    `- Source commit: \`${source}\`\n` +
    `- Package: [${receipt.ownerManualVerification.installerFile}](${url}/${receipt.ownerManualVerification.installerFile})\n` +
    `- Observed Windows version/architecture: **not recorded**\n` +
    `- Install and checked/unchecked Finish outcome: **not recorded**\n` +
    `- Owner feedback/result: **not recorded**\n\n` +
    `Record only what was actually observed. A single-machine result covers only that tested machine/architecture. Stop on security warnings or policy blocks; do not bypass protection. Hash consistency does not prove safety or signing.\n`;
  writeFileSync(join(output, 'owner-trial-checklist.md'), checklist);
  writeFileSync(join(output, 'evidence-notes.md'),
    `## Budlark owner-test installer\n\n` +
    `The exact package is [${receipt.ownerManualVerification.installerFile}](${url}/${receipt.ownerManualVerification.installerFile}).\n\n` +
    `SHA-256: \`${receipt.ownerManualVerification.installerSha256}\`\n\n` +
    `Source \`${source}\`; same-run package manifest and x64/ARM64 payload manifests are hash-bound in [run ${runId}](${receipt.origin}). ` +
    `Installer acceptance remains **UNVERIFIED; owner manual verification pending**. No VM runner or customer-launch pass is claimed.\n`);
  console.log(`${mode ? 'AUDIT ONLY, NOT AUTHORIZED FOR PUBLICATION: ' : ''}Verified package bytes and x64/ARM64 payload manifests; owner manual verification remains PENDING.`);
}
