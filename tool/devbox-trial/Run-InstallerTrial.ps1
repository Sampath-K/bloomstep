param([switch]$Resume)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$state = Join-Path $root 'state'
$receiptPath = Join-Path $state 'trial-receipt.json'
$receipt = $null
$stage = 'PackageCheck'

function Get-FileSha256([string]$Path) {
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Package([string]$PackageRoot) {
  $package = Get-Content -LiteralPath (Join-Path $PackageRoot 'package-manifest.json') -Raw | ConvertFrom-Json
  if ($package.kind -ne 'bloomstep-devbox-installer-trial-package-v1' -or
      $package.sourceCommit -notmatch '^[a-f0-9]{40}$') {
    throw 'Package source manifest is invalid. Re-download the ZIP and verify its external SHA-256.'
  }
  $expected = @(
    'Run-InstallerTrial.ps1', 'Trial.Common.ps1', 'trial-manifest.json', 'README.md',
    'Bloomstep-0.1.0-preview-windows-universal-setup.exe',
    'universal-manifest.json', 'payload-manifest-x64.json', 'payload-manifest-arm64.json'
  )
  $actual = @($package.files | ForEach-Object path | Sort-Object -Unique)
  if (($actual -join '|') -ne (($expected | Sort-Object) -join '|')) {
    throw 'Package file inventory differs from the fixed trial bundle.'
  }
  $expectedRootFiles = @($expected + 'package-manifest.json' | Sort-Object -Unique)
  $actualRootFiles = @(Get-ChildItem -LiteralPath $PackageRoot -File -Force | ForEach-Object Name | Sort-Object -Unique)
  if (($actualRootFiles -join '|') -ne ($expectedRootFiles -join '|')) {
    throw 'Unexpected or missing file beside the package manifest; do not execute.'
  }
  $unexpectedDirectories = @(Get-ChildItem -LiteralPath $PackageRoot -Directory -Force | Where-Object Name -ne 'state')
  if ($unexpectedDirectories.Count) { throw 'Unexpected directory beside the package; do not execute.' }
  foreach ($file in $package.files) {
    if ($file.path -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))' -or
        $file.sha256 -notmatch '^[a-f0-9]{64}$') {
      throw 'Unsafe or invalid package inventory entry.'
    }
    if ((Get-FileSha256 (Join-Path $PackageRoot $file.path)) -ne $file.sha256) {
      throw 'Package file hash mismatch. Do not execute; re-download the verified ZIP.'
    }
  }
  return $package
}

function Assert-NoPreviousBootstrapRunning {
  $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('powershell.exe','pwsh.exe') -and
    $_.CommandLine -match '(?i)bloomstep-vm-bootstrap[\\/]+(Bootstrap|Install-Inno)\.ps1'
  })
  if ($processes.Count) {
    throw 'The prerequisite bootstrap is still running. Let it finish; do not start another setup concurrently.'
  }
}

