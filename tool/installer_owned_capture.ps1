param([string]$Installer, [string]$EvidenceDir)
if (-not ('OnboardingWizard' -as [type])) {
  & "$PSScriptRoot\verify_onboarding_wizard.ps1" -Installer $Installer -EvidenceDir $EvidenceDir -LoadHelpersOnly
}
$captureOwned = @{}
$captureParents = @{}
$captureClock = [Diagnostics.Stopwatch]::StartNew()
$captureStages = [Collections.Generic.List[object]]::new()
$captureStage = 'initializing'
function Register-CaptureProcess($Process, [int]$Parent) {
  [void]$Process.Handle
  $captureOwned[$Process.Id] = $Process
  $captureParents[$Process.Id] = $Parent
}
function Update-CaptureTree {
  $tree = Get-CimInstance Win32_Process
  for ($pass = 0; $pass -lt 4; $pass++) {
    foreach ($child in $tree) {
      if ($captureOwned.ContainsKey([int]$child.ParentProcessId) -and -not $captureOwned.ContainsKey([int]$child.ProcessId)) {
        $process = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process) { Register-CaptureProcess $process ([int]$child.ParentProcessId) }
      }
    }
  }
}
function Get-CaptureWindows {
  @([OnboardingWizard]::Windows() | Where-Object {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($_, [ref]$owner)
    $captureOwned.ContainsKey([int]$owner) -and -not $captureOwned[[int]$owner].HasExited
  })
}
function Save-CaptureStage([string]$Stage) {
  $script:captureStage = $Stage
  $processes = @($captureOwned.Keys | ForEach-Object {
    $process = $captureOwned[$_]
    @{ pid = [int]$_; parentPid = $captureParents[$_]; exited = $process.HasExited;
       exitCode = if ($process.HasExited) { $process.ExitCode } else { $null } }
  })
  $dialogs = @(Get-CaptureWindows | ForEach-Object {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($_, [ref]$owner)
    $text = [OnboardingWizard]::Describe($_)
    foreach ($private in @($env:RUNNER_TEMP, $env:LOCALAPPDATA, $env:USERPROFILE)) {
      if ($private) { $text = $text.Replace($private, '[ISOLATED-HOST-PATH]') }
    }
    @{ pid = $owner; class = [OnboardingWizard]::ClassName($_); text = $text }
  })
  $captureStages.Add(@{ stage = $Stage; elapsedMilliseconds = $captureClock.ElapsedMilliseconds;
    processes = $processes; dialogs = $dialogs })
  @{ stages = $captureStages; stage = $Stage; processes = $processes; dialogs = $dialogs;
     elapsedMilliseconds = $captureClock.ElapsedMilliseconds; evidenceDirectory = '[EVIDENCE-DIRECTORY]' } |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'owned-stage-receipt.json') -Encoding utf8
}
function Start-CaptureProcess([string]$File, [string]$Arguments, [string]$Stage) {
  Save-CaptureStage "$Stage-before-start"
  $process = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
  Register-CaptureProcess $process $PID
  Save-CaptureStage "$Stage-started"
  return $process
}
function Wait-CaptureTree([string]$Stage, [int]$Seconds = 120) {
  Save-CaptureStage "$Stage-before-wait"
  $deadline = $captureClock.ElapsedMilliseconds + $Seconds * 1000
  do {
    Update-CaptureTree
    if (@($captureOwned.Values | Where-Object { -not $_.HasExited }).Count -eq 0) {
      Save-CaptureStage "$Stage-wait-completed"
      return
    }
    if ($captureClock.ElapsedMilliseconds -ge $deadline) {
      Save-CaptureStage "$Stage-timeout"
      throw "Owned $Stage process tree exceeded ${Seconds}s; owned-stage-receipt.json contains exact PID/dialog/exit state."
    }
    Start-Sleep -Milliseconds 150
  } while ($true)
}
function Invoke-CaptureButton([IntPtr]$Button, [string]$Stage) {
  [uint32]$owner = 0
  [void][OnboardingWizard]::GetWindowThreadProcessId($Button, [ref]$owner)
  if (-not $captureOwned.ContainsKey([int]$owner)) { throw 'Capture refuses an unowned control.' }
  Save-CaptureStage "$Stage-before-post"
  if (-not [OnboardingWizard]::PostMessage($Button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)) {
    throw "Owned $Stage control dispatch failed."
  }
  Save-CaptureStage "$Stage-after-post"
}
function Save-CaptureFrame([IntPtr]$Window, [string]$Name) {
  $bounds = [OnboardingWizard+Rect]::new()
  if (-not [OnboardingWizard]::GetWindowRect($Window, [ref]$bounds)) { throw 'Owned frame bounds unavailable.' }
  $width = $bounds.Right - $bounds.Left
  $height = $bounds.Bottom - $bounds.Top
  if ($width -lt 100 -or $height -lt 100) { throw 'Owned frame bounds invalid.' }
  $bitmap = [Drawing.Bitmap]::new($width, $height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $dc = $graphics.GetHdc()
  try {
    if (-not [OnboardingWizard]::PrintWindow($Window, $dc, 2)) { throw 'Actual owned frame capture failed.' }
  } finally { $graphics.ReleaseHdc($dc) }
  try { $bitmap.Save((Join-Path $EvidenceDir $Name), [Drawing.Imaging.ImageFormat]::Png) }
  finally { $graphics.Dispose(); $bitmap.Dispose() }
  return @{ file = $Name; sha256 = (Get-FileHash (Join-Path $EvidenceDir $Name)).Hash.ToLower();
    elapsedMilliseconds = $captureClock.ElapsedMilliseconds; dpi = [OnboardingWizard]::GetDpiForWindow($Window);
    width = $width; height = $height }
}
function Stop-CaptureTree {
  Update-CaptureTree
  Save-CaptureStage 'finally-before-owned-cleanup'
  foreach ($process in $captureOwned.Values) {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction Stop }
  }
  try { Wait-CaptureTree 'cleanup' 5 }
  finally { Save-CaptureStage 'finally-owned-exit-state' }
}
