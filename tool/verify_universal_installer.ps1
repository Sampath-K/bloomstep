param(
  [Parameter(Mandatory=$true)][string]$PackageDir,
  [Parameter(Mandatory=$true)][ValidateSet('x64','arm64')][string]$ExpectedArch,
  [Parameter(Mandatory=$true)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\universal_integrity_contract.ps1"
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
  throw 'Universal installer lifecycle proof is restricted to disposable GitHub runners.'
}
$manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
$installer = Join-Path $PackageDir $manifest.installerFile
$source = git rev-parse HEAD
if ($manifest.kind -ne 'bloomstep-offline-universal-v1' -or $manifest.source -ne $source -or
    $manifest.installerFile -ne "Bloomstep-$($manifest.version)-windows-universal-setup.exe" -or
    $manifest.installerSha256 -ne (Get-FileHash $installer).Hash.ToLower()) {
  throw 'Universal package source/name/hash authority mismatch.'
}
$payload = Get-Content (Join-Path $PackageDir "payload-manifest-$ExpectedArch.json") -Raw | ConvertFrom-Json
if ($payload.kind -ne 'bloomstep-release-payload-v1' -or $payload.arch -ne $ExpectedArch -or
    $payload.source -ne $manifest.source -or $payload.version -ne $manifest.version) {
  throw 'Selected payload source/version/architecture identity mismatch.'
}
if ($manifest.payloadManifests.$ExpectedArch -ne
    (Get-FileHash (Join-Path $PackageDir "payload-manifest-$ExpectedArch.json")).Hash.ToLower()) {
  throw 'Selected payload manifest hash mismatch.'
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$protection = Start-ProtectedInstallerProof $installer $manifest.installerSha256 $EvidenceDir
$probe = Join-Path $PWD 'native-probe-output\native-host-x64-probe.exe'
$probeManifest = Get-Content (Join-Path $PWD 'native-probe-output\native-probe-manifest.json') -Raw | ConvertFrom-Json
if ($probeManifest.kind -ne 'native-x64-host-query-probe-v1' -or $probeManifest.source -ne $source -or
    $probeManifest.sourceFile -ne 'tool/fixtures/native_architecture_probe.cpp' -or
    $probeManifest.sourceSha256 -ne (Get-FileHash "$PSScriptRoot\fixtures\native_architecture_probe.cpp").Hash.ToLower() -or
    $probeManifest.probeSha256 -ne (Get-FileHash $probe).Hash.ToLower()) {
  throw 'Native x64 host-query probe source/hash authority mismatch.'
}
$probeBytes = [IO.File]::ReadAllBytes($probe)
if ([BitConverter]::ToUInt16($probeBytes,[BitConverter]::ToInt32($probeBytes,60)+4) -ne 0x8664) {
  throw 'Native process probe is not AMD64.'
}
$native = (& $probe $ExpectedArch) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $native.nativeArchitecture -ne $ExpectedArch -or -not $native.process64Bit -or
    ($ExpectedArch -eq 'arm64' -and $native.processMachine -ne 0x8664)) {
  throw 'Actual x64 process native-host/emulation architecture evidence failed.'
}
$target = Join-Path $env:RUNNER_TEMP 'Bloomstep-universal-smoke'
$cancelTarget = Join-Path $env:RUNNER_TEMP 'Bloomstep-universal-cancel'
$corruptTarget = Join-Path $env:RUNNER_TEMP 'Bloomstep-universal-corrupt'
$measurement = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
$protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
foreach ($path in @($target,$cancelTarget,$corruptTarget,$measurement,$protocol)) {
  if (Test-Path $path) { throw 'Clean disposable universal proof refuses pre-existing product state.' }
}
$report = [ordered]@{
  kind = 'actual-universal-native-lifecycle-not-customer-acceptance'
  source = $source; architecture = $ExpectedArch; packageSha256 = $manifest.installerSha256
  compressedBytes = $manifest.bytes; nativeArchitectureProbe = $native
  nativeProbeSha256 = $probeManifest.probeSha256
  offlineMechanism = 'Both payloads embedded, no download/bootstrap/child-installer code'
  keyboardOrNarrator = 'UNKNOWN'; checkedUncheckedInteractiveLaunch = 'UNVERIFIED: separate blocking proof still required'
  stages = [Collections.Generic.List[object]]::new()
  outcome = 'running'
}
$setup = $null
$owned = [Collections.Generic.HashSet[int]]::new()
$ownedProcesses = @{}
$ownedParents = @{}
$proofClock = [Diagnostics.Stopwatch]::StartNew()
function Save-NativeStage([string]$Stage, [string]$Invocation = '') {
  $states = @($ownedProcesses.Keys | ForEach-Object {
    $process = $ownedProcesses[$_]
    $exited = $process.HasExited
    @{ pid = [int]$_; parentPid = $ownedParents[$_]; exited = $exited; exitCode = if ($exited) { $process.ExitCode } else { $null } }
  })
  $dialogs = @([OnboardingWizard]::Windows() | ForEach-Object {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($_,[ref]$owner)
    if ($owned.Contains([int]$owner)) {
      $description = [OnboardingWizard]::Describe($_)
      foreach ($privatePath in @($env:RUNNER_TEMP,$env:LOCALAPPDATA,$env:USERPROFILE)) {
        if ($privatePath) { $description = $description.Replace($privatePath,'[ISOLATED-PATH]') }
      }
      @{ pid = [int]$owner; handle = $_.ToInt64(); description = $description }
    }
  })
  $report.stages.Add(@{
    stage = $Stage; elapsedSeconds = $proofClock.Elapsed.TotalSeconds
    utc = [DateTime]::UtcNow.ToString('o'); invocation = $Invocation
    processes = $states; ownedDialogs = $dialogs
  })
  $report | ConvertTo-Json -Depth 9 | Set-Content (Join-Path $EvidenceDir 'universal-native-receipt.json') -Encoding utf8
}
function Update-NativeOwnedProcesses {
  $snapshot = Get-CimInstance Win32_Process
  for ($i = 0; $i -lt 5; $i++) {
    foreach ($process in $snapshot) {
      $parent = $ownedProcesses[[int]$process.ParentProcessId]
      if ($parent -and -not $parent.HasExited -and -not $owned.Contains([int]$process.ProcessId)) {
        $live = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        if ($live) {
          [void]$live.Handle
          [void]$owned.Add([int]$live.Id)
          $ownedProcesses[[int]$live.Id] = $live
          $ownedParents[[int]$live.Id] = [int]$process.ParentProcessId
        }
      }
    }
  }
}
function Invoke-NativeProcess([string]$Stage, [string]$File, [string]$Arguments, [int]$TimeoutSeconds = 120) {
  Assert-InstallerProtectionUnchanged $protection
  if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 120) { throw 'Native process timeout must be 1 through 120 seconds.' }
  $invocation = "$([IO.Path]::GetFileName($File)) $Arguments"
  foreach ($privatePath in @($env:RUNNER_TEMP,$env:LOCALAPPDATA,$env:USERPROFILE)) {
    if ($privatePath) { $invocation = $invocation.Replace($privatePath,'[ISOLATED-PATH]') }
  }
  Save-NativeStage "$Stage-before-start" $invocation
  $process = Start-Process $File -ArgumentList $Arguments -PassThru
  [void]$process.Handle
  [void]$owned.Add($process.Id)
  $ownedProcesses[$process.Id] = $process
  $ownedParents[$process.Id] = $PID
  Save-NativeStage "$Stage-started"
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $nextReceipt = (Get-Date).AddSeconds(5)
  while ((Get-Date) -lt $deadline) {
    Update-NativeOwnedProcesses
    if ($process.HasExited -and @($ownedProcesses.Values | Where-Object { -not $_.HasExited }).Count -eq 0) {
      Save-NativeStage "$Stage-after-wait"
      return $process
    }
    if ((Get-Date) -ge $nextReceipt) {
      Save-NativeStage "$Stage-waiting"
      $nextReceipt = (Get-Date).AddSeconds(5)
    }
    Start-Sleep -Milliseconds 200
  }
  $report.outcome = 'failure'
  Save-NativeStage "$Stage-timeout"
  foreach ($child in $ownedProcesses.Values) {
    if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force }
  }
  Save-NativeStage "$Stage-timeout-stopped"
  throw "Owned $Stage process tree did not exit within $TimeoutSeconds seconds; inspect stage receipt and owned dialogs."
}
try {
  & .\tool\verify_onboarding_wizard.ps1 -Installer $installer -EvidenceDir $EvidenceDir -LoadHelpersOnly
  Save-NativeStage 'cancel-before-start' '/SP- /NORESTART /DIR=[ISOLATED-CANCEL-TARGET]'
  $setup = Start-Process $installer -ArgumentList "/SP- /NORESTART /DIR=`"$cancelTarget`"" -PassThru
  [void]$owned.Add($setup.Id)
  [void]$setup.Handle
  $ownedProcesses[$setup.Id] = $setup
  $ownedParents[$setup.Id] = $PID
  Save-NativeStage 'cancel-started'
  $wizardProcessId = $null
  $cancelled = $false
  $cancelRequested = $false
  $deadline = (Get-Date).AddSeconds(40)
  while ((Get-Date) -lt $deadline -and -not $cancelled) {
    Update-NativeOwnedProcesses
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$owner = 0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window,[ref]$owner)
      if (-not $owned.Contains([int]$owner)) { continue }
      $text = [OnboardingWizard]::Describe($window)
      if (-not $cancelRequested -and (Get-StandardWizardStage $window) -eq 'ready') {
        $wizardProcess = Get-Process -Id $owner
        [void]$wizardProcess.Handle
        $ownedProcesses[[int]$owner] = $wizardProcess
        $wizardProcessId = [int]$owner
        Start-Sleep -Milliseconds 300
        $rectangle = [OnboardingWizard+Rect]::new()
        if (-not [OnboardingWizard]::GetWindowRect($window,[ref]$rectangle)) { throw 'Owned Welcome bounds unavailable.' }
        $width = $rectangle.Right - $rectangle.Left
        $height = $rectangle.Bottom - $rectangle.Top
        if ($width -lt 100 -or $height -lt 100) { throw 'Owned Welcome bounds invalid.' }
        $bitmap = [Drawing.Bitmap]::new($width,$height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $dc = $graphics.GetHdc()
        try {
          if (-not [OnboardingWizard]::PrintWindow($window,$dc,2)) { throw 'Owned universal Welcome capture failed.' }
        } finally { $graphics.ReleaseHdc($dc) }
        $frame = Join-Path $EvidenceDir 'actual-universal-ready.png'
        try { $bitmap.Save($frame,[Drawing.Imaging.ImageFormat]::Png) }
        finally { $graphics.Dispose(); $bitmap.Dispose() }
        $report.entry = @{
          page = 'ready'
          file = 'actual-universal-ready.png'; sha256 = (Get-FileHash $frame).Hash.ToLower()
          width = $width; height = $height; actualDpi = [OnboardingWizard]::GetDpiForWindow($window)
          scope = 'Actual compiled universal package on isolated CI host; Cancel only, not app acceptance'
        }
        $button = [OnboardingWizard]::Find($window,'Cancel')
        if ($button -eq [IntPtr]::Zero) { throw 'Owned Welcome Cancel control missing.' }
        Save-NativeStage 'cancel-dispatch'
        if (-not [OnboardingWizard]::PostMessage($button,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) {
          throw 'Owned Welcome Cancel dispatch failed.'
        }
        $cancelRequested = $true
        Save-NativeStage 'cancel-dispatched'
      }
      $yes = [OnboardingWizard]::Find($window,'Yes')
      if ($yes -ne [IntPtr]::Zero) {
        if (-not $cancelRequested -or $text -notmatch 'Exit Setup|Do you wish to exit Setup|Setup is not complete') {
          throw 'Unexpected owned Yes dialog; no automatic warning override.'
        }
        Save-NativeStage 'cancel-confirmation'
        if (-not [OnboardingWizard]::PostMessage($yes,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) {
          throw 'Owned Cancel confirmation dispatch failed.'
        }
        Save-NativeStage 'cancel-confirmation-dispatched'
      }
    }
    Start-Sleep -Milliseconds 200
    $setup.Refresh()
    $alive = @($owned | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    $cancelled = $cancelRequested -and $alive.Count -eq 0
  }
  if (-not $cancelled -or (Test-Path $cancelTarget) -or (Test-Path $measurement)) {
    throw 'Welcome Cancel did not finish without payload or observation effects.'
  }
  $wizardExitCode = $ownedProcesses[$wizardProcessId].ExitCode
  $report.cancelWizardExitCode = $wizardExitCode
  $report.cancelLauncherExitCode = $setup.ExitCode
  Assert-WelcomeCancelExit $wizardExitCode
  $report.cancelBeforePayload = $true
  Save-NativeStage 'cancel-exit-verified'
  $installed = Invoke-NativeProcess 'install' $installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$target`""
  if ($installed.ExitCode -ne 0 -or -not (Test-Path "$target\bloomstep.exe")) { throw 'Universal native installation failed.' }
  if (Test-Path $measurement) { throw 'Universal silent installation collected observations.' }
  foreach ($file in $payload.files) {
    $installedPath = Join-Path $target $file.path
    if (-not (Test-Path $installedPath) -or (Get-FileHash $installedPath).Hash.ToLower() -ne $file.sha256) {
      throw "Selected native payload readback mismatch: $($file.path)"
    }
    $actualPaths = @(Get-ChildItem $target -Recurse -File -Force | ForEach-Object {
      [IO.Path]::GetRelativePath($target,$_.FullName).Replace('\','/')
    } | Where-Object { $_ -notin @('unins000.exe','unins000.dat','unins000.msg') } | Sort-Object)
    $expectedPaths = @($payload.files.path | Sort-Object)
    if (Compare-Object $actualPaths $expectedPaths) {
      throw 'Installed inventory contains extra or missing files, possibly from the non-selected payload.'
    }
  }
  $bytes = [IO.File]::ReadAllBytes("$target\bloomstep.exe")
  $machine = [BitConverter]::ToUInt16($bytes,[BitConverter]::ToInt32($bytes,60)+4)
  $expectedMachine = if ($ExpectedArch -eq 'arm64') {0xaa64} else {0x8664}
  if ($machine -ne $expectedMachine) { throw 'Installed PE is not native to the OS.' }
  $report.selectedPayloadAllHashesVerified = $true
  $report.installedPeMachine = $machine
  $report.nonSelectedPayloadNotInstalled = $true
  $uninstall = Invoke-NativeProcess 'uninstall' "$target\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
  if ($uninstall.ExitCode -ne 0 -or (Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol)) {
    throw 'Universal owned uninstall did not remove payload/protocol.'
  }
  $report.uninstallVerified = $true
  $report.defaultOffObservationReceiptAbsent = -not (Test-Path $measurement)
  $faultDir = Join-Path $PWD 'universal-integrity-output'
  $fault = Get-Content "$faultDir\integrity-manifest.json" -Raw | ConvertFrom-Json
  $faultExe = Join-Path $faultDir 'isolated-corrupted-setup.exe'
  if ($fault.kind -ne 'isolated-embedded-checksum-fault-v1' -or $fault.source -ne $source -or
      $fault.fixtureAppId -ne 'A6690692-4D92-475A-9EAC-1AD867AB0635' -or
      $fault.installerSha256 -ne (Get-FileHash $faultExe).Hash.ToLower() -or
      -not (Test-BloomstepInnoProductName (Get-Item $faultExe).VersionInfo.ProductName 'Bloomstep isolated journey proof')) {
    throw 'Isolated corrupted fixture identity/hash authority mismatch.'
  }
  $faultLog = Join-Path $env:RUNNER_TEMP 'Bloomstep-universal-corrupt-private.log'
  $report.corruptionLogFile = [IO.Path]::GetFileName($faultLog)
  & "$PSScriptRoot\setup_defender_test_vm.ps1" -Mode ScanCandidate -Installer $faultExe `
    -ExpectedSha256 (Get-FileHash $faultExe).Hash.ToLower() -EvidenceDir (Join-Path $EvidenceDir 'fault-fixture-scan')
  $failed = Invoke-NativeProcess 'corrupt' $faultExe "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$corruptTarget`" /LOG=`"$faultLog`""
  $checksumErrors = if (Test-Path $faultLog) { @(Get-EmbeddedChecksumErrors (Get-Content $faultLog)) } else { @() }
  $remainingFiles = if (Test-Path $corruptTarget) { @(Get-ChildItem $corruptTarget -Recurse -File -Force) } else { @() }
  if ($failed.ExitCode -eq 0 -or $remainingFiles.Count -ne 0 -or
      (Test-Path $measurement) -or $checksumErrors.Count -eq 0) {
    throw 'Corrupted embedded payload was not rejected with rollback and no observation effects.'
  }
  $report.corruptedEmbeddedChecksumRollbackVerified = $true
  $report.checksumErrorLines = $checksumErrors
  $report.corruptMarkerAndPayloadAbsent = $true
  $report.corruptExitCode = $failed.ExitCode
  Assert-InstallerProtectionUnchanged $protection
  $report.outcome = 'success'
} catch {
  $report.outcome = 'failure'
  Save-NativeStage 'failure'
  throw
} finally {
  Save-NativeStage 'cleanup-before'
  foreach ($process in $ownedProcesses.Values) {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
  }
  Assert-InstallerProtectionUnchanged $protection
  if (Test-Path "$target\unins000.exe") {
    $cleanup = Invoke-NativeProcess 'cleanup-uninstall' "$target\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    if ($cleanup.ExitCode -ne 0) {
      $report.outcome = 'failure'
      Save-NativeStage 'cleanup-uninstall-failed'
      throw 'Owned cleanup uninstaller failed; inspect stage receipt.'
    }
  }
  Save-NativeStage 'cleanup-after'
}
