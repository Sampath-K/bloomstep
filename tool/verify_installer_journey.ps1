param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$FixtureManifest,
  [Parameter(Mandatory=$true)][string]$EvidenceDir,
  [ValidateSet('checked-launch','unchecked-launch','silent','unattended','cancel','failure','elevated')]
  [string]$Mode = 'unchecked-launch'
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:BLOOMSTEP_ISOLATED_JOURNEY_FIXTURE -ne 'true' -or
    $env:BLOOMSTEP_DISPOSABLE_VM -ne 'true') {
  throw 'This proof runs only on an explicitly authorized disposable CI host with an inert fixture, never the local host.'
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
. "$PSScriptRoot\universal_integrity_contract.ps1"
$compiledFixture = Get-Content $FixtureManifest -Raw | ConvertFrom-Json
$hash = (Get-FileHash $Installer).Hash.ToLower()
if ($compiledFixture.kind -ne 'inert-journey-fixture-v1' -or
    $compiledFixture.fixtureAppId -ne 'A6690692-4D92-475A-9EAC-1AD867AB0635' -or
    $compiledFixture.payloadSource -ne 'tool/fixtures/installer_launch_probe.cs' -or
    $compiledFixture.sourceRevision -ne (git rev-parse HEAD) -or
    $compiledFixture.installerFile -ne [IO.Path]::GetFileName($Installer) -or
    $compiledFixture.installerSha256 -ne $hash -or
    -not ([IO.Path]::GetFileName($Installer) -eq 'Bloomstep-0.0.0-contract-windows-x64-setup.exe' -or
      ([IO.Path]::GetFileName($Installer) -eq 'Bloomstep-0.0.0-contract-windows-universal-setup.exe' -and
        $compiledFixture.fixtureArch -eq 'universal'))) {
  throw 'Only the exact hash-authorized compiled inert journey fixture may be installed by this proof.'
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Mode -ne 'elevated' -and $admin) { throw 'Normal launch proof must have an actual non-elevated token. No installer started.' }
if ($Mode -eq 'elevated' -and -not $admin) { throw 'Elevated no-launch branch needs an actual elevated CI token. No self-elevation.' }
if (-not [Environment]::UserInteractive) { throw 'An actual interactive disposable desktop is required.' }
& "$PSScriptRoot\verify_onboarding_wizard.ps1" -Installer $Installer -EvidenceDir $EvidenceDir -LoadHelpersOnly
if (-not [OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  throw 'Per-monitor physical capture coordinates unavailable.'
}
$target = Join-Path $EvidenceDir ('Bloomstep-Inert-Journey-' + [Guid]::NewGuid())
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
$protocol = 'Registry::HKEY_CURRENT_USER\Software\Classes\bloomstep\shell\open\command'
if ((Test-Path $target) -or (Test-Path $receipt) -or (Test-Path $protocol)) {
  throw 'Fixture proof requires absent target, protocol and receipt.'
}
$privateProof = Join-Path $target 'launch-proof-private.jsonl'
$options = "/SP- /NORESTART /DIR=`"$target`""
if ($Mode -eq 'silent') { $options += ' /VERYSILENT /SUPPRESSMSGBOXES' }
if ($Mode -eq 'unattended') { $options += ' /SUPPRESSMSGBOXES' }
if ($Mode -eq 'failure') { $options += ' /FORCEFIXTUREFAILURE' }
$requestedScales = @(100, 150, 200)
$states = [Collections.Generic.List[object]]::new()
$owned = [Collections.Generic.HashSet[int]]::new()
$journey = New-StandardWizardJourney
$report = [ordered]@{
  schemaVersion = 2; sourceRevision = $compiledFixture.sourceRevision; installerSha256 = $hash
  mode = $Mode; fixture = $true; customerData = $false; outcome = 'UNVERIFIED'
  payload = 'Inert launch-token/count probe, not Bloomstep app or a public release'
  proofAutomation = 'Explicit Install/Finish test-driver input; no Next or customer automatic behavior claim'
  requestedOsScales = $requestedScales; states = $states; journey = $journey
  tokenElevated = $admin; userInteractive = [Environment]::UserInteractive
  screenReaderAcceptance = 'UNKNOWN; captures are not Narrator acceptance'
}
$protection = Start-ProtectedInstallerProof $Installer $compiledFixture.installerSha256 $EvidenceDir
$setup = $null
try {
  $setup = Start-Process -FilePath $Installer -ArgumentList $options -PassThru
  [void]$setup.Handle
  [void]$owned.Add($setup.Id)
  $seen = [Collections.Generic.HashSet[string]]::new()
  $finished = $false
  $failureObserved = $false
  $deadline = (Get-Date).AddMinutes(2)
  while ((Get-Date) -lt $deadline) {
    $processes = Get-CimInstance Win32_Process
    for ($i = 0; $i -lt 4; $i++) {
      foreach ($process in $processes) {
        if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
      }
    }
    $active = @($owned | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    if ($setup.HasExited -and $active.Count -eq 0) { $finished = $true; break }
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$owner = 0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
      if (-not $owned.Contains([int]$owner)) { continue }
      $text = [OnboardingWizard]::Describe($window)
      $class = [OnboardingWizard]::ClassName($window)
      if ($class -eq 'TApplication' -and -not $text -and -not [OnboardingWizard]::HasVisibleChildren($window)) { continue }
      if ($seen.Add($text)) {
        $rectangle = [OnboardingWizard+Rect]::new()
        if (-not [OnboardingWizard]::GetWindowRect($window, [ref]$rectangle)) { throw 'Owned bounds unavailable.' }
        $width = $rectangle.Right - $rectangle.Left; $height = $rectangle.Bottom - $rectangle.Top
        $bitmap = [Drawing.Bitmap]::new($width, $height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
          $dc = $graphics.GetHdc()
          try { if (-not [OnboardingWizard]::PrintWindow($window, $dc, 2)) { throw 'Owned fixture capture failed.' } }
          finally { $graphics.ReleaseHdc($dc) }
          $image = "$Mode-$($states.Count).png"
          $bitmap.Save((Join-Path $EvidenceDir $image), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
        $states.Add(@{ image = $image; dpi = [OnboardingWizard]::GetDpiForWindow($window);
          width = $width; height = $height; screenshotSha256 = (Get-FileHash (Join-Path $EvidenceDir $image)).Hash.ToLower() })
      }
      if ($class -ne 'TWizardForm') {
        $caption = if ($Mode -eq 'cancel' -and $text -match 'Exit Setup|Setup is not complete|If you exit now') { 'Yes' }
          elseif ($Mode -eq 'failure' -and $text.Contains('Isolated fixture installation failure')) {
            $failureObserved = $true; 'OK'
          } else { throw 'Unexpected owned fixture dialog; no override.' }
        $button = [OnboardingWizard]::Find($window, $caption)
        if ($button -eq [IntPtr]::Zero) { throw 'Owned fixture modal control unavailable.' }
        [void][OnboardingWizard]::PostMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        continue
      }
      if ($Mode -eq 'failure' -and $text.Contains('Isolated fixture installation failure')) { $failureObserved = $true }
      if ($Mode -eq 'silent') { throw 'Silent fixture unexpectedly displayed a wizard.' }
      if ($text.Contains('Save optional local observations')) { throw 'Installer observation prompt must not exist.' }
      if ($Mode -eq 'cancel' -or $failureObserved) {
        $cancel = [OnboardingWizard]::Find($window, 'Cancel')
        if ($cancel -eq [IntPtr]::Zero) { throw 'Native Cancel unavailable.' }
        [void][OnboardingWizard]::PostMessage($cancel, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        continue
      }
      [void](Invoke-StandardWizardStep $window $journey ($Mode -eq 'checked-launch'))
    }
    Start-Sleep -Milliseconds 100
  }
  if (-not $finished) { throw "Inert $Mode fixture exceeded bounded deadline." }
  if ($Mode -eq 'cancel') { Assert-WelcomeCancelExit $setup.ExitCode }
  elseif ($Mode -eq 'failure') {
    if (-not $failureObserved -or $setup.ExitCode -eq 0) { throw 'Fixture failure was not observed with a failed exit.' }
  } else {
    if ($setup.ExitCode -ne 0) { throw 'Inert fixture did not exit successfully.' }
    if ($Mode -ne 'silent') {
      Assert-StandardWizardJourney $journey ($Mode -eq 'checked-launch') ($Mode -notin @('unattended','elevated'))
    }
  }
  Start-Sleep -Seconds 2
  $launches = if (Test-Path $privateProof) { @(Get-Content $privateProof | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
  $expected = if ($Mode -eq 'checked-launch') { 1 } else { 0 }
  if ($launches.Count -ne $expected) { throw "Launch count mismatch: expected $expected, got $($launches.Count)." }
  if ($expected -eq 1) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($launches[0].sid -ne $sid -or $launches[0].elevated) { throw 'Installing user or non-elevated launch token mismatch.' }
  }
  if (Test-Path $receipt) { throw 'Default-off fixture manufactured an observation.' }
  if ($Mode -in @('cancel','failure') -and (Test-Path "$target\bloomstep.exe")) {
    throw 'Canceled or failed fixture installed a payload.'
  }
  $actualScales = @($states | ForEach-Object { [int]($_.dpi * 100 / 96) } | Sort-Object -Unique)
  $report.launchCount = $launches.Count
  $report.installingUserMatches = if ($expected -eq 1) { $true } else { $null }
  $report.launchedElevated = if ($expected -eq 1) { $false } else { $null }
  $report.observationReceiptAbsent = $true
  $report.measuredOsScales = $actualScales
  $report.uncoveredOsScales = @($requestedScales | Where-Object { $_ -notin $actualScales })
  Assert-InstallerProtectionUnchanged $protection
  $report.outcome = 'PASS inert standard wizard branch only; genuine app acceptance withheld'
} catch {
  $report.outcome = 'FAIL'
  $report.errorType = $_.Exception.GetType().FullName
  $report.errorLine = $_.InvocationInfo.ScriptLineNumber
  throw
} finally {
  try {
    foreach ($id in $owned) { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id } }
    Assert-InstallerProtectionUnchanged $protection
    if (Test-Path (Join-Path $target 'unins000.exe')) {
      $uninstall = Start-Process (Join-Path $target 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru
      if (-not $uninstall.WaitForExit(30000)) { Stop-Process -Id $uninstall.Id; throw 'Fixture cleanup exceeded deadline.' }
      if ($uninstall.ExitCode -ne 0 -or (Test-Path $protocol)) { throw 'Fixture owned cleanup failed.' }
    }
    if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  } finally {
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceDir "$Mode.json") -Encoding utf8
    Assert-InstallerProtectionUnchanged $protection
  }
}