function Assert-PreviousBootstrapCache([string]$PreviousRoot, [string]$Architecture, $PinnedAssets) {
  $packageManifestPath = Join-Path $PreviousRoot 'package-manifest.json'
  if (-not (Test-Path -LiteralPath $packageManifestPath)) { return 'NOT_FOUND; no files changed' }
  $previousManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
  if ($previousManifest.kind -ne 'bloomstep-vm-bootstrap-package-v1' -or
      $previousManifest.source -ne '33ca30f373a6883ad464834b3cd5c6dc69845c44') {
    throw 'A prior bootstrap folder exists but its source package is unrecognized; preserve it and stop.'
  }
  foreach ($file in $previousManifest.files) {
    if ($file.path -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))' -or
        (Get-FileSha256 (Join-Path $PreviousRoot $file.path)) -ne $file.sha256) {
      throw 'Prior bootstrap source files do not match their manifest; preserve caches and stop.'
    }
  }
  $priorState = Join-Path $PreviousRoot 'state'
  $statusPath = Join-Path $priorState 'bootstrap-receipt.json'
  $priorStage = if (Test-Path -LiteralPath $statusPath) {
    [string](Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json).stage
  } else { 'NO RECEIPT' }
  $verified = 0
  foreach ($tool in @('pwsh','git','node')) {
    $key = "$tool-$Architecture"
    $asset = $PinnedAssets.$key
    $archivePath = Join-Path (Join-Path $priorState 'downloads') ($asset.sha256 + '-' + $asset.fileName)
    $destination = Join-Path (Join-Path $priorState "tools\$tool-$Architecture") ''
    $hasArchive = Test-Path -LiteralPath $archivePath
    $hasTree = Test-Path -LiteralPath $destination
    if (-not $hasArchive -and -not $hasTree) { continue }
    if (-not $hasArchive -or -not $hasTree -or (Get-FileSha256 $archivePath) -ne $asset.sha256) {
      throw "Prior cached $tool files are incomplete or changed. Preserve them; do not reinstall or delete."
    }
    Assert-VerifiedPortableCache $archivePath $destination $asset.sha256 | Out-Null
    $verified++
  }
  $innoAsset = $PinnedAssets.inno
  $innoArchive = Join-Path (Join-Path $priorState 'downloads') ($innoAsset.sha256 + '-' + $innoAsset.fileName)
  if (Test-Path -LiteralPath $innoArchive) {
    if ((Get-FileSha256 $innoArchive) -ne $innoAsset.sha256 -or
        (Get-AuthenticodeSignature -LiteralPath $innoArchive).Status -ne 'Valid') {
      throw 'Prior cached Inno installer is not the pinned, validly signed installer; preserve it and stop.'
    }
    $innoCacheStatus = 'pinned installer hash and Authenticode signature verified'
  } else {
    $innoCacheStatus = 'installer cache not present'
  }
  $programFilesX86 = ${env:ProgramFiles(x86)}
  if (-not $programFilesX86) { $programFilesX86 = $env:ProgramFiles }
  $innoPath = Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'
  if (-not (Test-Path -LiteralPath $innoPath)) {
    $innoStatus = 'NOT PRESENT; not required for this already-built installer trial'
  } else {
    $innoVersion = (Get-Item -LiteralPath $innoPath).VersionInfo.FileVersion
    $innoSignature = Get-AuthenticodeSignature -LiteralPath $innoPath
    if ($innoVersion -match '^6\.7\.1(?:\.|$)' -and $innoSignature.Status -eq 'Valid') {
      $innoStatus = 'VERIFIED pinned 6.7.1 signed compiler; not executed by this trial'
    } else {
      $innoStatus = "PRESENT BUT NOT VERIFIED (version $innoVersion, signature $($innoSignature.Status)); not executed or used"
    }
  }
  return "Receipt stage $priorStage; verified $verified pinned portable-tool cache(s); Inno installer cache $innoCacheStatus; installed compiler $innoStatus; no files modified"
}

function Assert-InteractiveStandardUser {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
      @($identity.Groups | ForEach-Object Value) -contains 'S-1-5-32-544') {
    throw 'Use a standard-user token that is not a member of local Administrators.'
  }
  if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) {
    throw 'An interactive signed-in desktop session is required.'
  }
  if (-not ('BloomstepDevBoxInputDesktop' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BloomstepDevBoxInputDesktop {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool CloseDesktop(IntPtr desktop);
}
'@
  }
  $desktop = [BloomstepDevBoxInputDesktop]::OpenInputDesktop(0, $false, 0x0100)
  if ($desktop -eq [IntPtr]::Zero) { throw 'The interactive input desktop is unavailable.' }
  if (-not [BloomstepDevBoxInputDesktop]::CloseDesktop($desktop)) { throw 'The input desktop could not be closed cleanly.' }
}

function Get-DefenderSnapshot {
  $status = Get-MpComputerStatus -ErrorAction Stop
  foreach ($required in @('AntivirusEnabled','RealTimeProtectionEnabled','BehaviorMonitorEnabled','AMServiceEnabled')) {
    if (-not [bool]$status.$required) { throw "Microsoft Defender $required is not enabled." }
  }
  if ($status.AMRunningMode -ne 'Normal') { throw 'Microsoft Defender is not running in Normal mode.' }
  $detections = @(Get-MpThreatDetection -ErrorAction Stop)
  $unresolved = @($detections | Where-Object { -not $_.ActionSuccess })
  if ($unresolved.Count) { throw 'Unresolved Microsoft Defender detections require owner/IT review; no installer will run.' }
  return [ordered]@{
    summary = @{
      antivirus = [bool]$status.AntivirusEnabled
      realTime = [bool]$status.RealTimeProtectionEnabled
      behavior = [bool]$status.BehaviorMonitorEnabled
      service = [bool]$status.AMServiceEnabled
      mode = [string]$status.AMRunningMode
      unresolvedDetectionCount = $unresolved.Count
    }
    detectionFingerprints = @($detections | ForEach-Object {
      "$($_.DetectionID)|$($_.ThreatID)|$($_.LastThreatStatusChangeTime)|$($_.ThreatStatusID)"
    } | Sort-Object -Unique)
  }
}

