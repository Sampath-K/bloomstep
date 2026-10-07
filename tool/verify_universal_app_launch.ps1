param(
  [Parameter(Mandatory=$true)][string]$PackageDir,
  [Parameter(Mandatory=$true)][ValidateSet('x64','arm64')][string]$ExpectedArch,
  [Parameter(Mandatory=$true)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\universal_integrity_contract.ps1"
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:BLOOMSTEP_UNIVERSAL_APP_PROOF -ne 'true' -or -not $env:RUNNER_TEMP) {
  throw 'Genuine universal app launch proof is restricted to explicitly authorized disposable CI.'
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$report = [ordered]@{
  kind = 'genuine-universal-app-launch-not-inert-or-customer-acceptance'
  source = (git rev-parse HEAD); architecture = $ExpectedArch; outcome = 'UNVERIFIED'
  ordinarySignInAndFullJourney = 'PENDING owner trial'; keyboardNarrator = 'UNKNOWN'
  modes = [Collections.Generic.List[object]]::new()
}
$setup = $null
$owned = [Collections.Generic.HashSet[int]]::new()
$apps = [Collections.Generic.HashSet[int]]::new()
$target = $null
try {
  $manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
  $installer = Join-Path $PackageDir $manifest.installerFile
  if ($manifest.kind -ne 'bloomstep-offline-universal-v1' -or $manifest.source -ne $report.source -or
      $manifest.installerFile -ne "Bloomstep-$($manifest.version)-windows-universal-setup.exe" -or
      $manifest.installerSha256 -ne (Get-FileHash $installer).Hash.ToLower() -or
      -not (Test-BloomstepInnoProductName (Get-Item $installer).VersionInfo.ProductName)) {
    throw 'Genuine universal source/name/hash/product authority mismatch.'
  }
  $payloadPath = Join-Path $PackageDir "payload-manifest-$ExpectedArch.json"
  $payload = Get-Content $payloadPath -Raw | ConvertFrom-Json
  if ($manifest.payloadManifests.$ExpectedArch -ne (Get-FileHash $payloadPath).Hash.ToLower() -or
      $payload.source -ne $report.source -or $payload.version -ne $manifest.version -or $payload.arch -ne $ExpectedArch) {
    throw 'Genuine selected payload manifest authority mismatch.'
  }
  $report.installerSha256 = $manifest.installerSha256
  Add-Type -Path "$PSScriptRoot\process_token_probe.cs"
  $report.workerTokenElevated = [ProcessTokenProbe]::Elevated($PID)
  $report.workerInteractive = [Environment]::UserInteractive
  if ($report.workerTokenElevated -or -not $report.workerInteractive) {
    throw 'Actual universal app launch needs a clean non-elevated interactive installing user. No installer started; no guard bypass.'
  }
  $installingSid = [ProcessTokenProbe]::Sid($PID)
  if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower() -ne $ExpectedArch) {
    throw 'Genuine universal app proof is not on the expected native OS.'
  }
  & "$PSScriptRoot\verify_onboarding_wizard.ps1" -Installer $installer -EvidenceDir $EvidenceDir -LoadHelpersOnly
  $measurement = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
  $protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
  if ((Test-Path $measurement) -or (Test-Path $protocol) -or (Get-Process -Name bloomstep -ErrorAction SilentlyContinue)) {
    throw 'Genuine proof refuses pre-existing product state or processes.'
  }
  foreach ($mode in @('checked-launch','unchecked-launch')) {
    $target = Join-Path $env:RUNNER_TEMP "Bloomstep-genuine-universal-$mode"
    if (Test-Path $target) { throw 'Genuine proof refuses an existing install target.' }
    $owned.Clear(); $apps.Clear()
    $seen = [Collections.Generic.HashSet[string]]::new()
    $setup = Start-Process $installer -ArgumentList "/SP- /NORESTART /DIR=`"$target`"" -PassThru
    [void]$owned.Add($setup.Id)
    $finished = $false
    $wizardProcess = $null
    $deadline = (Get-Date).AddMinutes(3)
    while (-not $finished -and (Get-Date) -lt $deadline) {
      $processes = Get-CimInstance Win32_Process
      for ($i=0;$i -lt 5;$i++) {
        foreach ($process in $processes) {
          if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
        }
      }
      foreach ($window in [OnboardingWizard]::Windows()) {
        [uint32]$owner = 0
        [void][OnboardingWizard]::GetWindowThreadProcessId($window,[ref]$owner)
        if (-not $owned.Contains([int]$owner)) { continue }
        $text = [OnboardingWizard]::Describe($window)
        if (-not $seen.Add($text)) { continue }
        if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') { throw 'Unexpected owned genuine installer dialog; no automatic override.' }
        $observations = [OnboardingWizard]::Find($window,'Save optional local observations (unchecked by default)')
        if ($observations -ne [IntPtr]::Zero -and [OnboardingWizard]::SendMessage($observations,0x00F0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32() -ne 0) {
          throw 'Genuine optional observations must remain unchecked.'
        }
        $finish = [OnboardingWizard]::Find($window,'Finish')
        if ($finish -ne [IntPtr]::Zero) {
          $wizardProcess = Get-Process -Id $owner
          [void]$wizardProcess.Handle
          foreach ($file in $payload.files) {
            if ((Get-FileHash (Join-Path $target $file.path)).Hash.ToLower() -ne $file.sha256) { throw 'Genuine selected payload hash changed before Finish.' }
          }
          $root = [Windows.Automation.AutomationElement]::FromHandle($window)
          $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,'Launch Bloomstep and plant your first habit')
          $launch = $root.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
          if ($null -eq $launch) { throw 'Actual genuine Finish launch checkbox unavailable.' }
          $toggle = $launch.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
          if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::On) { throw 'Actual launch choice is not default checked.' }
          if ($mode -eq 'unchecked-launch') {
            $toggle.Toggle()
            if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::Off) { throw 'Actual launch choice did not become unchecked.' }
          }
          if (-not [OnboardingWizard]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) {
            throw 'Owned genuine Finish dispatch failed.'
          }
          $finished = $true
          break
        }
        $next = [OnboardingWizard]::Find($window,'Next >')
        if ($next -eq [IntPtr]::Zero) { $next = [OnboardingWizard]::Find($window,'Next') }
        if ($next -eq [IntPtr]::Zero) { $next = [OnboardingWizard]::Find($window,'Install') }
        if ($next -ne [IntPtr]::Zero -and -not [OnboardingWizard]::PostMessage($next,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) {
          throw 'Owned genuine Next/Install dispatch failed.'
        }
      }
      Start-Sleep -Milliseconds 200
    }
    if (-not $finished) { throw 'Genuine interactive journey exceeded bounded deadline.' }
    if (-not $wizardProcess -or -not $wizardProcess.WaitForExit(30000) -or -not $setup.WaitForExit(30000)) {
      throw 'Actual genuine wizard/launcher did not exit after Finish within the bounded deadline.'
    }
    $wizardExitCode = $wizardProcess.ExitCode
    $launcherExitCode = $setup.ExitCode
    $observeUntil = (Get-Date).AddSeconds(10)
    do {
      foreach ($app in @(Get-Process -Name bloomstep -ErrorAction SilentlyContinue)) {
        if ($app.Path -ne "$target\bloomstep.exe") { throw 'Unexpected genuine app process outside the exact owned target.' }
        [void]$apps.Add($app.Id)
        if ([ProcessTokenProbe]::Sid($app.Id) -ne $installingSid -or [ProcessTokenProbe]::Elevated($app.Id)) {
          throw 'Actual genuine app installing-user or non-elevated token mismatch.'
        }
      }
      Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $observeUntil)
    $expectedCount = if ($mode -eq 'checked-launch') {1} else {0}
    $sameExactTargetAppAlive = $false
    $ownedAppWindowVisible = $false
    if ($apps.Count -eq 1) {
      $app = Get-Process -Id (@($apps)[0])
      $sameExactTargetAppAlive = -not $app.HasExited -and $app.Path -eq "$target\bloomstep.exe"
      if ([ProcessTokenProbe]::Sid($app.Id) -ne $installingSid -or [ProcessTokenProbe]::Elevated($app.Id)) {
        throw 'Actual surviving app installing-user or token elevation changed.'
      }
      foreach ($window in [OnboardingWizard]::Windows()) {
        [uint32]$windowOwner = 0
        [void][OnboardingWizard]::GetWindowThreadProcessId($window,[ref]$windowOwner)
        if ($windowOwner -eq $app.Id) { $ownedAppWindowVisible = $true }
      }
    }
    Assert-GenuineLaunchOutcome $mode $wizardExitCode $launcherExitCode $apps.Count $sameExactTargetAppAlive $ownedAppWindowVisible
    if (Test-Path $measurement) { throw 'Actual genuine default-off receipt mismatch.' }
    $report.modes.Add(@{ mode=$mode; launchCount=$apps.Count; wizardExitCode=$wizardExitCode; launcherExitCode=$launcherExitCode;
      sameExactTargetAppAlive=$sameExactTargetAppAlive; ownedAppWindowVisible=$ownedAppWindowVisible;
      installingUserMatches=if($expectedCount -eq 1){$true}else{$null}; nonElevated=if($expectedCount -eq 1){$true}else{$null};
      observationReceiptAbsent=$true; observationSeconds=10 })
    foreach ($id in $apps) { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id } }
    $uninstall = Start-Process "$target\unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
    if ($uninstall.ExitCode -ne 0 -or (Test-Path "$target\bloomstep.exe") -or (Test-Path $protocol)) { throw 'Genuine owned uninstall failed.' }
    $target = $null
  }
  $report.outcome = 'PASS actual checked/unchecked genuine app launch only'
} catch {
  $report.failure = 'Blocked or failed; see explicit job exception. No launch acceptance inferred.'
  throw
} finally {
  foreach ($id in @($owned) + @($apps)) { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id -Force } }
  if ($target -and (Test-Path "$target\unins000.exe")) {
    Start-Process "$target\unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
  }
  $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $EvidenceDir 'genuine-universal-app-launch-receipt.json') -Encoding utf8
}
