param(
  [Parameter(Mandatory=$true)][string]$PackageDir,
  [Parameter(Mandatory=$true)][string]$EvidenceDir,
  [Parameter(Mandatory=$true)][ValidateSet('oneclick','zeroclick')][string]$Flow
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
  throw 'Actual visual proof is restricted to disposable CI; never local customer installation.'
}$manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
$installer = Join-Path $PackageDir $manifest.installerFile
$suffix = if ($Flow -eq 'zeroclick') { '-zeroclick' } else { '' }
if ($manifest.kind -ne 'bloomstep-offline-universal-v1' -or $manifest.source -ne (git rev-parse HEAD) -or
    $manifest.installFlow -ne $Flow -or
    $manifest.installerFile -ne "Bloomstep-$($manifest.version)-windows-universal$suffix-setup.exe" -or
    $manifest.installerSha256 -ne (Get-FileHash $installer).Hash.ToLower()) {
  throw 'Visual proof package source/flow/file/hash authority mismatch.'
}
$target = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
if ($Flow -eq 'oneclick') { $target = Join-Path $env:RUNNER_TEMP 'Bloomstep-progress-proof' }
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
$protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
foreach ($path in @($target, $receipt, $protocol)) {
  if (Test-Path $path) { throw 'Visual proof refuses existing customer/product state.' }
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $installer -EvidenceDir $EvidenceDir
. "$PSScriptRoot\installer_window_contract.ps1"
[void][OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Test-VisualWords([string]$Text) {
  foreach ($word in @('Anchor', 'Action', 'Celebrate')) {
    if ($Text -notmatch "(^| \| )$word( \| |$)") { return $false }
  }
  return $true
}
$welcomeFrames = [Collections.Generic.List[object]]::new()
$frames = [Collections.Generic.List[object]]::new()
$committed = $false
$welcomeAt = $null
$installStartedAt = $null
$trustedApplicationProxies = @{}
$report = [ordered]@{ kind = 'actual-compiled-install-visual-not-app-acceptance'; flow = $Flow;
  source = $manifest.source; installerFile = $manifest.installerFile; installerSha256 = $manifest.installerSha256;
  installed = $false; welcomeObserved = $false; welcomeFrames = $welcomeFrames; visualFrames = $frames;
  installClicks = 0; finishPageAbsent = $false; timerStopped = $false; outcome = 'running'; cleanupVerified = $false;
  visualIdentity = 'anchor-action-celebrate-garden';
  expectedArtworkSha256 = @{
    'welcome-steps.bmp' = (Get-FileHash (Join-Path $PSScriptRoot '..\packaging\assets\welcome-steps.bmp')).Hash.ToLower()
    'welcome-garden.bmp' = (Get-FileHash (Join-Path $PSScriptRoot '..\packaging\assets\welcome-garden.bmp')).Hash.ToLower()
  };
  applicationProxyClassification = 'Only empty, childless precommit TApplication handles sharing an observed owned wizard PID. All unexpected dialogs fail.';
  applicationProxies = [Collections.Generic.List[object]]::new();
  screenReaderAcceptance = 'UNKNOWN';
  automaticLaunch = 'UNVERIFIED' }
$log = Join-Path $EvidenceDir 'actual-install.log'
try {
  $arguments = "/SP- /NORESTART /SUPPRESSMSGBOXES /LOG=`"$log`""
  if ($Flow -eq 'oneclick') { $arguments += " /DIR=`"$target`"" }
  $setup = Start-CaptureProcess $installer $arguments 'install'
  $deadline = $captureClock.ElapsedMilliseconds + 120000
  while (-not $setup.HasExited -and $captureClock.ElapsedMilliseconds -lt $deadline) {
    Update-CaptureTree
    $windows = @(Get-CaptureWindows)
    $wizardOwners = @($windows | Where-Object { [OnboardingWizard]::ClassName($_) -eq 'TWizardForm' } |
      ForEach-Object {
        [uint32]$owner = 0
        [void][OnboardingWizard]::GetWindowThreadProcessId($_, [ref]$owner)
        $owner
      })
    if (-not $committed) {
      foreach ($window in $windows) {
        [uint32]$owner = 0
        [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
        if (Test-InnoApplicationProxy ([OnboardingWizard]::ClassName($window)) ([OnboardingWizard]::Describe($window)) `
            ([OnboardingWizard]::HasVisibleChildren($window)) $owner $wizardOwners) {
          $handle = $window.ToInt64()
          if (-not $trustedApplicationProxies.ContainsKey($handle)) {
            $trustedApplicationProxies[$handle] = $owner
            $report.applicationProxies.Add(@{ pid = $owner; class = 'TApplication';
              title = [OnboardingWizard]::GetWindowTitle($window); text = ''; hasVisibleChildren = $false })
            Save-CaptureStage 'recognized-empty-precommit-application-proxy'
          }
        }
      }
    }
    foreach ($window in $windows) {
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') {
        [uint32]$owner = 0
        [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
        if ($trustedApplicationProxies.ContainsKey($window.ToInt64()) -and
            $trustedApplicationProxies[$window.ToInt64()] -eq $owner -and
            (Test-InnoApplicationProxy ([OnboardingWizard]::ClassName($window)) ([OnboardingWizard]::Describe($window)) `
             ([OnboardingWizard]::HasVisibleChildren($window)) $owner $wizardOwners)) { continue }
        if ($committed -and [OnboardingWizard]::ClassName($window) -eq 'TApplication' -and
            -not [OnboardingWizard]::HasVisibleChildren($window) -and -not [OnboardingWizard]::Describe($window)) { continue }
        # /SUPPRESSMSGBOXES only applies to silent installs; this elevated host must see the exact Start-menu notice.
        if ($committed -and [OnboardingWizard]::ClassName($window) -eq '#32770' -and
            [OnboardingWizard]::Describe($window) -eq 'OK | Bloomstep is installed. Open Bloomstep from the Start menu as your normal Windows account.') {
          if (-not $report.elevatedHostNotice) {
            $report.elevatedHostNotice = Save-CaptureFrame $window 'actual-elevated-host-notice.png'
            Invoke-CaptureButton ([OnboardingWizard]::Find($window, 'OK')) 'elevated-host-notice-ok'
          }
          continue
        }
        Save-CaptureStage 'unexpected-install-dialog'
        throw 'Actual installer presented an unexpected owned dialog; no override.'
      }
      $text = [OnboardingWizard]::Describe($window)
      if ($text -match 'Optional local installation observations|Save optional local observations') {
        throw 'Installer observation prompt must not exist.'
      }
      if ($text.Contains('Bloomstep is ready') -or $text.Contains('Completing the') -or
          [OnboardingWizard]::Find($window, 'Finish') -ne [IntPtr]::Zero) {
        Save-CaptureFrame $window 'unexpected-finish.png' | Out-Null
        throw 'A Finish page must not exist; the app opens automatically after install.'
      }
      $words = Test-VisualWords $text
      $now = $captureClock.ElapsedMilliseconds
      if (-not $committed -and $Flow -eq 'oneclick') {
        if ($text.Contains('Select Destination Location')) {
          if ($null -eq $welcomeAt) { throw 'First actual page was not the Anchor/Action/Celebrate welcome.' }
          if ([OnboardingWizard]::Find($window, 'Install') -eq [IntPtr]::Zero -and
              [OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero) { continue }
          if ($text -match 'click Next|select Next') { throw 'Destination hint still instructs Next instead of Install.' }
          $install = [OnboardingWizard]::Find($window, 'Install')
          $browse = [OnboardingWizard]::Find($window, 'Browse...')
          if ($install -eq [IntPtr]::Zero -or $browse -eq [IntPtr]::Zero) { throw 'Native destination Install/Browse controls missing.' }
          $report.welcomeToDestinationMilliseconds = $now - $welcomeAt
          if ($report.welcomeToDestinationMilliseconds -lt 3500) { throw 'Welcome advanced before about 4 seconds.' }
          $report.destination = Save-CaptureFrame $window 'actual-destination.png'
          $report.destination.actualDpi = [OnboardingWizard]::GetDpiForWindow($window)
          Invoke-CaptureButton $install 'install-commit'
          $report.installClicks = 1
          $committed = $true
          $installStartedAt = $captureClock.ElapsedMilliseconds
          continue
        }
        if (-not $words) { throw 'First actual page was not the Anchor/Action/Celebrate welcome.' }
        if ([OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero -and $null -ne $welcomeAt -and
            ($now - $welcomeAt) -ge 3500) { continue }  # Inno shows the next page's buttons a moment before its surface.
        if ([OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero -or
            [OnboardingWizard]::Find($window, 'Cancel') -eq [IntPtr]::Zero) {
          throw 'Welcome must show only Cancel and advance on its own.'
        }
        if ($null -eq $welcomeAt) { $welcomeAt = $now; $report.welcomeObserved = $true }
        if ($welcomeFrames.Count -lt 6) {
          $frame = Save-CaptureFrame $window ("actual-welcome-{0:D2}.png" -f $welcomeFrames.Count)
          $frame.phase = 'welcome'
          $frame.elapsedMilliseconds = $captureClock.ElapsedMilliseconds - $welcomeAt
          $welcomeFrames.Add($frame)
        }
        continue
      }
      if ($text.Contains('Select Destination Location')) { throw 'Zero-click must not show a destination page.' }
      if ($text -match 'Setup Wizard|Click Next') {
        Save-CaptureFrame $window 'unexpected-generic-welcome.png' | Out-Null
        throw 'Zero-click showed the generic Inno welcome instead of the Bloomstep visual.'
      }
      if (-not $words) { continue }
      if (-not $committed -and -not $text.Contains('Installing')) {
        # Inno's mandatory pre-install page carries the same visual and advances on the first timer tick.
        if ($null -eq $report.zeroClickPreInstallFrame) {
          $report.zeroClickPreInstallFrame = Save-CaptureFrame $window 'actual-preinstall-visual.png'
          $report.zeroClickPreInstallFrame.elapsedMilliseconds = $now
        }
        continue
      }
      if (-not $committed) {
        $committed = $true
        $installStartedAt = $now
      }
      if ($frames.Count -lt 60) {
        $frame = Save-CaptureFrame $window ("actual-installing-{0:D4}.png" -f $frames.Count)
        $frame.phase = 'installing'
        $frame.elapsedMilliseconds = $captureClock.ElapsedMilliseconds - $installStartedAt
        $frames.Add($frame)
      }
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $setup.HasExited) {
    Save-CaptureStage 'install-ui-timeout'
    throw 'Actual install visual exceeded120s; see owned-stage-receipt.'
  }
  $report.installToExitMilliseconds = if ($null -ne $installStartedAt) { $captureClock.ElapsedMilliseconds - $installStartedAt } else { $null }
  Wait-CaptureTree 'install'
  if ($setup.ExitCode -ne 0) { throw 'Actual installer launcher exit was not0.' }
  if (@($captureOwned.Values | Where-Object { $_.ExitCode -ne 0 }).Count -ne 0) {
    throw 'Actual owned installer child did not exit0.'
  }
  if (-not $committed -or $frames.Count -eq 0) { throw 'Installing visual was never observed.' }
  if (Test-Path $receipt) { throw 'Installer observations must not exist.' }
  if (-not (Test-Path "$target\bloomstep.exe")) { throw 'Actual install did not create the payload at the expected path.' }
  $body = Get-Content $log -Raw
  $report.timerStopped = -not $body.Contains('Bloomstep visual timer disposal failed') -and
    $body.Contains('Bloomstep visual timer stopped.')
  if (-not $report.timerStopped) { throw 'Actual visual timer stop evidence missing.' }
  $report.staticPreference = $body.Contains('Bloomstep static visual')
  if ($Flow -eq 'oneclick') {
    $advance = [regex]::Match($body, 'Bloomstep welcome auto-advanced after (\d+) ms')
    if (-not $advance.Success -or [int]$advance.Groups[1].Value -lt 4000) { throw 'Welcome auto-advance log missing or early.' }
    $report.welcomeAutoAdvanceLoggedMilliseconds = [int]$advance.Groups[1].Value
  } else {
    $hold = [regex]::Match($body, 'Bloomstep zero-click visual held until (\d+) ms')
    if (-not $hold.Success -or [int]$hold.Groups[1].Value -lt 5000) { throw 'Zero-click visual hold log missing or short.' }
    $report.visualHoldMilliseconds = [int]$hold.Groups[1].Value
    $advance = [regex]::Match($body, 'Bloomstep welcome auto-advanced after (\d+) ms')
    if (-not $advance.Success -or [int]$advance.Groups[1].Value -gt 1000) { throw 'Zero-click pre-install visual did not advance on its own promptly.' }
    $report.zeroClickPreInstallAdvanceMilliseconds = [int]$advance.Groups[1].Value
  }
  if ($body.Contains('Bloomstep automatic launch started')) {
    throw 'Suppressed/elevated CI host must withhold automatic launch.'
  }
  if (-not $body.Contains('Bloomstep automatic launch withheld')) { throw 'Automatic launch decision not logged.' }
  if (@(Get-Process bloomstep -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($target) }).Count -ne 0) {
    throw 'An app process started on the suppressed/elevated CI host.'
  }
  $report.automaticLaunch = 'withheld on this elevated, /SUPPRESSMSGBOXES CI host by design; genuine non-elevated automatic launch UNVERIFIED'
  $report.finishPageAbsent = $true
  $report.dpiObserved = @(@($welcomeFrames) + @($frames) | ForEach-Object { $_.dpi } | Sort-Object -Unique)
  $report.uncoveredDpi = @(96, 144 | Where-Object { $_ -notin $report.dpiObserved })
  $report.motionAcceptance = if ($report.staticPreference) {
    'Static preference branch: art held still; timing still applied. Not motion evidence.'
  } else { 'Motion preference on: subtle drift only; frames are the evidence, not source code.' }
  $report.installed = $true
  $report.outcome = "actual-$Flow-install-without-Finish-observed-not-app-acceptance"} catch {
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
        throw 'Actual visual proof owned uninstall failed.'
      }
    }
    $report.cleanupVerified = -not ((Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol))
  } finally {
    try { Stop-CaptureTree }
    finally {
      Save-CaptureStage 'finally-complete'
      if (-not $report.cleanupVerified) { $report.outcome += '; FAIL: owned cleanup incomplete' }
      $report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'actual-progress-proof.json') -Encoding utf8
    }
  }
}