function Confirm-Operator([string]$Prompt, [string]$RequiredText) {
  (Read-Host "$Prompt Type exactly: $RequiredText") -ceq $RequiredText
}

. (Join-Path $root 'Trial.Common.ps1')
New-Item -ItemType Directory -Force -Path $state | Out-Null

try {
  if ($env:OS -ne 'Windows_NT') { throw 'This package runs only on Windows.' }
  $package = Assert-Package $root
  $trial = Get-Content -LiteralPath (Join-Path $root 'trial-manifest.json') -Raw | ConvertFrom-Json
  if ($trial.kind -ne 'bloomstep-devbox-installer-trial-v1' -or
      $trial.source -ne 'bd5ad93ad28988123ef7d3e28eab989f91cc4362' -or
      $trial.artifact.runId -ne '38994109408' -or
      $trial.artifact.installerSha256 -ne '664b60d44929da601e22832568d0c88d8baa70f119764958336e065ff4892162' -or
      $trial.protectedGatesAccepted -ne $false) {
    throw 'Candidate identity/scope mismatch. Do not execute.'
  }
  $installer = Join-Path $root $trial.artifact.installerFile
  $universal = Get-Content -LiteralPath (Join-Path $root 'universal-manifest.json') -Raw | ConvertFrom-Json
  if ($universal.source -ne $trial.source -or $universal.installerSha256 -ne $trial.artifact.installerSha256 -or
      $universal.signatureStatus -ne 'NotSigned' -or
      $universal.distribution -notmatch '^UNPUBLISHED') {
    throw 'Installer manifest does not describe the exact unsigned, unpublished CI candidate.'
  }
  foreach ($arch in @('x64','arm64')) {
    $payloadPath = Join-Path $root "payload-manifest-$arch.json"
    if ((Get-FileSha256 $payloadPath) -ne $universal.payloadManifests.$arch) {
      throw "The $arch payload manifest hash does not match the universal manifest."
    }
    $payload = Get-Content -LiteralPath $payloadPath -Raw | ConvertFrom-Json
    if ($payload.source -ne $trial.source -or $payload.arch -ne $arch) { throw "The $arch payload identity is inconsistent." }
  }
  if ((Get-FileSha256 $installer) -ne $trial.artifact.installerSha256) {
    throw 'Installer SHA-256 mismatch. Do not execute or attempt to repair the package.'
  }
  if (Test-Path -LiteralPath $receiptPath) {
    $previousReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($previousReceipt.installerExecutionStarted -or
        $previousReceipt.stage -in @('LaunchAuthorized','InstallerStarted','InstallerCompleted')) {
      throw 'This package already authorized/started the installer. Do not rerun it; preserve the receipt and use the Dev Box restore controls if recovery is needed.'
    }
    if (-not $Resume -and $previousReceipt.stage -notin @('Failed','Declined')) {
      throw 'A prior trial receipt exists. Use -Resume to revalidate it; no prior confirmation is reused.'
    }
  }
  $native = $env:PROCESSOR_ARCHITEW6432
  if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
  $architecture = switch ($native) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    default { throw "Unsupported or emulated architecture '$native'; use native x64 or ARM64 Windows." }
  }
  $receipt = New-DevBoxTrialReceipt $trial.source $architecture $trial.artifact.installerSha256
  $receipt.packageSourceCommit = $package.sourceCommit
  $receipt.artifactRunId = $trial.artifact.runId
  $receipt.artifactName = $trial.artifact.name
  $receipt.published = $false
  $receipt.signed = $false
  $receipt.environment = 'operator-confirmed assigned Microsoft Dev Box; not independently attested by this script'
  $receipt.restoreMechanism = 'Microsoft Dev Box Developer Portal managed snapshot/restore; not host Hyper-V checkpoint'
  if ($Resume) { $receipt.resume = 'All package, platform, Defender, and clean-state checks rerun; no prior approval reused.' }
  Assert-NoPreviousBootstrapRunning
  $previousRoot = Join-Path (Split-Path (Split-Path $root -Parent) -Parent) 'BloomstepVM\bloomstep-vm-bootstrap'
  $receipt.previousBootstrapCache = Assert-PreviousBootstrapCache $previousRoot $architecture $trial.previousBootstrap.assets
  $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  $receipt.virtualMachinePlatform = ($system.Manufacturer -eq 'Microsoft Corporation' -and $system.Model -eq 'Virtual Machine')
  if (-not $receipt.virtualMachinePlatform) { throw 'Windows does not report the expected Microsoft virtual-machine platform.' }
  if (-not (Confirm-Operator 'Confirm this is your assigned Dev Box and you are authorized to run this local owner trial.' 'MY ASSIGNED DEV BOX')) {
    $receipt.stage = 'Declined'
    $receipt.nextAction = 'Run only on the owner-authorized Dev Box; no installer was started.'
    throw 'Operator did not confirm the assigned Dev Box.'
  }
  Assert-InteractiveStandardUser
  $defenderBefore = Get-DefenderSnapshot
  $baselineDetectionFingerprints = @($defenderBefore.detectionFingerprints)
  $receipt.defenderBefore = $defenderBefore.summary
  $installTarget = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
  $protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep'
  $productPaths = @(
    $installTarget,
    (Join-Path $env:LOCALAPPDATA 'Bloomstep'),
    (Join-Path $env:APPDATA 'Bloomstep'),
    'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep',
    'Registry::HKEY_CURRENT_USER\Software\Bloomstep'
  )
  if (@($productPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -or
      (Get-Process -Name bloomstep -ErrorAction SilentlyContinue)) {
    throw 'Bloomstep state already exists. Nothing will be deleted; restore a clean Dev Box managed snapshot before this trial.'
  }
  $receipt.preflightPassed = $true
  $receipt.stage = 'PreflightPassed'
  $receipt.nextAction = 'Create a manual Dev Box snapshot in the Developer Portal now if one does not already exist. Confirm it is listed and usable; restoring discards all later Dev Box changes.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Write-Host 'Recovery is a managed Dev Box snapshot, not a host Hyper-V checkpoint. The script cannot verify or create that snapshot.'
  Write-Host 'Create/confirm the snapshot in the Developer Portal; back up anything you may need after a restore.'
  if (-not (Confirm-Operator 'Confirm you personally verified the Dev Box restore point is listed and usable, and accept loss of changes made after it on restore.' 'MANAGED RESTORE POINT READY')) {
    $receipt.stage = 'Declined'
    $receipt.nextAction = 'Create and verify a Dev Box managed snapshot in the Developer Portal, then rerun this entry point with -Resume. No installer was started.'
    throw 'No Dev Box restore point was confirmed.'
  }
  $receipt.restorePointOperatorConfirmed = $true
  $receipt.restorePointVerifiedByScript = $false
  $receipt.stage = 'Ready'
  $receipt.nextAction = 'Installer execution still requires a separate explicit confirmation.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Write-Host "Candidate: $($trial.artifact.installerFile)"
  Write-Host "Source: $($trial.source); Actions run: $($trial.artifact.runId); SHA-256: $($trial.artifact.installerSha256)"
  Write-Host 'Unsigned, unpublished CI candidate. SmartScreen/Defender warnings must not be bypassed.'
  $executionConfirmed = Confirm-Operator 'This starts the visible installer as the current non-admin user. You will drive the wizard and app test.' 'RUN UNSIGNED CANDIDATE'
  if (-not (Test-DevBoxTrialLaunchAllowed $receipt.stage $receipt.preflightPassed $receipt.restorePointOperatorConfirmed $executionConfirmed)) {
    $receipt.stage = 'Declined'
    $receipt.nextAction = 'No installer was started. Rerun with -Resume only after choosing to perform the owner trial.'
    throw 'Installer launch confirmation declined or guard conditions were not satisfied.'
  }
  if ((Get-FileSha256 $installer) -ne $trial.artifact.installerSha256) {
    throw 'Installer changed after preflight. Do not execute.'
  }
  $receipt.stage = 'LaunchAuthorized'
  $receipt.installerExecutionAuthorizedAt = [DateTime]::UtcNow.ToString('o')
  $receipt.nextAction = 'Installer launch authorized; do not rerun this package if the process is interrupted.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  $process = Start-Process -FilePath $installer -ArgumentList '/NORESTART' -PassThru
  $receipt.installerExecutionStarted = $true
  $receipt.installerProcessId = $process.Id
  $receipt.stage = 'InstallerStarted'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  $process.WaitForExit()
  $receipt.installerExitCode = $process.ExitCode
  $receipt.stage = 'InstallerCompleted'
  if ($receipt.installerExitCode -eq 0) {
    $receipt.installedPayloadFileCount = Assert-InstalledPayload $installTarget $architecture $root $universal
    $receipt.installedPayloadIntegrity = 'PASS'
  } else {
    $receipt.installedPayloadIntegrity = 'NOT_CHECKED; installer exit code was nonzero'
  }
  $defenderAfter = Get-DefenderSnapshot
  $receipt.defenderAfter = $defenderAfter.summary
  $newDetections = @($defenderAfter.detectionFingerprints | Where-Object { $_ -notin $baselineDetectionFingerprints })
  $receipt.newOrChangedDetectionCount = $newDetections.Count
  if ($newDetections.Count) { throw 'New Microsoft Defender detections occurred during the owner trial; stop and preserve the Dev Box state.' }
  $receipt.expectedInstallPathPresent = Test-Path -LiteralPath (Join-Path $installTarget 'bloomstep.exe')
  $receipt.nextAction = 'After the installer exits, manually check the finished wizard and launch/open the installed app. Confirm only what you personally observed.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Write-Host 'If the app did not open automatically, launch Bloomstep from its Start Menu shortcut now. Do not bypass any Windows warning.'
  $wizardObserved = Confirm-Operator 'Did the visible installer finish normally without a warning or error?' 'YES'
  $appObserved = Confirm-Operator 'Did you personally observe the installed app open to its expected first screen?' 'YES'
  $receipt.ownerConfirmedInstallerWizard = $wizardObserved
  $receipt.ownerConfirmedAppFirstScreen = $appObserved
  $receipt.appExecutablePresent = [bool]$receipt.expectedInstallPathPresent
  $receipt.payloadVerified = ($receipt.installedPayloadIntegrity -eq 'PASS')
  $receipt.outcome = Get-DevBoxTrialOutcome $receipt.installerExitCode $receipt.payloadVerified $wizardObserved $appObserved
  $receipt.stage = 'TrialRecorded'
  $receipt.completedAt = [DateTime]::UtcNow.ToString('o')
  $receipt.restoreAction = 'NOT_PERFORMED; owner controls restore in the Dev Box Developer Portal'
  $receipt.nextAction = 'Review the sanitized receipt. This owner trial is supplemental only and does not satisfy any protected Actions gate.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Write-Host "Supplemental receipt: $receiptPath"
  Write-Host 'Protected CI gates remain UNVERIFIED. No runner was registered, no policy changed, and no release was authorized.'
} catch {
  if ($null -ne $receipt) {
    if ($receipt.stage -eq 'Created') { $receipt.stage = 'Blocked' }
    if ($receipt.stage -eq 'LaunchAuthorized') {
      $receipt.outcome = 'LAUNCH_NOT_CONFIRMED'
      $receipt.nextAction = 'Do not rerun. The installer may have been invoked; inspect local state and use the Dev Box Developer Portal restore point if recovery is needed.'
    } elseif ($receipt.stage -eq 'InstallerStarted') {
      $receipt.outcome = 'INSTALLER_INTERRUPTED'
      $receipt.nextAction = 'Do not rerun. Preserve the Dev Box and receipt; inspect the installer state or restore through the Dev Box Developer Portal.'
    } elseif ($receipt.stage -eq 'InstallerCompleted') {
      $receipt.outcome = 'POST_INSTALL_CHECK_FAILED'
      $receipt.nextAction = 'Do not rerun. Preserve the Dev Box and receipt; inspect the stated failure or restore through the Dev Box Developer Portal.'
    } elseif ($receipt.stage -notin @('Declined','TrialRecorded')) {
      $receipt.outcome = 'BLOCKED'
      $receipt.nextAction = 'Read the visible error and resolve only the stated supported dependency. Do not bypass Windows protection or alter tenant policy.'
    } elseif ($receipt.stage -eq 'Declined') {
      $receipt.outcome = 'OPERATOR_DECLINED'
    }
    $receipt.completedAt = [DateTime]::UtcNow.ToString('o')
  }
  Write-Error $_
  exit 1
} finally {
  if ($null -ne $receipt) {
    Save-DevBoxTrialReceipt $receiptPath $receipt
    Write-Host "Sanitized local receipt: $receiptPath"
  }
}
