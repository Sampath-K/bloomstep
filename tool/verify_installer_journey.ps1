param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$FixtureManifest,
  [Parameter(Mandatory=$true)][string]$EvidenceDir,
  [ValidateSet('checked-launch','unchecked-launch','silent','unattended','cancel','failure','elevated')]
  [string]$Mode = 'checked-launch',
  [switch]$Worker
)
$ErrorActionPreference = 'Stop'
if ($env:BLOOMSTEP_ISOLATED_JOURNEY_FIXTURE -ne 'true' -and -not $Worker) {
  throw 'This proof runs only on a disposable CI host with an inert fixture, never a customer installer.'
}
$requestedScales = @(100, 150, 200)
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$compiledFixture = Get-Content $FixtureManifest -Raw | ConvertFrom-Json
if ($compiledFixture.kind -ne 'inert-journey-fixture-v1' -or
    $compiledFixture.fixtureAppId -ne 'A6690692-4D92-475A-9EAC-1AD867AB0635' -or
    $compiledFixture.payloadSource -ne 'tool/fixtures/installer_launch_probe.cs' -or
    $compiledFixture.installerFile -ne [IO.Path]::GetFileName($Installer) -or
    $compiledFixture.installerSha256 -ne (Get-FileHash $Installer).Hash.ToLower() -or
    [IO.Path]::GetFileName($Installer) -ne 'Bloomstep-0.0.0-contract-windows-x64-setup.exe') {
  throw 'Only the exact hash-authorized compiled inert journey fixture may be installed by this proof.'
}
$authority = Join-Path $EvidenceDir 'fixture-authority.json'
if (-not $Worker) {
  @{ sourceRevision = $compiledFixture.sourceRevision; installerSha256 = (Get-FileHash $Installer).Hash.ToLower() } |
    ConvertTo-Json | Set-Content $authority -Encoding utf8
}
$authorization = Get-Content $authority -Raw | ConvertFrom-Json
if ($authorization.installerSha256 -ne (Get-FileHash $Installer).Hash.ToLower()) { throw 'Fixture hash authorization changed.' }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin -and $Mode -ne 'elevated' -and -not $Worker) {
  # A supported limited interactive task tests the actual installing-user token.
  $taskName = 'Bloomstep-Journey-Proof-' + [Guid]::NewGuid().ToString()
  $arguments = "-NoProfile -File `"$PSCommandPath`" -Installer `"$Installer`" -FixtureManifest `"$FixtureManifest`" -EvidenceDir `"$EvidenceDir`" -Mode $Mode -Worker"
  $action = New-ScheduledTaskAction -Execute (Get-Process -Id $PID).Path -Argument $arguments
  $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
  try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal | Out-Null
    $startedAt = Get-Date
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddMinutes(3)
    do {
      Start-Sleep -Seconds 1
      $info = Get-ScheduledTaskInfo -TaskName $taskName
    } while ((-not (Test-Path (Join-Path $EvidenceDir "$Mode.json"))) -and
      ($info.LastRunTime -lt $startedAt -or $info.LastTaskResult -eq 267009) -and (Get-Date) -lt $deadline)
    $result = Join-Path $EvidenceDir "$Mode.json"
    if (-not (Test-Path $result)) {
      throw "Limited interactive task produced no $Mode evidence; desktop/token availability is not established. Task result: $($info.LastTaskResult)"
    }
    return
  } finally { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
}
if ($Mode -ne 'elevated' -and $admin) { throw 'Normal launch proof must have an actual non-elevated token.' }
if ($Mode -eq 'elevated' -and -not $admin) { throw 'Elevated no-launch branch needs an actual elevated CI token.' }
& "$PSScriptRoot\verify_onboarding_wizard.ps1" -Installer $Installer -EvidenceDir $EvidenceDir -LoadHelpersOnly
if (-not [OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  throw 'Per-monitor physical capture coordinates unavailable.'
}
$target = Join-Path $env:TEMP ('Bloomstep-Inert-Journey-' + [Guid]::NewGuid())
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
if ((Test-Path $target) -or (Test-Path $receipt)) { throw 'Fixture proof requires absent target and receipt.' }
$privateProof = Join-Path $target 'launch-proof-private.jsonl'
$options = "/SP- /NORESTART /DIR=`"$target`""
if ($Mode -eq 'silent') { $options += ' /VERYSILENT /SUPPRESSMSGBOXES' }
if ($Mode -eq 'unattended') { $options += ' /SUPPRESSMSGBOXES' }
if ($Mode -eq 'failure') { $options += ' /FORCEFIXTUREFAILURE' }
$setup = Start-Process -FilePath $Installer -ArgumentList $options -PassThru
$owned = [Collections.Generic.HashSet[int]]::new()
[void]$owned.Add($setup.Id)
$states = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new()
$finished = $Mode -eq 'silent'
$checked = $null
$deadline = (Get-Date).AddMinutes(2)
$shell = New-Object -ComObject WScript.Shell
try {
  if ($Mode -eq 'silent') {
    if (-not $setup.WaitForExit(60000) -or $setup.ExitCode -ne 0) { throw 'Inert silent fixture did not complete.' }
  }
  while (-not $finished -and (Get-Date) -lt $deadline) {
    $processes = Get-CimInstance Win32_Process
    for ($i = 0; $i -lt 4; $i++) {
      foreach ($process in $processes) {
        if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
      }
    }
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$owner = 0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
      if (-not $owned.Contains([int]$owner)) { continue }
      $text = [OnboardingWizard]::Describe($window)
      if (-not $seen.Add($text)) { continue }
      $rectangle = New-Object OnboardingWizard+Rect
      if (-not [OnboardingWizard]::GetWindowRect($window, [ref]$rectangle)) { throw 'Owned bounds unavailable.' }
      $width = $rectangle.Right - $rectangle.Left
      $height = $rectangle.Bottom - $rectangle.Top
      $bitmap = [Drawing.Bitmap]::new($width, $height)
      $graphics = [Drawing.Graphics]::FromImage($bitmap)
      $dc = $graphics.GetHdc()
      try {
        if (-not [OnboardingWizard]::PrintWindow($window, $dc, 2)) { throw 'Owned fixture capture failed.' }
      } finally { $graphics.ReleaseHdc($dc) }
      $image = "$Mode-$($states.Count).png"
      try { $bitmap.Save((Join-Path $EvidenceDir $image), [Drawing.Imaging.ImageFormat]::Png) }
      finally { $graphics.Dispose(); $bitmap.Dispose() }
      $states.Add(@{ caption = $text; image = $image; dpi = [OnboardingWizard]::GetDpiForWindow($window);
        width = $width; height = $height; screenshotSha256 = (Get-FileHash (Join-Path $EvidenceDir $image)).Hash.ToLower() })
      if ($Mode -eq 'failure' -and $text.Contains('Isolated fixture installation failure')) {
        $finished = $true
        break
      }
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') {
        if ($Mode -eq 'failure' -and $text.Contains('Isolated fixture installation failure')) {
          $ok = [OnboardingWizard]::Find($window, 'OK')
          if ($ok -ne [IntPtr]::Zero) { [void][OnboardingWizard]::SendMessage($ok, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
          $finished = $true
          break
        }
        throw "Unexpected owned dialog: $text"
      }
      $checkbox = [OnboardingWizard]::Find($window, 'Save optional local observations (unchecked by default)')
      if ($checkbox -ne [IntPtr]::Zero -and
          [OnboardingWizard]::SendMessage($checkbox, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -ne 0) {
        throw 'Observations must stay unchecked.'
      }
      if ($Mode -eq 'cancel') {
        $cancel = [OnboardingWizard]::Find($window, 'Cancel')
        if ($cancel -eq [IntPtr]::Zero) { throw 'Native Cancel unavailable.' }
        [void][OnboardingWizard]::SendMessage($cancel, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 200
        foreach ($confirmation in [OnboardingWizard]::Windows()) {
          [uint32]$confirmationOwner = 0
          [void][OnboardingWizard]::GetWindowThreadProcessId($confirmation, [ref]$confirmationOwner)
          if (-not $owned.Contains([int]$confirmationOwner)) { continue }
          $yes = [OnboardingWizard]::Find($confirmation, 'Yes')
          if ($yes -ne [IntPtr]::Zero) { [void][OnboardingWizard]::SendMessage($yes, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
        }
        $finished = $true
        break
      }
      $finish = [OnboardingWizard]::Find($window, 'Finish')
      if ($finish -ne [IntPtr]::Zero) {
        $root = [Windows.Automation.AutomationElement]::FromHandle($window)
        $condition = [Windows.Automation.PropertyCondition]::new(
          [Windows.Automation.AutomationElement]::NameProperty, 'Launch Bloomstep and plant your first habit')
        $launch = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
        if ($Mode -in @('elevated','unattended')) {
          if ($null -ne $launch) { throw 'Elevated/unattended installer offered a launch checkbox.' }
        } else {
          if ($null -eq $launch) { throw 'Launch choice was not visibly available.' }
          $pattern = $launch.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
          if ($pattern.Current.ToggleState -ne [Windows.Automation.ToggleState]::On) { throw 'Launch choice not default checked.' }
          $checked = $true
          if ($Mode -eq 'unchecked-launch') {
            if ([OnboardingWizard]::GetForegroundWindow() -ne $window -and
                -not [OnboardingWizard]::SetForegroundWindow($window)) { throw 'Owned Finish focus failed.' }
            $launch.SetFocus()
            $shell.SendKeys(' ')
            Start-Sleep -Milliseconds 200
            if ($pattern.Current.ToggleState -ne [Windows.Automation.ToggleState]::Off) { throw 'Keyboard uncheck did not suppress launch choice.' }
            $checked = $false
          }
        }
        [void][OnboardingWizard]::SendMessage($finish, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        $finished = $true
        break
      }
      $next = [OnboardingWizard]::Find($window, 'Next')
      if ($next -eq [IntPtr]::Zero) { $next = [OnboardingWizard]::Find($window, 'Next >') }
      if ($next -ne [IntPtr]::Zero) {
        if ([OnboardingWizard]::GetForegroundWindow() -ne $window -and
            -not [OnboardingWizard]::SetForegroundWindow($window)) { throw 'Owned Next focus failed.' }
        $shell.SendKeys('%n')
      } else {
        $install = [OnboardingWizard]::Find($window, 'Install')
        if ($install -eq [IntPtr]::Zero) { throw "Unexpected wizard state: $text" }
        [void][OnboardingWizard]::SendMessage($install, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
      }
      Start-Sleep -Milliseconds 400
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $finished) { throw "Inert $Mode fixture exceeded bounded deadline." }
  Start-Sleep -Seconds 2
  $launches = if (Test-Path $privateProof) { @(Get-Content $privateProof | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
  $expected = if ($Mode -eq 'checked-launch') { 1 } else { 0 }
  if ($launches.Count -ne $expected) { throw "Launch count mismatch: expected $expected, got $($launches.Count)." }
  if ($expected -eq 1) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($launches[0].sid -ne $sid -or $launches[0].elevated) { throw 'Installing user or non-elevated launch token mismatch.' }
  }
  if (Test-Path $receipt) { throw 'Default-off fixture manufactured an observation.' }
  $actualScales = @($states | ForEach-Object { [int]($_.dpi * 100 / 96) } | Sort-Object -Unique)
  @{
    schemaVersion = 1; sourceRevision = $authorization.sourceRevision; mode = $Mode; fixture = $true
    payload = 'Inert launch-token/count probe, not Bloomstep app or a public release'; customerData = $false
    installerSha256 = (Get-FileHash $Installer).Hash.ToLower(); launchCount = $launches.Count
    launchChoice = $checked; installingUserMatches = if ($expected -eq 1) { $true } else { $null }; launchedElevated = $false
    observationReceiptAbsent = $true; requestedOsScales = $requestedScales; measuredOsScales = $actualScales
    uncoveredOsScales = @($requestedScales | Where-Object { $_ -notin $actualScales })
    screenReaderAcceptance = 'UNKNOWN; UIA/keyboard evidence is not a Narrator acceptance claim'
    states = $states
  } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceDir "$Mode.json") -Encoding utf8
} finally {
  foreach ($window in [OnboardingWizard]::Windows()) {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
    if ($owned.Contains([int]$owner)) { [void][OnboardingWizard]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
  }
  Start-Sleep -Milliseconds 300
  foreach ($id in $owned) {
    if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id }
  }
  if (Test-Path (Join-Path $target 'unins000.exe')) {
    Start-Process (Join-Path $target 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
  }
  if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
