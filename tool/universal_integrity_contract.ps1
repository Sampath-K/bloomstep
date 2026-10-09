function Get-EmbeddedChecksumErrors([string[]]$Lines) {
  $expected = '^\s*(?:\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{3})?\s+)?(?:Error:\s*)?(?:The source file is corrupted\.?|Verification of the source file failed: The hash of the file is incorrect\.?)\s*$'
  @($Lines | Where-Object { $_ -match $expected } | ForEach-Object {
    if ($_ -match 'Verification of the source file failed:') {
      'Verification of the source file failed: The hash of the file is incorrect'
    } else { 'The source file is corrupted' }
  } | Select-Object -Unique)
}

function Assert-WelcomeCancelExit([int]$ExitCode) {
  if ($ExitCode -ne 2) { throw "Owned Welcome wizard did not return Inno's pre-install Cancel exit code 2: $ExitCode" }
}

function Test-BloomstepInnoProductName([string]$ProductName,
    [ValidateSet('Bloomstep','Bloomstep isolated journey proof')][string]$ExpectedName = 'Bloomstep') {
  if ($null -eq $ProductName) { return $false }
  return ($ProductName.TrimEnd([char]32) -ceq $ExpectedName)
}

function Assert-GenuineLaunchOutcome([string]$Mode, [int]$WizardExitCode, [int]$LauncherExitCode,
    [int]$LaunchCount, [bool]$SameAppAlive, [bool]$VisibleOwnedWindow) {
  if ($Mode -notin @('checked-launch','unchecked-launch','silent-no-launch') -or $WizardExitCode -ne 0 -or $LauncherExitCode -ne 0) {
    throw 'Genuine checked/unchecked/silent proof requires successful actual wizard and launcher exit0.'
  }
  if ($Mode -eq 'checked-launch') {
    if ($LaunchCount -ne 1 -or -not $SameAppAlive -or -not $VisibleOwnedWindow) {
      throw 'Genuine explicitly checked app must survive the observation window with one exact-target process and visible owned window.'
    }
  } elseif ($LaunchCount -ne 0 -or $SameAppAlive -or $VisibleOwnedWindow) {
    throw 'Genuine unchecked or silent install must produce no app process or window.'
  }
}

function New-StandardWizardJourney {
  @{
    stages = [Collections.Generic.List[string]]::new()
    nextClicks = 0; installClicks = 0; finishClicks = 0
    launchDefaultUnchecked = $null; launchSelected = $false
  }
}

function Get-StandardWizardStage([IntPtr]$Window) {
  $text = [OnboardingWizard]::Describe($Window)
  if ([OnboardingWizard]::Find($Window, 'Finish') -ne [IntPtr]::Zero) { return 'finish' }
  if ($text.Contains('Installing')) { return 'installing' }
  if ($text.Contains('Ready to Install')) { return 'ready' }
  if ($text.Contains('Select Destination Location')) { return 'destination' }
  if ($text.Contains('Welcome') -or $text.Contains('Anchor')) { return 'welcome' }
  return $null
}

function Invoke-StandardWizardStep([IntPtr]$Window, [hashtable]$Journey, [bool]$CheckLaunch = $false) {
  $stage = Get-StandardWizardStage $Window
  if (-not $stage) { throw 'Unknown native wizard page; no automatic override.' }
  if ($Journey.stages.Contains($stage)) {
    if ($Journey.stages[$Journey.stages.Count - 1] -ne $stage) { throw 'Native wizard unexpectedly returned to an earlier page.' }
    return $stage
  }
  $expected = @('welcome','destination','ready','installing','finish')
  if ($Journey.stages.Count -ge $expected.Count -or $stage -ne $expected[$Journey.stages.Count]) {
    throw "Native wizard page skipped or auto-advanced: $stage"
  }
  $Journey.stages.Add($stage)
  if ($stage -eq 'installing') { return $stage }
  $caption = if ($stage -eq 'ready') { 'Install' } elseif ($stage -eq 'finish') { 'Finish' } else { 'Next >' }
  $button = [OnboardingWizard]::Find($Window, $caption)
  if ($button -eq [IntPtr]::Zero -and $caption -eq 'Next >') {
    $button = [OnboardingWizard]::Find($Window, 'Next')
  }
  if ($button -eq [IntPtr]::Zero) { throw "Native $stage button missing: $caption" }
  if ($stage -eq 'finish') {
    $choice = [OnboardingWizard]::LaunchChoiceState($Window)
    if ($choice -eq 1) { throw 'Launch Bloomstep must be unchecked by default.' }
    if ($choice -eq -1 -and $CheckLaunch) { throw 'Explicit Launch Bloomstep choice unavailable on checked proof.' }
    $Journey.launchDefaultUnchecked = if ($choice -eq 0) { $true } else { $null }
    if ($CheckLaunch) {
      [OnboardingWizard]::ToggleLaunchChoice($Window)
      $deadline = (Get-Date).AddSeconds(2)
      while ([OnboardingWizard]::LaunchChoiceState($Window) -ne 1 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
      }
      if ([OnboardingWizard]::LaunchChoiceState($Window) -ne 1) { throw 'Explicit Launch Bloomstep selection was not verified.' }
      $Journey.launchSelected = $true
    }
  }
  # Test-driver input on the disposable desktop, not automatic customer setup behavior.
  if (-not [OnboardingWizard]::PostMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)) {
    throw "Owned native $caption dispatch failed."
  }
  if ($stage -eq 'ready') { $Journey.installClicks++ }
  elseif ($stage -eq 'finish') { $Journey.finishClicks++ }
  else { $Journey.nextClicks++ }
  return $stage
}

