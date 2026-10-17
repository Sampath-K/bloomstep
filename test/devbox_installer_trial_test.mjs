import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const common = new URL('../tool/devbox-trial/Trial.Common.ps1', import.meta.url);
const entry = new URL('../tool/devbox-trial/Run-InstallerTrial.ps1', import.meta.url);
const text = url => readFileSync(url, 'utf8');
const runPowerShell = (code, extra = {}) => spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', code], {
  encoding: 'utf8',
  env: { ...process.env, BLOOMSTEP_TRIAL_COMMON: fileURLToPath(common), ...extra },
});

test('trial receipt and outcome cannot claim protected acceptance or release readiness', () => {
  const result = runPowerShell(`
    . $env:BLOOMSTEP_TRIAL_COMMON
    $receipt = New-DevBoxTrialReceipt 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'x64' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    if ($receipt.evidenceClass -ne 'supplemental-manual-owner-trial' -or
        $receipt.protectedGateStatus -ne 'UNVERIFIED' -or $receipt.releaseAuthorized -or
        $receipt.runnerRegistrationAuthorized -or $receipt.installerExecutionStarted) {
      throw 'Initial receipt overclaims or enables a protected action.'
    }
    if ((Get-DevBoxTrialOutcome 0 $true $true $true) -ne 'SUPPLEMENTAL_OWNER_TRIAL_COMPLETE') {
      throw 'Owner observations did not map to the supplemental result.'
    }
    if ((Get-DevBoxTrialOutcome 0 $true $false $true) -ne 'INCOMPLETE_OWNER_OBSERVATION') {
      throw 'Missing observation was reported as complete.'
    }
    if ((Get-DevBoxTrialOutcome 0 $false $true $true) -ne 'INSTALLED_PAYLOAD_FAILED') {
      throw 'Payload integrity failure was reported as complete.'
    }
    if ((Get-DevBoxTrialOutcome 5 $true $true $true) -ne 'INSTALLER_FAILED') {
      throw 'Installer failure was not preserved.'
    }
    $receipt.outcome = Get-DevBoxTrialOutcome 0 $true $true
    if ($receipt.protectedGateStatus -ne 'UNVERIFIED' -or $receipt.protectedGatesAccepted -or $receipt.releaseAuthorized) {
      throw 'A completed manual observation promoted protected acceptance or release.'
    }
  `);
  assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
});

test('installer launch requires all preconditions and is never repeatable after it starts', () => {
  const result = runPowerShell(`
    . $env:BLOOMSTEP_TRIAL_COMMON
    foreach ($stage in @('Preflight','LaunchAuthorized','InstallerStarted','InstallerCompleted','Failed')) {
      if (Test-DevBoxTrialLaunchAllowed $stage $true $true $true) {
        throw "Unexpected launch permission at $stage"
      }
    }
    if (Test-DevBoxTrialLaunchAllowed 'Ready' $false $true $true) { throw 'Skipped preflight.' }
    if (Test-DevBoxTrialLaunchAllowed 'Ready' $true $false $true) { throw 'Skipped recovery point.' }
    if (Test-DevBoxTrialLaunchAllowed 'Ready' $true $true $false) { throw 'Skipped explicit execution confirmation.' }
    if (-not (Test-DevBoxTrialLaunchAllowed 'Ready' $true $true $true)) { throw 'Valid launch was blocked.' }
  `);
  assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
});

