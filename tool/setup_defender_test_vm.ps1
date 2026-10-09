param(
  [ValidateSet('Check','ScanCandidate','RunInstaller')][string]$Mode = 'Check',
  [string]$Installer,
  [string]$ExpectedSha256,
  [string]$EvidenceDir = (Join-Path $env:TEMP 'bloomstep-protected-vm-evidence')
)
$ErrorActionPreference = 'Stop'
$withdrawnHash = 'b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$report = [ordered]@{
  mode = $Mode; startedAt = [DateTime]::UtcNow.ToString('o')
  result = 'BLOCKED'; installerStarted = $false
  staticScanIsNotBehaviorAcceptance = $true
}
try {
  $computer = Get-CimInstance Win32_ComputerSystem
  if ($env:BLOOMSTEP_DISPOSABLE_VM -ne 'true' -or
      $computer.Manufacturer -ne 'Microsoft Corporation' -or $computer.Model -ne 'Virtual Machine') {
    throw 'Only the explicitly marked disposable Hyper-V VM is permitted. Never run on the owner host.'
  }
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  $report.elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $report.administratorMembership = @($identity.Groups | ForEach-Object Value) -contains 'S-1-5-32-544'
  if ($report.elevated -or $report.administratorMembership) {
    throw 'Use the signed-in standard user, not an administrator with a filtered or elevated token.'
  }
  if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) {
    throw 'An active standard-user interactive desktop is required; services are not supported.'
  }
  if (-not ('BloomstepInputDesktop' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BloomstepInputDesktop {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool CloseDesktop(IntPtr desktop);
}
'@
  }
  $desktop = [BloomstepInputDesktop]::OpenInputDesktop(0, $false, 0x0100)
  if ($desktop -eq [IntPtr]::Zero) { throw 'Interactive input desktop access is unavailable.' }
  if (-not [BloomstepInputDesktop]::CloseDesktop($desktop)) { throw 'Input desktop handle could not be closed.' }
  $status = Get-MpComputerStatus
  $report.protection = @{
    antivirus = $status.AntivirusEnabled; realTime = $status.RealTimeProtectionEnabled
    behavior = $status.BehaviorMonitorEnabled; mode = $status.AMRunningMode
    service = $status.AMServiceEnabled; signatures = $status.AntivirusSignatureVersion
    engine = $status.AMEngineVersion; product = $status.AMProductVersion
  }
  if (-not $status.AntivirusEnabled -or -not $status.RealTimeProtectionEnabled -or
      -not $status.BehaviorMonitorEnabled -or -not $status.AMServiceEnabled -or
      $status.AMRunningMode -ne 'Normal') {
    throw 'Defender antivirus, real-time and behavior protection must already be active in Normal mode.'
  }
  $before = @(Get-MpThreatDetection)
  if (@($before | Where-Object { -not $_.ActionSuccess }).Count) {
    throw 'Unresolved prior Defender detections require investigation before testing.'
  }
  if ($Mode -eq 'Check') {
    $report.result = 'PREFLIGHT PASS ONLY; no installer or app execution'
    return
  }
  if (-not $Installer -or $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'RunInstaller requires the exact CI candidate path and independent expected SHA-256.'
  }
  if ([IO.Path]::GetFileName($Installer) -match 'zeroclick') {
    throw 'Autonomous zero-click packages are withdrawn; only the approved standard-flow candidate is permitted.'
  }
  if ($ExpectedSha256.ToLower() -eq $withdrawnHash) { throw 'The withdrawn candidate must never be restored or executed.' }
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash.ToLower()
  if ($actualHash -ne $ExpectedSha256.ToLower()) { throw 'Installer hash mismatch.' }
  $report.sha256 = $actualHash
  Start-MpScan -ScanType CustomScan -ScanPath (Resolve-Path -LiteralPath $Installer).Path
  $baseline = @($before | ForEach-Object DetectionID)
  if (@(Get-MpThreatDetection | Where-Object { $_.DetectionID -notin $baseline }).Count) {
    throw 'Defender detection during pre-run scan; do not execute or restore.'
  }
  $afterScan = Get-MpComputerStatus
  if (-not $afterScan.RealTimeProtectionEnabled -or -not $afterScan.BehaviorMonitorEnabled) {
    throw 'Protection changed before launch.'
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash.ToLower() -ne $actualHash) {
    throw 'Installer changed or was quarantined during scan.'
  }
  if ($Mode -eq 'ScanCandidate') {
    $report.result = 'STATIC SCAN PASS ONLY; behavior and genuine launch unverified'
    return
  }
  $target = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
  $protocol = 'HKCU:\Software\Classes\bloomstep'
  if ((Test-Path $target) -or (Test-Path $protocol)) {
    throw 'VM must start from a clean checkpoint without existing Bloomstep installation or protocol.'
  }
  $log = Join-Path $EvidenceDir 'setup.log'
  $process = Start-Process -FilePath $Installer -ArgumentList "/LOG=`"$log`" /NORESTART" -PassThru
  $report.installerStarted = $true
  $process.WaitForExit()
  $report.launcherExitCode = $process.ExitCode
  $detections = @(Get-MpThreatDetection | Where-Object { $_.DetectionID -notin $baseline })
  $report.detections = @($detections | ForEach-Object {
    @{ id = $_.DetectionID; threatId = $_.ThreatID; time = $_.InitialDetectionTime; actionSuccess = $_.ActionSuccess }
  })
  if ($detections.Count) { throw 'Defender behavior detection during execution; preserve evidence, do not retry.' }
  $final = Get-MpComputerStatus
  if (-not $final.RealTimeProtectionEnabled -or -not $final.BehaviorMonitorEnabled) {
    throw 'Protection changed during execution.'
  }
  if ($process.ExitCode -ne 0) { throw "Setup launcher exited $($process.ExitCode); inspect log before interpreting outcome." }
  $report.result = 'Setup launcher exited without new detection; app launch/user-token/full journey require separate evidence.'
} catch {
  $report.error = $_.Exception.Message
  throw
} finally {
  $report.completedAt = [DateTime]::UtcNow.ToString('o')
  $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $EvidenceDir 'vm-security-receipt.json') -Encoding utf8
}