function Assert-StandardWizardJourney([hashtable]$Journey, [bool]$CheckLaunch = $false, [bool]$ChoiceRequired = $true) {
  if (($Journey.stages -join ',') -ne 'welcome,destination,ready,installing,finish' -or
      $Journey.nextClicks -ne 2 -or $Journey.installClicks -ne 1 -or $Journey.finishClicks -ne 1) {
    throw 'Standard proof requires Welcome, destination, Ready, Installing, Finish and explicit test-driver clicks.'
  }
  if (($ChoiceRequired -and $Journey.launchDefaultUnchecked -ne $true) -or $Journey.launchSelected -ne $CheckLaunch) {
    throw 'Native default-off launch choice proof mismatch.'
  }
}

function Get-InstallerProtectionSnapshot {
  $status = Get-MpComputerStatus -ErrorAction Stop
  $flags = [ordered]@{}
  foreach ($name in @('AntivirusEnabled','RealTimeProtectionEnabled','BehaviorMonitorEnabled',
      'AMServiceEnabled','AntispywareEnabled','IoavProtectionEnabled','NISEnabled')) {
    $flags[$name] = [bool]$status.$name
  }
  foreach ($required in @('AntivirusEnabled','RealTimeProtectionEnabled','BehaviorMonitorEnabled')) {
    if (-not $flags[$required]) { throw 'Required Defender protection is not enabled; no execution authorized.' }
  }
  $detections = @(Get-MpThreatDetection -ErrorAction Stop | ForEach-Object {
    "$($_.DetectionID)|$($_.ThreatID)|$($_.LastThreatStatusChangeTime)|$($_.ThreatStatusID)"
  } | Sort-Object -Unique)
  @{ flags = $flags; detections = $detections }
}

function Start-ProtectedInstallerProof([string]$Installer, [string]$ExpectedSha256, [string]$EvidenceDir) {
  if ($env:GITHUB_ACTIONS -ne 'true' -or $env:BLOOMSTEP_DISPOSABLE_VM -ne 'true') {
    throw 'Protected installer execution requires explicitly authorized disposable CI, never the local host.'
  }
  $baseline = Get-InstallerProtectionSnapshot
  & "$PSScriptRoot\setup_defender_test_vm.ps1" -Mode ScanCandidate -Installer $Installer `
    -ExpectedSha256 $ExpectedSha256 -EvidenceDir (Join-Path $EvidenceDir 'defender-candidate-scan')
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Defender candidate preflight failed.' }
  if ((Get-FileHash -LiteralPath $Installer).Hash.ToLower() -ne $ExpectedSha256) {
    throw 'Protected candidate bytes changed after scan.'
  }
  $context = @{ baseline = $baseline; evidenceDir = $EvidenceDir; installerSha256 = $ExpectedSha256 }
  Assert-InstallerProtectionUnchanged $context
  return $context
}

function Assert-InstallerProtectionUnchanged([hashtable]$Context) {
  $receipt = [ordered]@{ kind = 'sanitized-defender-installer-proof'; installerSha256 = $Context.installerSha256;
    outcome = 'FAIL'; baselineProtection = $Context.baseline.flags; detectionDetailsWithheld = $true }
  try {
    $current = Get-InstallerProtectionSnapshot
    $receipt.currentProtection = $current.flags
    $receipt.baselineDetectionCount = $Context.baseline.detections.Count
    $receipt.currentDetectionCount = $current.detections.Count
    $changed = @($current.detections | Where-Object { $_ -notin $Context.baseline.detections })
    $receipt.newOrChangedDetectionCount = $changed.Count
    if ($changed.Count -ne 0) { throw 'New or changed Defender detection; stop and withhold installer acceptance.' }
    foreach ($name in $Context.baseline.flags.Keys) {
      if ($current.flags[$name] -ne $Context.baseline.flags[$name]) {
        throw 'Defender protection changed; stop and withhold installer acceptance.'
      }
    }
    $receipt.outcome = 'PASS protection unchanged; no new detections'
  } finally {
    $receipt | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Context.evidenceDir 'defender-proof-receipt.json') -Encoding utf8
  }
}
