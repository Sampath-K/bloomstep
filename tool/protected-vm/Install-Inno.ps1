param([Parameter(Mandatory = $true)][string]$PackageRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Bootstrap.Common.ps1"
$manifest = Assert-PackageInventory $PackageRoot
$assets = Get-Content -LiteralPath (Join-Path $PackageRoot 'dependencies.json') -Raw | ConvertFrom-Json
$receipt = New-BootstrapReceipt 'DependencySetup' $manifest.source 'dependency-only'
try {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The dependency-only child needs the separately approved UAC administrator token.'
  }
  $computer = Get-CimInstance Win32_ComputerSystem
  if ($computer.Manufacturer -ne 'Microsoft Corporation' -or $computer.Model -ne 'Virtual Machine') {
    throw 'Dependency installation is restricted to the disposable Hyper-V guest.'
  }
  Confirm-Bootstrap 'Install pinned Inno Setup only; no runner or app will start.' 'INSTALL INNO'
  $installer = Get-PinnedDownload $assets.assets.inno (Join-Path $PackageRoot 'state\downloads')
  $signature = Get-AuthenticodeSignature -LiteralPath $installer
  if ($signature.Status -ne 'Valid') { throw 'Dependency Authenticode verification failed; do not bypass.' }
  $status = Get-MpComputerStatus
  if (-not $status.RealTimeProtectionEnabled -or -not $status.BehaviorMonitorEnabled) {
    throw 'Defender protection must remain active during dependency installation.'
  }
  $process = Start-Process -FilePath $installer -ArgumentList '/SP-', '/NORESTART', '/RESTARTEXITCODE=3010' -Wait -PassThru
  $receipt.stage = Get-InnoExitDisposition $process.ExitCode
  $receipt.exitCode = $process.ExitCode
  $receipt.nextAction = 'Close the elevated child. If restart requested, restart manually. Resume Bootstrap.ps1 as the original STANDARD user.'
} catch {
  $receipt.stage = 'DependencySetupFailed'
  $receipt.nextAction = 'Stop. Inspect dependency/UAC/protection failure locally; no elevation of the runner or security bypass.'
  throw
} finally {
  $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PackageRoot 'state\dependency-receipt.json') -Encoding utf8
}
