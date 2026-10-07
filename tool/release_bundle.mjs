import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
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

export function verifyReleaseEvidence({ root, source, tag, runId, genuineResult, auditOnly = false }) {
  requireEvidence(/^[a-f0-9]{40}$/.test(source) && /^\d+$/.test(runId), 'Invalid release source/run identity.');
  const packageDir = join(root, 'universal-output');
  const manifest = readJson(join(packageDir, 'universal-manifest.json'));
  const expectedName = `Bloomstep-${tag.slice(1)}-windows-universal-setup.exe`;
  requireEvidence(manifest.kind === 'bloomstep-offline-universal-v1' && manifest.source === source &&
    tag === `v${manifest.version}` && manifest.installerFile === expectedName, 'Release package source/version/name identity mismatch.');
  const bytes = readFileSync(join(packageDir, expectedName));
  requireEvidence(bytes.length === manifest.bytes && digest(bytes) === manifest.installerSha256,
    'Release package bytes/hash mismatch.');
  const checksum = readFileSync(join(packageDir, 'SHA256-universal.txt'), 'utf8').replace(/^\uFEFF/, '').trim();
  requireEvidence(checksum === `${manifest.installerSha256}  ${expectedName}`, 'Release checksum authority mismatch.');
  const native = {}, launch = {};
  for (const arch of ['x64', 'arm64']) {
    const payloadFile = join(packageDir, `payload-manifest-${arch}.json`);
    const payload = readJson(payloadFile);
    requireEvidence(digest(readFileSync(payloadFile)) === manifest.payloadManifests[arch] &&
      payload.kind === 'bloomstep-release-payload-v1' && payload.source === source &&
      payload.version === manifest.version && payload.arch === arch, 'Same-run payload manifest identity/hash mismatch.');
    const proof = readJson(join(root, `native-${arch}`, 'universal-native-receipt.json'));
    requireEvidence(proof.source === source && proof.architecture === arch &&
      proof.packageSha256 === manifest.installerSha256 && proof.outcome === 'success',
    'Native receipt source/package/run binding mismatch.');
    for (const key of ['selectedPayloadAllHashesVerified', 'nonSelectedPayloadNotInstalled',
      'defaultOffObservationReceiptAbsent', 'uninstallVerified', 'corruptedEmbeddedChecksumRollbackVerified',
      'corruptMarkerAndPayloadAbsent']) {
      requireEvidence(proof[key] === true, `Native lifecycle requirement missing: ${key}`);
    }
    normalizeChecksumErrors(proof.checksumErrorLines);
    requireEvidence(proof.cancelWizardExitCode === 2 && proof.cancelLauncherExitCode === 2 &&
      proof.corruptExitCode === 5,
    'Native cancellation/checksum rollback evidence missing.');
    requireEvidence(proof.installedPeMachine === (arch === 'x64' ? 0x8664 : 0xaa64) &&
      proof.nativeArchitectureProbe.nativeArchitecture === arch &&
      proof.nativeArchitectureProbe.processMachine === 0x8664, 'Actual native/emulated process routing mismatch.');
    const frame = proof.entry ?? proof.welcome;
    requireEvidence(frame && (proof.entry ?
      frame.page === 'destination' && frame.file === 'actual-universal-destination.png' :
      frame.file === 'actual-universal-welcome.png') &&
      digest(readFileSync(join(root, `native-${arch}`, frame.file))) === frame.sha256,
    'Same-run actual entry frame hash mismatch.');
    native[arch] = proof;
    const result = readJson(join(root, `launch-${arch}`, 'genuine-universal-app-launch-receipt.json'));
    requireEvidence(result.source === source && result.architecture === arch &&
      result.installerSha256 === manifest.installerSha256, 'Genuine launch source/package/run binding mismatch.');
    if (genuineResult === 'success') {
      requireEvidence(result.outcome === 'PASS actual checked/unchecked genuine app launch only' &&
        result.modes?.length === 2, 'Genuine checked/unchecked successful evidence missing.');
    } else {
      requireEvidence((tag === 'v0.1.0-preview.12' || (auditOnly && tag === 'v0.1.0-preview.11')) && genuineResult === 'failure' &&
        result.outcome === 'UNVERIFIED' && result.workerTokenElevated === true &&
        result.workerInteractive === true && Array.isArray(result.modes) && result.modes.length === 0,
      'Exact preview12 manual-trial exception requires elevated pre-install guard evidence, not arbitrary failure.');
    }
    launch[arch] = result;
  }
  return {
    kind: 'bloomstep-same-run-owner-trial-release-evidence-v1', source, tag, actionsRunId: runId,
    publicationAuthorized: !auditOnly,
    origin: `https://github.com/Sampath-K/bloomstep/actions/runs/${runId}`,
    package: manifest, native, launch,
    genuineLaunch: genuineResult === 'success' ? 'PASS automated checked/unchecked only; full owner journey pending' :
      'UNVERIFIED: elevated hosted worker stopped before installation; owner manual trial pending',
    publicPointer: 'v0.1.0-preview.9', ownerAcceptance: 'PENDING',
    crossRunBinaryEquivalence: 'Not asserted. Same-source packaging can differ; all evidence is bound within this one run.',
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [, , root, source, tag, runId, genuineResult, mode] = process.argv;
  requireEvidence(mode === undefined || (mode === '--audit-failed-preview11' && tag === 'v0.1.0-preview.11'),
    'Unknown publication/audit mode.');
  const receipt = verifyReleaseEvidence({ root, source, tag, runId, genuineResult, auditOnly: mode !== undefined });
  const output = join(root, mode ? 'release-proof-audit-NOT-FOR-PUBLICATION' : 'release-proof');
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'release-evidence.json'), `${JSON.stringify(receipt, null, 2)}\n`);
  const url = `https://github.com/Sampath-K/bloomstep/releases/download/${tag}`;
  for (const arch of ['x64', 'arm64']) {
    const frame = receipt.native[arch].entry ?? receipt.native[arch].welcome;
    copyFileSync(join(root, `native-${arch}`, frame.file),
      join(output, frame.file.replace('.png', `-${arch}.png`)));
    writeFileSync(join(output, `native-lifecycle-${arch}.json`), `${JSON.stringify(receipt.native[arch], null, 2)}\n`);
    writeFileSync(join(output, `genuine-launch-${arch}.json`), `${JSON.stringify(receipt.launch[arch], null, 2)}\n`);
  }
  const destinationFirst = Object.values(receipt.native).every(proof => proof.entry?.page === 'destination');
  const pageChecklist = destinationFirst ?
    `- [ ] Destination opens first with the per-user folder/Browse; Install is the only commitment. During real installation original scenes may transition; fast completion is never delayed. Check actual motion/reduced-motion and high-DPI readability separately.\n` +
    `- [ ] Cancel before installation leaves no payload. Installer observations are entirely disabled, including silent installs; prior legacy receipts are not new consent.\n` :
    `- [ ] Offline payload install succeeds; Welcome, two illustrated recipe cards, full garden and Back/Cancel remain readable. No animation is included.\n` +
    `- [ ] Cancel before installation leaves no payload or observations. Optional observations remain unchecked/default-off and absent unless explicitly selected.\n`;
  const checklist = `# Owner manual-test checklist — ${tag}\n\n` +
    `Status: PENDING. Genuine launch-after-Finish remains explicitly UNVERIFIED when the hosted elevated-token guard stops before installation. This is not customer-ready or full acceptance.\n\n` +
    `Use clean disposable native x64 and ARM64 slots as the ordinary installing user; do not run as administrator or disable protections. Verify exact release filename and SHA-256 first. Unknown source/hash, malware or managed-policy block means STOP. Hash consistency is not safety/signing.\n\n` +
    `- [ ] One primary universal download routes to the native OS without an architecture choice; also exercise x64 process emulation on ARM where available.\n` +
    pageChecklist +
    `- [ ] Checked Finish exits successfully and starts exactly one native, non-elevated app as the installing user; same process survives at least ten seconds with visible window. Record observed outcome, not an assumption.\n` +
    `- [ ] In a separate clean slot, unchecked Finish exits successfully and starts no app. Manual Start Menu launch remains possible.\n` +
    `- [ ] Ordinary sign-in, tiny routine-linked habit, check-in, celebration and full garden journey work; cancel/exit and keyboard/focus/accessibility remain usable.\n` +
    `- [ ] Record native OS/architecture, package hash, installing-user/elevation confirmation, checked/unchecked outcomes and any failure, with no private identity in shared screenshots.\n\n` +
    `Any launch/journey failure is P0 for a new immutable preview, not mutation of these bytes. No external recruitment or public-pointer change. The site stays preview9 until separately agreed owner trials pass; promote these SAME verified binaries only after separate approval.\n`;
  writeFileSync(join(output, 'owner-trial-checklist.md'), checklist);
  writeFileSync(join(output, 'evidence-notes.md'),
    `## Executive summary and verified single download\n\n` +
    `[Download Bloomstep for Windows — universal owner-test installer](${url}/${receipt.package.installerFile})\n\n` +
    `One offline installer, native x64/ARM64 routing; per-architecture installers are support-only secondary assets. ` +
    `Measured size **${receipt.package.bytes.toLocaleString('en-US')} bytes**; compiler ${receipt.package.compiler}; ${receipt.package.signatureStatus}.\n\n` +
    `SHA-256: \`${receipt.package.installerSha256}\`\n\n` +
    `Source \`${source}\`; [same-run build/native proof](${receipt.origin}). Public binary/checksum/manifests must match this run, never another same-source build. ` +
    `Genuine launch: **${receipt.genuineLaunch}**. Native lifecycle evidence does not establish sign-in/full journey or installer safety.\n\n` +
    `## Actual static installer screenshots\n\n` +
    `These are the actual compiled universal ${destinationFirst ? 'destination' : 'Welcome'} on isolated CI x64/ARM64, followed by Cancel. They are not motion, customer app/Finish acceptance, universal warning or safety evidence.\n\n` +
    ['x64', 'arm64'].map(arch => {
      const frame = receipt.native[arch].entry ?? receipt.native[arch].welcome;
      return `![Actual ${arch} universal entry, isolated CI Cancel evidence](${url}/${frame.file.replace('.png', `-${arch}.png`)})`;
    }).join('\n\n') + '\n\n' + checklist);
  console.log(`${mode ? 'AUDIT ONLY, NOT AUTHORIZED FOR PUBLICATION: ' : ''}Verified one-run release package, both native/frame receipts and ${receipt.genuineLaunch}.`);
}
