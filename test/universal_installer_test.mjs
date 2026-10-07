import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

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
test('universal packaging remains required and source-pinned, recovery exception is exact preview12 only', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-installer:/);
  assert.match(workflow, /universal-native-proof:/);
  assert.match(workflow, /release_payload\.mjs verify/);
  assert.match(workflow, /payload-manifest-/);
  assert.match(workflow, /needs: \[api, test-and-build-windows, installer-launch-evidence, universal-native-proof, universal-app-launch-evidence\]/);
  assert.match(workflow, /github\.ref_name == 'v0\.1\.0-preview\.10'/);
  assert.match(workflow, /needs\.universal-app-launch-evidence\.result == 'success' \|\| github\.ref_name == 'v0\.1\.0-preview\.12'/);
  assert.doesNotMatch(workflow, /github\.ref_name == 'v0\.1\.0-preview\.13'/);
  assert.match(workflow, /release_bundle\.mjs/);
  assert.match(workflow, /universal-native-\$\{\{ matrix\.arch/);
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
test('unified customer download is fail-closed after the owner-authorized preview12 pointer update', async () => {
  const { renderDownloads, validateRelease } = await import('../site/release-downloads.mjs');
  const current = JSON.parse(read('site/customer-config.json'));
  assert.equal(current.release.tag, 'v0.1.0-preview.12');
  assert.equal(current.release.universal.sha256, 'fe115a7ada87858a55ba2610f778888079ee01a242f9ff74e18120a359292858');
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
  assert.match(html, /<details[^>]*>[\s\S]*Other downloads \(troubleshooting\)/);
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
  const source = read('packaging/bloomstep.iss');
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
test('next universal release requires genuine app launch evidence independently of the inert fixture', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /universal-app-launch-evidence:/);
  assert.match(workflow, /needs\.universal-app-launch-evidence\.result == 'success'/);
  const proof = read('tool/verify_universal_app_launch.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /installerSha256/);
  assert.match(proof, /ProcessTokenProbe\]::Elevated\(\$PID\)/);
  assert.match(proof, /checked-launch','unchecked-launch/);
  assert.match(proof, /ProcessTokenProbe\]::Sid/);
  assert.match(proof, /ProcessTokenProbe\]::Elevated\(\$app\.Id\)/);
  assert.match(proof, /default checked/);
  assert.doesNotMatch(proof, /continue-on-error|inert-journey-fixture-v1/);
});
test('genuine outcome oracle rejects transient apps and unsuccessful installer exits (no app execution)', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    Assert-GenuineLaunchOutcome 'checked-launch' 0 0 1 $true $true;
    Assert-GenuineLaunchOutcome 'unchecked-launch' 0 0 0 $false $false;
    foreach ($bad in @(
      @('checked-launch',0,0,1,$false,$false),
      @('checked-launch',0,0,1,$true,$false),
      @('checked-launch',1,0,1,$true,$true),
      @('checked-launch',0,1,1,$true,$true),
      @('unchecked-launch',1,0,0,$false,$false),
      @('unchecked-launch',0,0,1,$true,$true)
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
test('genuine Inno product authority permits only trailing ASCII resource padding', () => {
  const helper = fileURLToPath(new URL('../tool/universal_integrity_contract.ps1', import.meta.url)).replaceAll("'", "''");
  const script = `$ErrorActionPreference='Stop'; . '${helper}';
    foreach ($valid in @('Bloomstep',('Bloomstep'+(' '*51)))) {
      if (-not (Test-BloomstepInnoProductName $valid)) { throw 'Genuine padded resource rejected' }
    }
    if (-not (Test-BloomstepInnoProductName ('Bloomstep isolated journey proof'.PadRight(60,' ')) 'Bloomstep isolated journey proof')) { throw 'Known padded fixture rejected' }
    if (Test-BloomstepInnoProductName ('Bloomstep isolated journey proof'.PadRight(60,' '))) { throw 'Fixture accepted as product' }
    foreach ($invalid in @('',' Bloomstep','Bloomstep other','bloomstep',('Bloomstep'+[char]9),('Bloomstep'+[char]10),('Bloomstep'+[char]13),('Bloomstep'+[char]160))) {
      if (Test-BloomstepInnoProductName $invalid) { throw 'Non-product identity accepted' }
    }
    'PASS'`;
  assert.match(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }), /PASS/);
  assert.match(read('tool/verify_universal_app_launch.ps1'), /Test-BloomstepInnoProductName/);
  assert.match(read('tool/verify_universal_installer.ps1'), /Test-BloomstepInnoProductName/);
});
test('owned Cancel and other modal wizard clicks cannot block the evidence deadline', () => {
  for (const name of ['tool/verify_universal_installer.ps1', 'tool/verify_universal_app_launch.ps1']) {
    const proof = read(name);
    assert.doesNotMatch(proof, /SendMessage\([^;\n]*0x00F5/);
    assert.match(proof, /PostMessage\([^;\n]*0x00F5/);
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