test('previous portable-tool caches are validated read-only and reject modified or extra files', () => {
  const directory = mkdtempSync(join(tmpdir(), 'bloomstep-devbox-cache-test-'));
  try {
    const result = runPowerShell(`
      . $env:BLOOMSTEP_TRIAL_COMMON
      $root = $env:BLOOMSTEP_TRIAL_TEMP
      $source = Join-Path $root 'input.txt'
      [IO.File]::WriteAllText($source, 'pinned')
      $archive = Join-Path $root 'tool.zip'
      Compress-Archive -LiteralPath $source -DestinationPath $archive
      $destination = Join-Path $root 'expanded'
      New-Item -ItemType Directory -Path $destination | Out-Null
      Expand-Archive -LiteralPath $archive -DestinationPath $destination
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
      if (-not (Assert-VerifiedPortableCache $archive $destination $hash)) { throw 'Valid cache was not accepted.' }
      $rejected = $false
      try { Assert-VerifiedPortableCache $archive $destination ('0' * 64) | Out-Null } catch { $rejected = $true }
      if (-not $rejected) { throw 'An archive with the wrong pinned hash was accepted.' }
      [IO.File]::WriteAllText((Join-Path $destination 'input.txt'), 'changed')
      $rejected = $false
      try { Assert-VerifiedPortableCache $archive $destination $hash | Out-Null } catch { $rejected = $true }
      if (-not $rejected) { throw 'Modified cached tool was accepted.' }
      [IO.File]::WriteAllText((Join-Path $destination 'input.txt'), 'pinned')
      [IO.File]::WriteAllText((Join-Path $destination 'extra.txt'), 'unexpected')
      $rejected = $false
      try { Assert-VerifiedPortableCache $archive $destination $hash | Out-Null } catch { $rejected = $true }
      if (-not $rejected) { throw 'Unexpected extracted file was accepted.' }
    `, { BLOOMSTEP_TRIAL_TEMP: directory });
    assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('installed native payload must match its architecture manifest and every SHA-256', () => {
  const directory = mkdtempSync(join(tmpdir(), 'bloomstep-devbox-payload-test-'));
  try {
    const result = runPowerShell(`
      . $env:BLOOMSTEP_TRIAL_COMMON
      $root = $env:BLOOMSTEP_TRIAL_TEMP
      $target = Join-Path $root 'installed'
      New-Item -ItemType Directory -Path $target | Out-Null
      $filePath = Join-Path $target 'bloomstep.exe'
      [IO.File]::WriteAllText($filePath, 'native-test-binary')
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $filePath).Hash.ToLowerInvariant()
      $payloadPath = Join-Path $root 'payload-manifest-x64.json'
      @{source='a'*40;arch='x64';files=@(@{path='bloomstep.exe';bytes=(Get-Item $filePath).Length;sha256=$hash})} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $payloadPath
      $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $payloadPath).Hash.ToLowerInvariant()
      $universal = @{source='a'*40;payloadManifests=@{x64=$manifestHash}}
      if ((Assert-InstalledPayload $target 'x64' $root $universal) -ne 1) { throw 'Valid payload was not counted.' }
      $rejected = $false
      try { Assert-InstalledPayload $target 'arm64' $root $universal | Out-Null } catch { $rejected = $true }
      if (-not $rejected) { throw 'Wrong architecture was accepted.' }
      [IO.File]::WriteAllText($filePath, 'tampered')
      $rejected = $false
      try { Assert-InstalledPayload $target 'x64' $root $universal | Out-Null } catch { $rejected = $true }
      if (-not $rejected) { throw 'Tampered installed payload was accepted.' }
    `, { BLOOMSTEP_TRIAL_TEMP: directory });
    assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('entry point is PS 5.1 parseable and avoids runner, policy, Defender, and reboot bypasses', () => {
  const source = `${text(common)}\n${text(entry)}`;
  assert.doesNotMatch(source, /config\.cmd|run\.cmd|registration-token|Set-ExecutionPolicy|Unblock-File|Set-MpPreference|Add-MpPreference|schtasks|New-Service|shutdown\.exe|Restart-Computer|Remove-Item|Invoke-WebRequest|az\.exe/);
  assert.doesNotMatch(source, /BLOOMSTEP_DISPOSABLE_VM/);
  assert.equal((text(entry).match(/Start-Process/g) || []).length, 1);
  assert.match(text(entry), /Start-Process -FilePath \$installer -ArgumentList '\/NORESTART' -PassThru/);
  assert.doesNotMatch(text(entry), /-Verb\s+RunAs|New-ItemProperty|Remove-ItemProperty/);
  for (const required of ['Dev Box', 'Developer Portal', 'restore point', 'Get-MpComputerStatus',
    'Get-MpThreatDetection', 'Run-InstallerTrial.ps1', 'UNVERIFIED']) {
    assert.ok(source.includes(required), required);
  }
  for (const file of [common, entry]) {
    const result = runPowerShell(`$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile('${fileURLToPath(file).replaceAll("'", "''")}',[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Error $_};exit 1}`);
    assert.equal(result.status, 0, result.stderr || result.error?.message);
  }
});

test('trial bundle pins the retained unsigned CI candidate and states supplemental-only scope', () => {
  const manifestPath = new URL('../tool/devbox-trial/trial-manifest.json', import.meta.url);
  const manifest = JSON.parse(text(manifestPath));
  assert.equal(manifest.kind, 'bloomstep-devbox-installer-trial-v1');
  assert.equal(manifest.source, 'bd5ad93ad28988123ef7d3e28eab989f91cc4362');
  assert.equal(manifest.artifact.runId, '38994109408');
  assert.equal(manifest.artifact.name, 'bloomstep-universal-installer');
  assert.equal(manifest.artifact.installerSha256, '664b60d44929da601e22832568d0c88d8baa70f119764958336e065ff4892162');
  assert.equal(manifest.previousBootstrap.sourceCommit, '33ca30f373a6883ad464834b3cd5c6dc69845c44');
  assert.equal(manifest.protectedGatesAccepted, false);
  for (const hash of Object.values(manifest.payloadManifests)) assert.match(hash, /^[a-f0-9]{64}$/);
  for (const [name, asset] of Object.entries(manifest.previousBootstrap.assets)) {
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    assert.ok(asset.fileName);
    if (name !== 'inno') assert.ok(asset.executable);
  }
});
