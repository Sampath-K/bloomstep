import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = new URL('../tool/protected-vm/', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const run = code => spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `${code}\nexit 0`], {
  encoding: 'utf8',
  env: { ...process.env, BUDLARK_BOOTSTRAP_MODULE: fileURLToPath(new URL('Bootstrap.Common.ps1', root)) },
});

test('retry policy retries only bounded transient transport/status failures', () => {
  const result = run(`
    . $env:BUDLARK_BOOTSTRAP_MODULE
    foreach ($status in @(408,429,500,502,503,504)) {
      if (-not (Test-TransientDownloadFailure $status '')) { throw "Not transient: $status" }
    }
    foreach ($status in @(400,401,403,404,410,422)) {
      if (Test-TransientDownloadFailure $status 'Timeout') { throw "Retried HTTP $status" }
    }
    if (Test-TransientDownloadFailure 0 'TrustFailure') { throw 'Retried TLS trust failure' }
    if (-not (Test-TransientDownloadFailure 0 'Timeout')) { throw 'Timeout not retried' }
    $script:count = 0
    try { Invoke-BoundedDownloadAttempt { $script:count++; throw 'permanent' } { param($e) $false } { param($seconds) }; throw 'Unexpected success' }
    catch { if ($script:count -ne 1) { throw 'Permanent error retried' } }
    $script:count = 0; $script:delays = @()
    try { Invoke-BoundedDownloadAttempt { $script:count++; throw 'transient' } { param($e) $true } { param($seconds) $script:delays += $seconds }; throw 'Unexpected success' }
    catch { if ($script:count -ne 3 -or ($script:delays -join ',') -ne '2,4') { throw 'Unbounded retry or wrong backoff' } }
  `);
  assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message || 'PowerShell failed');
});

test('resume never authorizes registration; terminal states distinguish readiness and reboot', () => {
  const result = run(`
    . $env:BUDLARK_BOOTSTRAP_MODULE
    if ((Get-InnoExitDisposition 0) -ne 'Installed') { throw 'Success lost' }
    if ((Get-InnoExitDisposition 3010) -ne 'RestartRequired') { throw 'Restart lost' }
    try { Get-InnoExitDisposition 5; throw 'Accepted installer failure' } catch { if ($_.Exception.Message -eq 'Accepted installer failure') { throw } }
    $r = New-BootstrapReceipt 'TrustBlocked' 'test-source' 'x64'
    if ($r.registrationAuthorized -or $r.installerAcceptanceVerified -or $r.complete) { throw 'Success-shaped blocked receipt' }
  `);
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});

test('cached downloads, package inventory and partial portable extraction fail closed on tampering', () => {
  const directory = mkdtempSync(join(tmpdir(), 'budlark-bootstrap-test-'));
  try {
    const result = run(`
      . $env:BUDLARK_BOOTSTRAP_MODULE
      $root = '${directory.replaceAll("'", "''")}'
      $file = Join-Path $root 'input.txt'
      [IO.File]::WriteAllText($file, 'verified')
      $hash = (Get-FileHash $file).Hash.ToLowerInvariant()
      $asset = @{url='https://nodejs.org/dist/pinned/input.txt';sha256=$hash}
      Copy-Item $file (Join-Path $root "$hash-input.txt")
      if ((Get-PinnedDownload $asset $root) -ne (Join-Path $root "$hash-input.txt")) { throw 'Cache not reused' }
      [IO.File]::WriteAllText((Join-Path $root "$hash-input.txt"), 'corrupt')
      try { Get-PinnedDownload $asset $root; throw 'Accepted corrupt cache' }
      catch { if ($_.Exception.Message -eq 'Accepted corrupt cache') { throw } }
      @{source=('a'*40);files=@(@{path='input.txt';sha256=$hash})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'package-manifest.json')
      Assert-PackageInventory $root | Out-Null
      [IO.File]::WriteAllText($file, 'modified')
      try { Assert-PackageInventory $root; throw 'Accepted modified bundle' }
      catch { if ($_.Exception.Message -eq 'Accepted modified bundle') { throw } }
      [IO.File]::WriteAllText($file, 'verified')
      Compress-Archive -LiteralPath $file -DestinationPath (Join-Path $root 'tool.zip')
      $destination = Join-Path $root 'portable'
      New-Item -ItemType Directory $destination | Out-Null
      Expand-VerifiedPortable (Join-Path $root 'tool.zip') $destination
      Expand-VerifiedPortable (Join-Path $root 'tool.zip') $destination
      [IO.File]::WriteAllText((Join-Path $destination 'input.txt'), 'changed')
      try { Expand-VerifiedPortable (Join-Path $root 'tool.zip') $destination; throw 'Accepted modified tool' }
      catch { if ($_.Exception.Message -eq 'Accepted modified tool') { throw } }
    `);
    assert.equal(result.status, 0, result.stderr || result.stdout || 'PowerShell failed');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('all dependency downloads are immutable official assets with explicit SHA256', () => {
  const manifest = JSON.parse(read('dependencies.json'));
  for (const asset of Object.values(manifest.assets)) {
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    const url = new URL(asset.url);
    assert.equal(url.protocol, 'https:');
    assert.ok(['github.com', 'nodejs.org'].includes(url.hostname));
    assert.doesNotMatch(url.pathname, /latest/);
  }
  assert.equal(manifest.assets.inno.sha256, '4d11e8050b6185e0d49bd9e8cc661a7a59f44959a621d31d11033124c4e8a7b0');
});

test('single-entry bootstrap and elevation helper cannot register or weaken protection', () => {
  const text = read('Bootstrap.ps1') + read('Install-Inno.ps1');
  assert.doesNotMatch(text, /config\.cmd|run\.cmd|Set-ExecutionPolicy|Unblock-File|Set-MpPreference|Add-MpPreference|schtasks|New-Service/);
  for (const word of ['TrustBlocked', 'BUDLARK_DISPOSABLE_VM', 'Resume', 'checkpoint', 'corporate']) {
    assert.ok(text.includes(word), word);
  }
  assert.ok(read('Install-Inno.ps1').includes('Get-AuthenticodeSignature'));
});

test('PowerShell 5.1-compatible bootstrap files parse without executing', () => {
  for (const name of ['Bootstrap.ps1', 'Bootstrap.Common.ps1', 'Install-Inno.ps1']) {
    const text = read(name);
    assert.doesNotMatch(text, /\$IsWindows|\?\?|\?\./);
    const result = run(`$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseInput(@'\n${text}\n'@,[ref]$tokens,[ref]$errors)|Out-Null; if($errors.Count){$errors|ForEach-Object{Write-Error $_};exit 1}`);
    assert.equal(result.status, 0, result.stderr || result.error?.message);
  }
});
