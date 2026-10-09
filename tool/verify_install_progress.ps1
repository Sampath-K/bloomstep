param(
  [Parameter(Mandatory=$true)][string]$PackageDir,
  [Parameter(Mandatory=$true)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:BLOOMSTEP_DISPOSABLE_VM -ne 'true') {
  throw 'Actual visual proof is restricted to explicitly authorized disposable CI; never local installation.'
}
$manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
$installer = Join-Path $PackageDir $manifest.installerFile
if ($manifest.kind -ne 'bloomstep-offline-universal-v1' -or $manifest.source -ne (git rev-parse HEAD) -or
    $manifest.installerFile -ne "Bloomstep-$($manifest.version)-windows-universal-setup.exe" -or
    $manifest.installerSha256 -ne (Get-FileHash $installer).Hash.ToLower()) {
  throw 'Visual proof package source/file/hash authority mismatch.'
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$target = Join-Path $EvidenceDir 'Bloomstep-progress-proof'
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
$protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
foreach ($path in @($target, $receipt, $protocol)) {
  if (Test-Path $path) { throw 'Visual proof refuses existing customer/product state.' }
}
. "$PSScriptRoot\universal_integrity_contract.ps1"
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $installer -EvidenceDir $EvidenceDir
. "$PSScriptRoot\installer_window_contract.ps1"
if (-not [OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  throw 'Per-monitor physical capture coordinates unavailable.'
}
$journey = New-StandardWizardJourney
$frames = [Collections.Generic.List[object]]::new()
$trustedApplicationProxies = @{}
$report = [ordered]@{
  kind = 'actual-compiled-standard-install-visual-not-app-acceptance'
  source = $manifest.source; installerFile = $manifest.installerFile; installerSha256 = $manifest.installerSha256
  proofAutomation = 'Explicit disposable test-driver Install/Finish; no Next or customer automatic behavior'
  installed = $false; journey = $journey; visualFrames = $frames; outcome = 'UNVERIFIED'; cleanupVerified = $false
  staticArtwork = $true; motionAcceptance = 'Static artwork only. Not motion evidence.'
  expectedArtworkSha256 = @{
    'welcome-steps.bmp' = (Get-FileHash (Join-Path $PSScriptRoot '..\packaging\assets\welcome-steps.bmp')).Hash.ToLower()
    'welcome-garden.bmp' = (Get-FileHash (Join-Path $PSScriptRoot '..\packaging\assets\welcome-garden.bmp')).Hash.ToLower()
  }
  screenReaderAcceptance = 'UNKNOWN'; launchChoice = 'withheld by /SUPPRESSMSGBOXES'
}
$log = Join-Path $EvidenceDir 'actual-install.log'
$protection = Start-ProtectedInstallerProof $installer $manifest.installerSha256 $EvidenceDir
try {
  $setup = Start-CaptureProcess $installer "/SP- /NORESTART /SUPPRESSMSGBOXES /DIR=`"$target`" /LOG=`"$log`"" 'install'
  $deadline = $captureClock.ElapsedMilliseconds + 120000
  while ($captureClock.ElapsedMilliseconds -lt $deadline) {
    Update-CaptureTree
    if (@($captureOwned.Values | Where-Object { -not $_.HasExited }).Count -eq 0) { break }
    $windows = @(Get-CaptureWindows)
    $wizardOwners = @($windows | Where-Object { [OnboardingWizard]::ClassName($_) -eq 'TWizardForm' } | ForEach-Object {
      [uint32]$owner = 0; [void][OnboardingWizard]::GetWindowThreadProcessId($_, [ref]$owner); $owner
    })
    foreach ($window in $windows) {
      [uint32]$owner = 0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') {
        if (Test-InnoApplicationProxy ([OnboardingWizard]::ClassName($window)) ([OnboardingWizard]::Describe($window)) `
            ([OnboardingWizard]::HasVisibleChildren($window)) $owner $wizardOwners) {
          $trustedApplicationProxies[$window.ToInt64()] = $owner
          continue
        }
        Save-CaptureStage 'unexpected-install-dialog'
        throw 'Actual installer presented an unexpected owned dialog; no override.'
      }
      $text = [OnboardingWizard]::Describe($window)
      if ($text -match 'Optional local installation observations|Save optional local observations') {
        throw 'Installer observation prompt must not exist.'
      }
      $stage = Get-StandardWizardStage $window
      if (-not $stage) { throw 'Unknown native wizard stage.' }
      if (-not $journey.stages.Contains($stage)) {
        $frame = Save-CaptureFrame $window "actual-$stage.png"
        $frame.phase = $stage
        $frame.actualDpi = [OnboardingWizard]::GetDpiForWindow($window)
        $frame.elapsedMilliseconds = $captureClock.ElapsedMilliseconds
        $frames.Add($frame)
      }
      [void](Invoke-StandardWizardStep $window $journey)
    }
    Start-Sleep -Milliseconds 100
  }
  Wait-CaptureTree 'install' 10
  if ($setup.ExitCode -ne 0 -or @($captureOwned.Values | Where-Object { $_.ExitCode -ne 0 }).Count -ne 0) {
    throw 'Actual installer launcher or owned child did not exit0.'
  }
  Assert-StandardWizardJourney $journey $false $false
  if (Test-Path $receipt) { throw 'Installer observations must not exist.' }
  if (-not (Test-Path "$target\bloomstep.exe")) { throw 'Actual install payload missing at expected path.' }
  if (@(Get-Process bloomstep -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq "$target\bloomstep.exe" }).Count -ne 0) {
    throw 'An app process started despite suppressed launch.'
  }
  $report.observationReceiptAbsent = $true
  $report.dpiObserved = @($frames | ForEach-Object { $_.dpi } | Sort-Object -Unique)
  $report.uncoveredDpi = @(96, 144, 192 | Where-Object { $_ -notin $report.dpiObserved })
  $report.installed = $true
  Assert-InstallerProtectionUnchanged $protection
  $report.outcome = 'PASS actual standard wizard observed; app and Narrator acceptance withheld'
} catch {
  $report.outcome = 'FAIL; actual installation evidence incomplete'
  $report.failureType = $_.Exception.GetType().FullName
  $report.failureLine = $_.InvocationInfo.ScriptLineNumber
  Save-CaptureStage 'install-proof-failed'
  throw
} finally {
  try {
    Stop-CaptureTree
    Assert-InstallerProtectionUnchanged $protection
    if (Test-Path "$target\unins000.exe") {
      $uninstall = Start-CaptureProcess "$target\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' 'uninstall'
      Wait-CaptureTree 'uninstall'
      if ($uninstall.ExitCode -ne 0 -or (Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol)) {
        throw 'Actual visual proof owned uninstall failed.'
      }
    }
    $report.cleanupVerified = -not ((Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol))
    if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  } finally {
    try { Stop-CaptureTree }
    finally {
      Save-CaptureStage 'finally-complete'
      $report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'actual-progress-proof.json') -Encoding utf8
      Assert-InstallerProtectionUnchanged $protection
    }
  }
}
