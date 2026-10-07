param(
  [Parameter(Mandatory=$true)][string]$PackageDir,
  [Parameter(Mandatory=$true)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
  throw 'Actual motion proof is restricted to disposable CI; never local customer installation.'
}
$manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
$installer = Join-Path $PackageDir $manifest.installerFile
if ($manifest.kind -ne 'bloomstep-offline-universal-v1' -or $manifest.source -ne (git rev-parse HEAD) -or
    $manifest.installerFile -ne "Bloomstep-$($manifest.version)-windows-universal-setup.exe" -or
    $manifest.installerSha256 -ne (Get-FileHash $installer).Hash.ToLower()) {
  throw 'Motion proof package source/file/hash authority mismatch.'
}
$target = Join-Path $env:RUNNER_TEMP 'Bloomstep-progress-proof'
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
$protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
foreach ($path in @($target, $receipt, $protocol)) {
  if (Test-Path $path) { throw 'Motion proof refuses existing customer/product state.' }
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $installer -EvidenceDir $EvidenceDir
[void][OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))
$frames = [Collections.Generic.List[object]]::new()
$finishObserved = $false
$committed = $false
$installStartedAt = $null
$report = [ordered]@{ kind = 'actual-compiled-install-progress-not-app-acceptance';
  source = $manifest.source; installerSha256 = $manifest.installerSha256; installed = $false;
  sceneFrames = $frames; finishObserved = $false; timerStopped = $false; outcome = 'running';
  screenReaderAcceptance = 'UNKNOWN'; genuineFinishLaunch = 'UNVERIFIED; deliberately suppressed in this installation-only proof' }
$log = Join-Path $EvidenceDir 'actual-install.log'
try {
  $setup = Start-CaptureProcess $installer "/SP- /NORESTART /SUPPRESSMSGBOXES /DIR=`"$target`" /LOG=`"$log`"" 'install'
  $deadline = $captureClock.ElapsedMilliseconds + 120000
  while (-not $finishObserved -and $captureClock.ElapsedMilliseconds -lt $deadline) {
    Update-CaptureTree
    foreach ($window in Get-CaptureWindows) {
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') {
        Save-CaptureStage 'unexpected-install-dialog'
        throw 'Actual installer presented an unexpected owned dialog; no override.'
      }
      $text = [OnboardingWizard]::Describe($window)
      if ($text -match 'Optional local installation observations|Save optional local observations') {
        throw 'Installer observation prompt must not exist.'
      }
      if (-not $committed) {
        if (-not $text.Contains('Select Destination Location')) { throw 'First actual page was not destination.' }
        $install = [OnboardingWizard]::Find($window, 'Install')
        $browse = [OnboardingWizard]::Find($window, 'Browse...')
        if ($install -eq [IntPtr]::Zero -or $browse -eq [IntPtr]::Zero) { throw 'Native destination Install/Browse controls missing.' }
        $report.destination = Save-CaptureFrame $window 'actual-destination.png'
        $report.destination.actualDpi = [OnboardingWizard]::GetDpiForWindow($window)
        Invoke-CaptureButton $install 'install-commit'
        $committed = $true
        $installStartedAt = $captureClock.ElapsedMilliseconds
        continue
      }
      $finish = [OnboardingWizard]::Find($window, 'Finish')
      if ($finish -ne [IntPtr]::Zero) {
        if (-not $text.Contains('Bloomstep is ready') -or -not $text.Contains('Open Bloomstep to create your first tiny habit')) {
          throw 'Actual Finish copy mismatch.'
        }
        $report.finish = Save-CaptureFrame $window 'actual-finish.png'
        $report.commitToFinishMilliseconds = $captureClock.ElapsedMilliseconds - $installStartedAt
        $finishObserved = $true
        Invoke-CaptureButton $finish 'finish-with-launch-suppressed'
        break
      }
      if ($text.Contains('A little is enough') -or $text.Contains('After a familiar routine') -or $text.Contains('Your practice grows a garden')) {
        $frame = Save-CaptureFrame $window ("actual-progress-{0:D4}.png" -f $frames.Count)
        $frame.scene = if ($text.Contains('After a familiar routine')) { 1 }
          elseif ($text.Contains('Your practice grows a garden')) { 2 } else { 0 }
        $frame.elapsedMilliseconds = $captureClock.ElapsedMilliseconds - $installStartedAt
        $frames.Add($frame)
      }
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $finishObserved) {
    Save-CaptureStage 'install-ui-timeout'
    throw 'Actual destination/install/Finish exceeded120s; see owned-stage-receipt.'
  }
  Wait-CaptureTree 'install'
  if ($setup.ExitCode -ne 0) { throw 'Actual installer launcher exit was not0.' }
  if (Test-Path $receipt) { throw 'Installer observations must not exist.' }
  if (-not (Test-Path "$target\bloomstep.exe")) { throw 'Actual progress install did not create the payload.' }
  $body = Get-Content $log -Raw
  $report.timerStopped = $body.Contains('Bloomstep install presentation stopped.') -or
    $body.Contains('Bloomstep static install presentation') -or $body.Contains('progress timer could not be created')
  if (-not $report.timerStopped) { throw 'Actual motion timer stop/static evidence missing.' }
  $report.staticPreference = $body.Contains('Bloomstep static install presentation')
  $report.observedScenes = @($frames.scene | Sort-Object -Unique)
  $report.dpiObserved = @($report.destination.dpi, $report.finish.dpi)
  $report.uncoveredDpi = @(96, 144 | Where-Object { $_ -notin $report.dpiObserved })
  $report.motionAcceptance = 'Actual compiled timed frames; short installation is not delayed. Three-scene/high-DPI/reduced-motion coverage remains pending unless actually observed.'
  $report.finishObserved = $true
  $report.installed = $true
  $report.outcome = 'installation-and-Finish-observed-not-app-acceptance'
} catch {
  $report.outcome = 'FAIL; actual installation/motion evidence incomplete'
  $report.failureType = $_.Exception.GetType().FullName
  $report.failureLine = $_.InvocationInfo.ScriptLineNumber
  Save-CaptureStage 'install-proof-failed'
  throw
} finally {
  try {
    Stop-CaptureTree
    if (Test-Path "$target\unins000.exe") {
      $uninstall = Start-CaptureProcess "$target\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' 'uninstall'
      Wait-CaptureTree 'uninstall'
      if ($uninstall.ExitCode -ne 0 -or (Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol)) {
        throw 'Actual motion proof owned uninstall failed.'
      }
    }
  } finally {
    try { Stop-CaptureTree }
    finally {
      Save-CaptureStage 'finally-complete'
      $report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'actual-progress-proof.json') -Encoding utf8
    }
  }
}
