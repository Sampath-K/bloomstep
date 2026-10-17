param([switch]$Resume)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$state = Join-Path $root 'state'
$receiptPath = Join-Path $state 'trial-receipt.json'
$receipt = $null
$lock = $null
$ownerPath = Join-Path $state 'installation-owner.json'
$registrationPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}_is1'

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

function Assert-TrialRegistration([string]$Target) {
  $registration = Get-ItemProperty -LiteralPath $registrationPath -ErrorAction Stop
  $expectedUninstall = '"' + (Join-Path $Target 'unins000.exe') + '"'
  if ($registration.DisplayName -ne 'Bloomstep version 0.1.0-preview' -or
      $registration.UninstallString -cne $expectedUninstall -or
      [IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\') -cne [IO.Path]::GetFullPath($Target).TrimEnd('\')) {
    throw 'Product uninstall registration differs from the owned candidate/path; stop for review.'
  }
}

function Assert-NoOtherProductRegistration([bool]$AllowOwned) {
  $roots = @(
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'Registry::HKEY_CURRENT_USER\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach ($registryRoot in $roots) {
    if (-not (Test-Path -LiteralPath $registryRoot)) { continue }
    foreach ($key in Get-ChildItem -LiteralPath $registryRoot -ErrorAction Stop) {
      $displayName = $key.GetValue('DisplayName')
      if ($displayName -like 'Bloomstep*') {
        if (-not $AllowOwned -or
            $registryRoot -ne $roots[0] -or $key.PSChildName -ne '{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}_is1') {
          throw 'Another/preexisting Bloomstep uninstall registration exists. No install or uninstall authorized.'
        }
      }
    }
  }
}

function Get-ProductFootprint([string]$Target) {
  $runPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
  $runKey = $null
  if (Test-Path -LiteralPath $runPath) { $runKey = Get-Item -LiteralPath $runPath -ErrorAction Stop }
  $runValuePresent = $false
  if ($null -ne $runKey) { $runValuePresent = $runKey.GetValueNames() -contains 'Bloomstep' }
  [ordered]@{
    executableRemains = (Test-Path -LiteralPath (Join-Path $Target 'bloomstep.exe')) -or
      (Test-Path -LiteralPath (Join-Path $Target 'unins000.exe')) -or
      (Test-Path -LiteralPath (Join-Path $Target 'unins000.dat'))
    registrationRemains = (Test-Path -LiteralPath $registrationPath) -or
      (Test-Path -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep') -or
      (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Bloomstep')) -or
      (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Bloomstep.lnk')) -or
      $runValuePresent
    processRemains = [bool](Get-Process -Name bloomstep -ErrorAction SilentlyContinue)
  }
}

function Assert-NoInstallerProcess {
  $active = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -eq 'unins000.exe' -or $_.Name -eq 'Bloomstep-0.1.0-preview-windows-universal-setup.exe'
  })
  if ($active.Count) { throw 'An installer/uninstaller is still running. Finish or cancel its window normally before resuming. No concurrent operation authorized.' }
}

function Get-ResidualData {
  [ordered]@{
    localAppDataPresent = Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Bloomstep')
    roamingAppDataPresent = Test-Path -LiteralPath (Join-Path $env:APPDATA 'Bloomstep')
    flutterDataPresent = Test-Path -LiteralPath (Join-Path $env:APPDATA 'com.example\bloomstep')
    applicationSupportDataPresent = Test-Path -LiteralPath (Join-Path $env:APPDATA 'Bloomstep contributors\Bloomstep')
    productSettingsPresent = Test-Path -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Bloomstep'
    dataDeletionAttempted = $false
    machineRestored = $false
  }
}

function Invoke-OwnedTrialUninstall([string]$Target, [string]$Architecture, $UniversalManifest, [string]$CandidateHash) {
  $receipt.stage = 'CleanupRequired'
  $receipt.residualUserData = Get-ResidualData
  $receipt.nextAction = 'Close Bloomstep normally, then confirm product-only uninstall. -Resume retries only verified cleanup, never reinstalls.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  if (-not (Test-Path -LiteralPath $ownerPath)) {
    throw 'No installation ownership receipt exists. Cannot safely automate uninstall of ambiguous/preexisting state.'
  }
  $owner = Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Assert-NoInstallerProcess
  $uninstaller = Assert-OwnedUninstaller $owner $Target $sid $CandidateHash
  Assert-NoOtherProductRegistration $true
  Assert-TrialRegistration $Target
  Assert-InstalledPayload $Target $Architecture $root $UniversalManifest | Out-Null
  $protectionBeforeCleanup = Get-DefenderSnapshot
  Write-Host 'Close Bloomstep normally, including Exit from its tray menu, before continuing. No process will be killed.'
  $confirm = Confirm-Operator "Remove only this trial's Bloomstep program, shortcuts and protocol using its verified uninstaller? App-created user data stays; this is NOT VM rollback. Target: $Target" 'UNINSTALL OWNED TRIAL'
  if (-not $confirm) { throw 'Uninstall declined. Product remains installed; rerun this entry point with -Resume for verified cleanup.' }
  if (Get-Process -Name bloomstep -ErrorAction SilentlyContinue) {
    throw 'Bloomstep is still running. Exit normally via its tray menu and rerun with -Resume; no force kill.'
  }
  # Revalidate after the human confirmation, before executing any uninstall code.
  $uninstaller = Assert-OwnedUninstaller $owner $Target $sid $CandidateHash
  Assert-TrialRegistration $Target
  Assert-NoInstallerProcess
  $null = Get-DefenderSnapshot
  $receipt.stage = 'UninstallStarted'
  $receipt.nextAction = 'Visible uninstall in progress; do not start another trial or cleanup.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/NORESTART' -PassThru
  if (-not $uninstall.WaitForExit(120000)) {
    throw 'Uninstaller exceeded 120 seconds. It was not killed. Finish/cancel its visible window; preserve the receipt and do not run another copy.'
  }
  $receipt.uninstallerExitCode = $uninstall.ExitCode
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  do {
    $footprint = Get-ProductFootprint $Target
    if (-not ($footprint.executableRemains -or $footprint.registrationRemains -or $footprint.processRemains)) { break }
    Start-Sleep -Milliseconds 300
  } while ([DateTime]::UtcNow -lt $deadline)
  $receipt.residualUserData = Get-ResidualData
  $receipt.postUninstallFootprint = $footprint
  $receipt.installDirectoryRemains = Test-Path -LiteralPath $Target
  Assert-UninstallResult $uninstall.ExitCode $footprint.executableRemains $footprint.registrationRemains $footprint.processRemains
  $protectionAfterCleanup = Get-DefenderSnapshot
  $receipt.defenderAfterCleanup = $protectionAfterCleanup.summary
  $receipt.newOrChangedCleanupDetectionCount = @($protectionAfterCleanup.detectionFingerprints | Where-Object {
    $_ -notin $protectionBeforeCleanup.detectionFingerprints
  }).Count
  if ($receipt.newOrChangedCleanupDetectionCount) { throw 'New/changed Defender detection during uninstall. Cleanup acceptance withheld; preserve evidence.' }
  $receipt.cleanupVerified = $true
  $receipt.cleanupOutcome = 'VERIFIED_PRODUCT_REMOVAL_ONLY'
  $receipt.cleanupCompletedAt = [DateTime]::UtcNow.ToString('o')
  $receipt.stage = 'Uninstalled'
  $receipt.nextAction = 'Product removal verified; user data and any unknown residual directory are preserved. This is not a clean-VM proof or machine rollback. Share only trial-receipt.json.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
}

. (Join-Path $root 'Trial.Common.ps1')
New-Item -ItemType Directory -Force -Path $state | Out-Null

try {
  $lock = [IO.File]::Open((Join-Path $state 'trial.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  if ($env:OS -ne 'Windows_NT') { throw 'This package runs only on Windows.' }
  if ([IntPtr]::Size -ne 8) { throw 'Use built-in 64-bit Windows PowerShell, not its x86 edition. No operation started.' }
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
  $previousReceipt = $null
  if (Test-Path -LiteralPath $receiptPath) {
    $previousReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if (-not $Resume) { throw 'A prior trial receipt exists. Use the same entry point with -Resume; no reinstall is automatic.' }
    if ($previousReceipt.schema -ne 2) { throw 'Older trial receipt is not uninstall ownership evidence; stop for review without altering existing product state.' }
  }
  $native = $env:PROCESSOR_ARCHITEW6432
  if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
  $architecture = switch ($native) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    default { throw "Unsupported or emulated architecture '$native'; use native x64 or ARM64 Windows." }
  }
  if ($null -eq $previousReceipt) {
    $receipt = New-DevBoxTrialReceipt $trial.source $architecture $trial.artifact.installerSha256
  } else {
    $receipt = [ordered]@{}
    foreach ($property in $previousReceipt.PSObject.Properties) { $receipt[$property.Name] = $property.Value }
    if ($receipt.source -ne $trial.source -or $receipt.installerSha256 -ne $trial.artifact.installerSha256 -or
        $receipt.architecture -ne $architecture) { throw 'Prior trial candidate/architecture identity mismatch.' }
  }
  $receipt.packageSourceCommit = $package.sourceCommit
  $receipt.artifactRunId = $trial.artifact.runId
  $receipt.artifactName = $trial.artifact.name
  $receipt.published = $false
  $receipt.signed = $false
  $receipt.environment = 'operator-confirmed assigned Microsoft Dev Box; not independently attested by this script'
  $receipt.recoveryMode = 'owned-product-uninstall; no snapshot required; NOT machine rollback'
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
  Assert-NoInstallerProcess
  $defenderBefore = Get-DefenderSnapshot
  $baselineDetectionFingerprints = @($defenderBefore.detectionFingerprints)
  $receipt.defenderBefore = $defenderBefore.summary
  $installTarget = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
  Assert-NoReparsePath $installTarget
  if ($null -ne $previousReceipt -and $previousReceipt.installerExecutionStarted) {
    if ($receipt.cleanupVerified) {
      $footprint = Get-ProductFootprint $installTarget
      Assert-UninstallResult 0 $footprint.executableRemains $footprint.registrationRemains $footprint.processRemains
      Assert-NoOtherProductRegistration $false
      $receipt.residualUserData = Get-ResidualData
      $receipt.installDirectoryRemains = Test-Path -LiteralPath $installTarget
      Write-Host 'Previously verified uninstall remains absent. No installer rerun or data deletion.'
      return
    }
    if ($receipt.stage -eq 'UninstallStarted') { throw 'Earlier uninstall started; completion/exit code is unknown. Do not rerun blindly. Preserve state for review; this script cannot claim successful uninstall without its exit code.' }
    Invoke-OwnedTrialUninstall $installTarget $architecture $universal $trial.artifact.installerSha256
    Write-Host "Cleanup receipt: $receiptPath"
    return
  }
  if ($null -ne $previousReceipt -and $previousReceipt.stage -eq 'LaunchAuthorized') {
    throw 'Previous installer invocation is uncertain and no owned installation was recorded. Stop for review; no reinstall/uninstall authorized.'
  }
  $productPaths = @(
    $installTarget,
    (Join-Path $env:LOCALAPPDATA 'Bloomstep'),
    (Join-Path $env:APPDATA 'Bloomstep'),
    'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep',
    'Registry::HKEY_CURRENT_USER\Software\Bloomstep',
    $registrationPath,
    (Join-Path $env:APPDATA 'com.example\bloomstep'),
    (Join-Path $env:APPDATA 'Bloomstep contributors\Bloomstep')
  )
  Assert-NoOtherProductRegistration $false
  $preexistingFootprint = Get-ProductFootprint $installTarget
  if (@($productPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -or
      $preexistingFootprint.registrationRemains -or $preexistingFootprint.processRemains) {
    throw 'Unowned/preexisting Bloomstep installation or data exists. Nothing will be deleted or adopted. Preserve it and return the blocker for review.'
  }
  $receipt.preflightPassed = $true
  $receipt.stage = 'PreflightPassed'
  Write-Host 'No snapshot is required for this supplemental trial. Uninstall removes only the owned program; user data and other VM changes are not rolled back.'
  $receipt.stage = 'Ready'
  $receipt.nextAction = 'Installer execution still requires a separate explicit confirmation.'
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Write-Host "Candidate: $($trial.artifact.installerFile)"
  Write-Host "Source: $($trial.source); Actions run: $($trial.artifact.runId); SHA-256: $($trial.artifact.installerSha256)"
  Write-Host 'Unsigned, unpublished CI candidate. SmartScreen/Defender warnings must not be bypassed.'
  $executionConfirmed = Confirm-Operator 'This starts the visible installer as the current non-admin user. You will drive the wizard and app test.' 'RUN UNSIGNED CANDIDATE'
  if (-not (Test-DevBoxTrialLaunchAllowed $receipt.stage $receipt.preflightPassed $executionConfirmed)) {
    $receipt.stage = 'Declined'
    $receipt.nextAction = 'No installer was started. Rerun with -Resume only after choosing to perform the owner trial.'
    throw 'Installer launch confirmation declined or guard conditions were not satisfied.'
  }
  if ((Get-FileSha256 $installer) -ne $trial.artifact.installerSha256) {
    throw 'Installer changed after preflight. Do not execute.'
  }
  Assert-InteractiveStandardUser
  Assert-NoInstallerProcess
  Assert-NoOtherProductRegistration $false
  Assert-NoReparsePath $installTarget
  if (@($productPaths | Where-Object { Test-Path -LiteralPath $_ }).Count) { throw 'Product state changed during confirmation. Stop; no install authorized.' }
  $null = Get-DefenderSnapshot
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
    Assert-TrialRegistration $installTarget
    $owner = [ordered]@{
      installTarget = $installTarget
      installingSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
      installerSha256 = $trial.artifact.installerSha256
      uninstallerSha256 = Get-FileSha256 (Join-Path $installTarget 'unins000.exe')
      uninstallDataSha256 = Get-FileSha256 (Join-Path $installTarget 'unins000.dat')
    }
    Assert-OwnedUninstaller $owner $installTarget $owner.installingSid $owner.installerSha256 | Out-Null
    Save-DevBoxTrialReceipt $ownerPath $owner
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
  Save-DevBoxTrialReceipt $receiptPath $receipt
  Invoke-OwnedTrialUninstall $installTarget $architecture $universal $trial.artifact.installerSha256
  Write-Host "Supplemental receipt: $receiptPath"
  Write-Host 'Protected CI gates remain UNVERIFIED. No runner was registered, no policy changed, and no release was authorized.'
} catch {
  if ($null -ne $receipt) {
    if ($receipt.stage -eq 'Created') { $receipt.stage = 'Blocked' }
    if ($receipt.stage -eq 'LaunchAuthorized') {
      $receipt.outcome = 'LAUNCH_NOT_CONFIRMED'
      $receipt.nextAction = 'Installer invocation is uncertain. Stop for review; no ownership evidence exists for automatic reinstall/uninstall.'
    } elseif ($receipt.stage -eq 'InstallerStarted') {
      $receipt.outcome = 'INSTALLER_INTERRUPTED'
      $receipt.nextAction = 'Preserve state. Use -Resume only for verified owned uninstall if ownership was recorded; otherwise stop for review.'
    } elseif ($receipt.stage -eq 'InstallerCompleted') {
      $receipt.outcome = 'POST_INSTALL_CHECK_FAILED'
      $receipt.nextAction = 'Preserve state. -Resume can only uninstall a verified owned installation, never adopt ambiguous state.'
    } elseif ($receipt.stage -in @('CleanupRequired','UninstallStarted','Uninstalled')) {
      $receipt.cleanupVerified = $false
      $receipt.cleanupOutcome = 'FAILED_OR_UNVERIFIED'
      $receipt.nextAction = 'Cleanup not verified. Inspect the visible failure. If no uninstall was started, close the app normally and use -Resume for verified cleanup. Never delete residual data or force-kill processes.'
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
  if ($null -ne $lock) { $lock.Dispose() }
}
