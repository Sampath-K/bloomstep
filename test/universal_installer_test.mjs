import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
test('universal installer bundles exclusive native OS payloads without bootstrap or privilege changes', () => {
  const source = read('packaging/budlark.iss');
  assert.match(source, /#if AppArch == "universal"[\s\S]*ArchitecturesAllowed=arm64 or x64os/);
  assert.match(source, /Source: "\{#SourceDirX64\}\\\*";.*Check: UseX64Payload/);
  assert.match(source, /Source: "\{#SourceDirArm64\}\\\*";.*Check: UseArm64Payload/);
  assert.match(source, /function UseX64Payload[\s\S]*Result := ProcessorArchitecture = paX64/);
  assert.match(source, /function UseArm64Payload[\s\S]*Result := ProcessorArchitecture = paArm64/);
  assert.match(source, /PrivilegesRequired=lowest/);
  assert.match(source, /postinstall skipifsilent runasoriginaluser/);
  assert.doesNotMatch(source, /ExecAsOriginalUser/);
  assert.doesNotMatch(source, /DownloadTemporaryFile|dontverifychecksum|skipifsourcedoesntexist|PrivilegesRequired=admin/);
});
test('hosted packaging remains required and owner installer verification stays pending', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-installer:/);
  assert.match(workflow, /release_payload\.mjs verify/);
  assert.match(workflow, /payload-manifest-/);
  assert.match(workflow, /needs: \[api, test-and-build-windows, universal-installer\]/);
  for (const job of ['installer-launch-evidence', 'protected-installer-lifecycle',
    'universal-native-proof', 'universal-app-launch-evidence']) {
    assert.doesNotMatch(workflow, new RegExp(`^  ${job}:`, 'm'));
  }
  assert.doesNotMatch(workflow, /runs-on:\s*\[self-hosted/);
  assert.doesNotMatch(workflow, /needs\.[\w-]*(?:launch|lifecycle|native-proof)/);
  assert.doesNotMatch(workflow, /protected disposable standard-user VM jobs/);
  assert.match(workflow, /release_bundle\.mjs/);
  assert.match(workflow, /owner manual installer verification (?:remains )?pending/i);
});
test('release inputs require exact source, version, architecture, inventory and byte hashes', async () => {
  const { createPayloadManifest, verifyPayloadManifest } = await import('../tool/release_payload.mjs');
  const root = mkdtempSync(fileURLToPath(new URL('../.budlark-payload-contract-', import.meta.url)));
  const source = 'a'.repeat(40), version = '0.1.0-preview.11';
  const pe = Buffer.alloc(128); pe.write('MZ'); pe.writeUInt32LE(64, 60);
  pe.write('PE\0\0', 64); pe.writeUInt16LE(0xaa64, 68);
  try {
    mkdirSync(join(root, 'data', 'flutter_assets'), { recursive: true });
    for (const file of ['budlark.exe', 'flutter_windows.dll']) writeFileSync(join(root, file), pe);
    writeFileSync(join(root, 'data', 'icudtl.dat'), 'fixture only');
    writeFileSync(join(root, 'data', 'app.so'), 'synthetic AOT shape fixture, never a genuine Release claim');
    writeFileSync(join(root, 'data', 'flutter_assets', 'AssetManifest.bin'), 'fixture only');
    const manifest = createPayloadManifest(root, { arch: 'arm64', source, version });
    assert.equal(verifyPayloadManifest(root, manifest, { arch: 'arm64', source, version }).arch, 'arm64');
    rmSync(join(root, 'data', 'app.so'));
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /app\.so/);
    writeFileSync(join(root, 'data', 'app.so'), 'synthetic AOT shape fixture, never a genuine Release claim');
    const wrongPe = Buffer.from(pe); wrongPe.writeUInt16LE(0x8664, 68);
    writeFileSync(join(root, 'flutter_windows.dll'), wrongPe);
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /architecture/);
    writeFileSync(join(root, 'flutter_windows.dll'), pe);
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
    rmSync(join(root, 'budlark.exe'));
    assert.throws(() => createPayloadManifest(root, { arch: 'arm64', source, version }), /required|missing/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('native routing source semantics reject unsupported hosts even with a misleading process architecture (simulation only)', () => {
  const source = read('packaging/budlark.iss');
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
test('unified customer download is fail-closed after the owner-authorized preview14 pointer update', async () => {
  const { renderDownloads, validateRelease } = await import('../site/release-downloads.mjs');
  const current = JSON.parse(read('site/customer-config.json'));
  assert.equal(current.release.tag, 'v0.1.0-preview.14');
  assert.equal(current.release.universal.sha256, 'b53767c405fa9b704fb828d221f883b81d14231e3ebf65dd8820d3812fd42a2c');
  const release = {
    ...current.release, tag: 'v0.1.0-preview.11',
    ...Object.fromEntries(['arm64','x64','universal'].map(arch => [arch, {
      url: `https://github.com/Sampath-K/budlark/releases/download/v0.1.0-preview.11/Budlark-0.1.0-preview.11-windows-${arch}-setup.exe`,
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
  assert.match(html, /data-download="unknown"[^>]*>Internal dogfood preview \(unsigned; designated testers only\)/);
  assert.match(html, /secondary x64 and ARM64 installers are for troubleshooting by designated testers/);
  assert.match(html, /<details><summary>Other files \(owner testing only\)<\/summary>[\s\S]*secondary x64 and ARM64 installers are for troubleshooting by designated testers/);
  assert.doesNotMatch(html, /data-universal-download[\s\S]*?<div class="choices"/);
});
test('actual proof requires package and native machine authority, cancel, installed hashes and corrupt rollback', () => {
  const proof = read('tool/verify_universal_installer.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /manifest\.source -ne \$source/);
  assert.match(proof, /native-probe-manifest\.json/);
  assert.match(proof, /processMachine -ne 0x8664/);
  assert.match(proof, /cancelBeforePayload/);
  assert.match(proof, /selectedPayloadAllHashesVerified/);
  assert.match(proof, /corruptedEmbeddedChecksumRollbackVerified/);
  const source = read('packaging/budlark.iss');
  assert.match(source, /#ifdef UniversalIntegrityFixture[\s\S]*#ifndef OnboardingJourneyFixture[\s\S]*#error/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-integrity-fixture/);
  assert.doesNotMatch(workflow, /gh release create[^\n]*integrity/);
});
test('ARM emulation proof uses a genuine native x64 process, not managed PE metadata', () => {
  const source = read('tool/fixtures/native_architecture_probe.cpp');
  assert.match(source, /IsWow64Process2/);
  assert.match(source, /sizeof\(void\*\) == 8/);
  assert.match(source, /GetProcessInformation[\s\S]*ProcessMachineTypeInfo/);
  assert.match(source, /wow64ProcessMachine/);
  assert.doesNotMatch(source, /System\.|CLR|WindowsIdentity/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /vcvars64\.bat/);
  assert.match(workflow, /native_architecture_probe\.cpp/);
  assert.match(workflow, /native-probe-output/);
  assert.match(workflow, /native-probe-manifest\.json/);
  assert.match(read('.gitattributes'), /native_architecture_probe\.cpp text eol=lf/);
  assert.doesNotMatch(workflow, /gh release create[^\n]*native-probe/);
});
test('actual PowerShell corruption oracle ignores command paths and verifies Welcome Cancel exit (no installer execution)', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    $wrong = @(Get-EmbeddedChecksumErrors @('Command line: /DIR=C:\\universal-corrupt /LOG=C:\\corrupt-private.log','Error: Setup initialization failed','Checksum file: C:\\CRC.txt'));
    if ($wrong.Count -ne 0) { throw 'Path/header manufactured checksum success' }
    $valid = @(Get-EmbeddedChecksumErrors @('2026-10-07 05:02:06.811   Error: The source file is corrupted','The source file is corrupted'));
    if ($valid.Count -ne 1 -or $valid[0] -ne 'The source file is corrupted') { throw 'Specific sanitized error missing' }
    Assert-WelcomeCancelExit 2;
    foreach ($code in @(0,1,3,4,5)) {
      $rejected = $false;
      try { Assert-WelcomeCancelExit $code } catch { $rejected = $true }
      if (-not $rejected) { throw 'Non-cancel exit accepted' }
    }
    'PASS'`;
  const output = execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' });
  assert.match(output, /PASS/);
  const proof = read('tool/verify_universal_installer.ps1');
  assert.match(proof, /Get-EmbeddedChecksumErrors/);
  assert.match(proof, /Assert-WelcomeCancelExit/);
  assert.match(proof, /checksumErrorLines/);
  assert.doesNotMatch(proof, /-notmatch '\(\?i\)corrupt\|checksum\|CRC'/);
});
test('release records manual installer verification as pending and binds it to package bytes', async () => {
  const { verifyReleaseEvidence } = await import('../tool/release_bundle.mjs');
  const root = mkdtempSync(join(tmpdir(), 'budlark-release-evidence-'));
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  const source = 'a'.repeat(40), tag = 'v0.1.0-preview.15', version = tag.slice(1);
  const bytes = Buffer.from('fixture installer bytes');
  const writeJson = (path, value) => writeFileSync(join(root, path), JSON.stringify(value));
  try {
    mkdirSync(join(root, 'universal-output'));
    const installerFile = `Budlark-${version}-windows-universal-setup.exe`;
    writeFileSync(join(root, 'universal-output', installerFile), bytes);
    const payloadManifests = {};
    for (const arch of ['x64', 'arm64']) {
      const payload = JSON.stringify({ kind: 'budlark-release-payload-v1', source, version, arch });
      writeFileSync(join(root, 'universal-output', `payload-manifest-${arch}.json`), payload);
      payloadManifests[arch] = sha(payload);
    }
    writeJson('universal-output/universal-manifest.json', {
      kind: 'budlark-offline-universal-v1', source, version, installerFile,
      installerSha256: sha(bytes), bytes: bytes.length, payloadManifests,
    });
    writeFileSync(join(root, 'universal-output', 'SHA256-universal.txt'),
      `${sha(bytes)}  ${installerFile}\n`);

    const evidence = verifyReleaseEvidence({ root, source, tag, runId: '123' });
    assert.equal(evidence.ownerManualVerification.status, 'PENDING');
    assert.equal(evidence.ownerManualVerification.installerSha256, sha(bytes));
    assert.equal(evidence.ownerManualVerification.requiredBeforeCustomerLaunch, true);
    assert.equal(evidence.ownerManualVerification.recordedResult, null);
    assert.match(evidence.installerAcceptance, /UNVERIFIED/);
    assert.doesNotMatch(JSON.stringify(evidence.ownerManualVerification), /PASS|SUCCESS/i);
    assert.throws(() => verifyReleaseEvidence({ root, source: 'b'.repeat(40), tag, runId: '123' }), /identity/);
    writeFileSync(join(root, 'universal-output', installerFile), 'tampered');
    assert.throws(() => verifyReleaseEvidence({ root, source, tag, runId: '123' }), /bytes|hash/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('genuine app-launch harness stays fail-closed for future separately authorized manual use', () => {
  const proof = read('tool/verify_universal_app_launch.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /installerSha256/);
  assert.match(proof, /ProcessTokenProbe\]::Elevated\(\$PID\)/);
  assert.match(proof, /checked-launch','unchecked-launch','silent-no-launch/);
  assert.match(proof, /ProcessTokenProbe\]::Sid/);
  assert.match(proof, /ProcessTokenProbe\]::Elevated\(\$app\.Id\)/);
  assert.match(proof, /Assert-StandardWizardJourney/);
  assert.match(proof, /Start-ProtectedInstallerProof/);
  assert.doesNotMatch(proof, /continue-on-error|inert-journey-fixture-v1/);
});
test('genuine outcome oracle rejects transient apps and unsuccessful installer exits (no app execution)', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    Assert-GenuineLaunchOutcome 'checked-launch' 0 0 1 $true $true;
    Assert-GenuineLaunchOutcome 'unchecked-launch' 0 0 0 $false $false;
    Assert-GenuineLaunchOutcome 'silent-no-launch' 0 0 0 $false $false;
    foreach ($bad in @(
      @('checked-launch',0,0,1,$false,$false),
      @('checked-launch',0,0,1,$true,$false),
      @('checked-launch',1,0,1,$true,$true),
      @('checked-launch',0,1,1,$true,$true),
      @('unchecked-launch',0,0,1,$true,$true),
      @('unchecked-launch',1,0,0,$false,$false),
      @('automatic-launch',0,0,1,$true,$true),
      @('unknown-mode',0,0,0,$false,$false),
      @('silent-no-launch',1,0,0,$false,$false),
      @('silent-no-launch',0,0,1,$true,$true)
    )) {
      $rejected = $false;
      try { Assert-GenuineLaunchOutcome @bad } catch { $rejected = $true }
      if (-not $rejected) { throw 'Transient/uninstalled outcome accepted' }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  const proof = read('tool/verify_universal_app_launch.ps1');
  assert.match(proof, /Assert-GenuineLaunchOutcome/);
  assert.match(proof, /sameExactTargetAppAlive/);
  assert.match(proof, /ownedAppWindowVisible/);
  assert.match(proof, /wizardExitCode/);
});

test('one-click wizard driver verifies Install/Finish and freely toggleable default-checked launch without an installer', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    Add-Type @'
using System;
public static class OnboardingWizard {
  public static int Choice = 1;
  public static string Describe(IntPtr h) {
    return new [] { "", "Welcome", "Select Destination Location", "Ready to Install", "Installing", "Completing" }[(int)h];
  }
  public static IntPtr Find(IntPtr h, string caption) {
    int page = (int)h;
    return ((page == 5 && caption == "Finish") || (page == 3 && caption == "Install") ||
      ((page == 1 || page == 2) && caption == "Next >")) ? new IntPtr(99) : IntPtr.Zero;
  }
  public static int LaunchChoiceState(IntPtr h) { return Choice; }
  public static void ToggleLaunchChoice(IntPtr h) { Choice = 1 - Choice; }
  public static bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l) { return true; }
}
'@
    foreach ($checked in @($false,$true)) {
      [OnboardingWizard]::Choice = 1;
      $journey = New-StandardWizardJourney;
      foreach ($page in 3..5) {
        Invoke-StandardWizardStep ([IntPtr]$page) $journey $checked | Out-Null;
        Invoke-StandardWizardStep ([IntPtr]$page) $journey $checked | Out-Null;
      }
      Assert-StandardWizardJourney $journey $checked;
      if ($journey.launchSelected -ne $checked) { throw 'Choice mismatch' }
    }
    foreach ($pages in @(@(2),@(1,3),@(3,5),@(3,4,3))) {
      $rejected = $false;
      try {
        $journey = New-StandardWizardJourney;
        foreach ($page in $pages) { Invoke-StandardWizardStep ([IntPtr]$page) $journey | Out-Null }
      } catch { $rejected=$true }
      if (-not $rejected) { throw 'Skipped or reversed page accepted' }
    }
    foreach ($choice in @(0,-1)) {
      [OnboardingWizard]::Choice = $choice;
      $rejected = $false;
      try {
        $journey = New-StandardWizardJourney;
        foreach ($page in 3..5) { Invoke-StandardWizardStep ([IntPtr]$page) $journey $true | Out-Null }
      } catch { $rejected=$true }
      if (-not $rejected) { throw 'Default-off or missing explicit checkbox accepted' }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
});

test('owned PowerShell proof scripts parse on every CI platform', () => {
  const scripts = ['verify_onboarding_wizard', 'verify_install_progress', 'verify_installer_journey',
    'verify_universal_app_launch', 'universal_integrity_contract', 'setup_defender_test_vm', 'verify_universal_installer'];
  const paths = scripts.map(name => `'${fileURLToPath(new URL(`../tool/${name}.ps1`, import.meta.url)).replaceAll("'", "''")}'`);
  const script = `$ErrorActionPreference='Stop';
    foreach ($file in @(${paths.join(',')})) {
      $tokens=$null; $errors=$null;
      [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null;
      if ($errors.Count -ne 0) { throw ($errors | Out-String) }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
});

test('Windows native accessibility helpers compile without installer execution',
  { skip: process.platform !== 'win32' }, () => {
    const helper = fileURLToPath(new URL('../tool/verify_onboarding_wizard.ps1', import.meta.url)).replaceAll("'", "''");
    const script = `$ErrorActionPreference='Stop'; & '${helper}' -Installer 'never-executed' -EvidenceDir '.' -LoadHelpersOnly; 'PASS'`;
    assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  });

test('Defender proof refuses new detections or changed protection and preserves sanitized receipt (mocked, no installer)', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const root = mkdtempSync(fileURLToPath(new URL('../.budlark-protection-contract-', import.meta.url)));
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    $script:protection = $true; $script:detections = @();
    function Get-MpComputerStatus {
      [pscustomobject]@{ AntivirusEnabled=$true; RealTimeProtectionEnabled=$script:protection; BehaviorMonitorEnabled=$true;
        AMServiceEnabled=$true; AntispywareEnabled=$true; IoavProtectionEnabled=$true; NISEnabled=$true }
    }
    function Get-MpThreatDetection { $script:detections }
    $context = @{ baseline=(Get-InstallerProtectionSnapshot); evidenceDir='${root.replaceAll("'", "''")}'; installerSha256=('a'*64) };
    Assert-InstallerProtectionUnchanged $context;
    $script:detections = @([pscustomobject]@{ DetectionID='PRIVATE-ID'; ThreatID=1; LastThreatStatusChangeTime='now'; ThreatStatusID=1 });
    $rejected=$false; try { Assert-InstallerProtectionUnchanged $context } catch { $rejected=$true }
    if (-not $rejected) { throw 'New detection accepted' }
    $body = Get-Content (Join-Path $context.evidenceDir 'defender-proof-receipt.json') -Raw;
    if ($body.Contains('PRIVATE-ID') -or ($body | ConvertFrom-Json).outcome -ne 'FAIL') { throw 'Receipt is not sanitized failed evidence' }
    $script:detections=@(); $script:protection=$false;
    $rejected=$false; try { Assert-InstallerProtectionUnchanged $context } catch { $rejected=$true }
    if (-not $rejected) { throw 'Protection disabled accepted' }
    'PASS'`;
  try {
    assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  } finally { rmSync(root, { recursive: true, force: true }); }
  const contract = read('tool/universal_integrity_contract.ps1');
  assert.match(contract, /setup_defender_test_vm\.ps1" -Mode ScanCandidate -Installer \$Installer/);
  assert.match(contract, /-ExpectedSha256 \$ExpectedSha256/);
  for (const name of ['verify_onboarding_wizard', 'verify_install_progress', 'verify_installer_journey', 'verify_universal_app_launch']) {
    const proof = read(`tool/${name}.ps1`);
    assert.match(proof, /Start-ProtectedInstallerProof/);
    assert.match(proof, /Assert-InstallerProtectionUnchanged/);
    const firstExecution = /(?:Start-Process(?: -FilePath)? \$(?:Installer|installer)|Start-CaptureProcess \$(?:Installer|installer))/.exec(proof);
    assert.ok(firstExecution, `${name}: installer dispatch is auditable`);
    assert.ok(proof.indexOf('Start-ProtectedInstallerProof') < firstExecution.index,
      `${name}: candidate scan must precede execution`);
  }
});
test('genuine Inno product authority permits only trailing ASCII resource padding', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    foreach ($valid in @('Budlark',('Budlark'+(' '*51)))) {
      if (-not (Test-BudlarkInnoProductName $valid)) { throw 'Genuine padded resource rejected' }
    }
    if (-not (Test-BudlarkInnoProductName ('Budlark isolated journey proof'.PadRight(60,' ')) 'Budlark isolated journey proof')) { throw 'Known padded fixture rejected' }
    if (Test-BudlarkInnoProductName ('Budlark isolated journey proof'.PadRight(60,' '))) { throw 'Fixture accepted as product' }
    foreach ($invalid in @('',' Budlark','Budlark other','budlark',('Budlark'+[char]9),('Budlark'+[char]10),('Budlark'+[char]13),('Budlark'+[char]160))) {
      if (Test-BudlarkInnoProductName $invalid) { throw 'Non-product identity accepted' }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  assert.match(read('tool/verify_universal_app_launch.ps1'), /Test-BudlarkInnoProductName/);
  assert.match(read('tool/verify_universal_installer.ps1'), /Test-BudlarkInnoProductName/);
});
test('owned Cancel and other modal wizard clicks cannot block the evidence deadline', () => {
  for (const name of ['tool/verify_universal_installer.ps1', 'tool/verify_universal_app_launch.ps1']) {
    const proof = read(name);
    assert.doesNotMatch(proof, /SendMessage\([^;\n]*0x00F5/);
    const driver = name.endsWith('verify_universal_app_launch.ps1') ? read('tool/universal_integrity_contract.ps1') : proof;
    assert.match(driver, /PostMessage\([^;\n]*0x00F5/);
  }
  const proof = read('tool/verify_universal_installer.ps1');
  assert.match(proof, /cancel-dispatch/);
  assert.match(proof, /cancel-confirmation/);
  assert.match(proof, /Save-NativeStage/);
  assert.doesNotMatch(proof, /Start-Process[^\n]* -Wait/);
  assert.match(proof, /TimeoutSeconds = 120/);
  assert.match(proof, /AddSeconds\(\$TimeoutSeconds\)/);
  assert.match(proof, /parentPid = \$ownedParents/);
  assert.match(proof, /ownedDialogs = \$dialogs/);
  for (const stage of ['install', 'uninstall', 'corrupt', 'cleanup-uninstall']) {
    assert.match(proof, new RegExp(`Invoke-NativeProcess '${stage}'`));
  }
});
test('compiler compatibility uses observed engine banner, not missing ISCC file-version resources', () => {
  const helper = fileURLToPath(new URL('../tool/inno_compiler_version.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    if ((Get-InnoEngineVersion @('Compiler engine version: Inno Setup 6.3.0')).ToString() -ne '6.3.0') { throw 'Minimum version not recognized' }
    if ((Get-InnoEngineVersion @('Inno Setup 6 Command-Line Compiler','','Compiler engine version: Inno Setup 6.7.1','','Successful compile. Output was disabled.')).ToString() -ne '6.7.1') { throw 'Observed multiline version lost' }
    foreach ($bad in @('','File version: 0.0.0.0','Compiler engine version: Inno Setup 6.2.2','Compiler engine version: Other Tool 7.0.0')) {
      $rejected=$false; try { Get-InnoEngineVersion @($bad) } catch { $rejected=$true }
      if (-not $rejected) { throw 'Unknown/unsupported compiler accepted' }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /Get-InnoEngineVersion/);
  assert.match(workflow, /inno-toolchain-probe\.iss/);
  assert.doesNotMatch(workflow, /compiler\.VersionInfo\.File(?:Major|Minor)Part\s+-(?:lt|eq|gt)/);
  assert.match(workflow, /fileVersion = \$compiler\.VersionInfo\.FileVersion/);
  assert.match(workflow, /Tee-Object -Variable engineOutput/);
  assert.match(read('packaging/inno-toolchain-probe.iss'), /Output=no/);
});
