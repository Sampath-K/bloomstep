param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$EvidenceDir,
  [switch]$LoadHelpersOnly
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class OnboardingWizard {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr x);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr x);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder b, int c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder b, int c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct Rect { public int Left, Top, Right, Bottom; }
  public static string ClassName(IntPtr h) {
    var b = new StringBuilder(256); GetClassName(h,b,b.Capacity); return b.ToString();
  }
  public static IntPtr[] Windows() {
    var a = new List<IntPtr>();
    EnumWindows((h,p) => { if (IsWindowVisible(h)) a.Add(h); return true; }, IntPtr.Zero);
    return a.ToArray();
  }
  public static IntPtr Find(IntPtr owner, string caption) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(owner,(h,p) => {
      var b = new StringBuilder(4096); GetWindowText(h,b,b.Capacity);
      if (IsWindowVisible(h) && IsWindowEnabled(h) &&
          b.ToString().Replace("&","").Trim() == caption.Replace("&","").Trim()) found=h;
      return true;
    },IntPtr.Zero);
    return found;
  }
  public static IntPtr Memo(IntPtr owner) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(owner,(h,p) => {
      if (IsWindowVisible(h) && ClassName(h).Contains("Memo")) found=h;
      return true;
    },IntPtr.Zero);
    return found;
  }
  public static string Describe(IntPtr owner) {
    var texts = new List<string>();
    EnumChildWindows(owner,(h,p) => {
      var b = new StringBuilder(8192); GetWindowText(h,b,b.Capacity);
      if (IsWindowVisible(h) && b.Length > 0) texts.Add(b.ToString());
      return true;
    },IntPtr.Zero);
    return string.Join(" | ",texts);
  }
}
'@
if ($LoadHelpersOnly) { return }
if (-not [OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  throw 'Capture process could not use per-monitor DPI coordinates; do not claim a clipped screenshot.'
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$target = Join-Path $EvidenceDir 'NEVER-INSTALL'
if (Test-Path $target) { throw 'Capture target must not exist.' }
$setup = Start-Process -FilePath $Installer -ArgumentList "/SP- /NORESTART /DIR=`"$target`"" -PassThru
$owned = [Collections.Generic.HashSet[int]]::new()
[void]$owned.Add($setup.Id)
$states = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new()
$ready = $false
$backVerified = $false
$expectedOrder = @('Welcome', 'recipe', 'grow', 'destination', 'optional-observations', 'ready')
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
if (Test-Path $receipt) { throw 'Capture refuses an existing installer receipt.' }
try {
  $deadline = (Get-Date).AddSeconds(40)
  while ((Get-Date) -lt $deadline -and -not $ready) {
    $processes = Get-CimInstance Win32_Process
    foreach ($process in $processes) {
      if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
    }
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$owner = 0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
      if (-not $owned.Contains([int]$owner)) { continue }
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') { continue }
      $text = [OnboardingWizard]::Describe($window)
      if (-not $seen.Add($text)) { continue }
      if ($states.Count -eq 0 -and -not $text.Contains('Welcome to Bloomstep')) {
        throw 'First observed wizard page was not Welcome.'
      }
      $step = if ($text.Contains('Welcome to Bloomstep')) { 'Welcome' }
        elseif ($text.Contains('Plant a tiny recipe')) { 'recipe' }
        elseif ($text.Contains('Celebrate and grow')) { 'grow' }
        elseif ($text.Contains('Optional local installation observations')) { 'optional-observations' }
        elseif ($text.Contains('Ready to install this unsigned Bloomstep preview')) { 'ready' }
        elseif ($text.Contains('Select Destination Location')) { 'destination' }
        else { throw "Unexpected wizard page: $text" }
      if ($step -ne $expectedOrder[$states.Count]) { throw "Unexpected page order: $step" }
      $checkbox = [OnboardingWizard]::Find($window, 'Save optional local observations (unchecked by default)')
      if ($checkbox -ne [IntPtr]::Zero) {
        if ([OnboardingWizard]::SendMessage($checkbox, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -ne 0) {
          throw 'Consent checkbox was not unchecked.'
        }
      }
      $rectangle = New-Object OnboardingWizard+Rect
      if (-not [OnboardingWizard]::GetWindowRect($window, [ref]$rectangle)) { throw 'Could not read owned wizard bounds.' }
      $width = $rectangle.Right - $rectangle.Left
      $height = $rectangle.Bottom - $rectangle.Top
      if ($width -lt 100 -or $height -lt 100) { throw "Invalid owned wizard size: ${width}x${height}" }
      $bitmap = [Drawing.Bitmap]::new($width, $height)
      $graphics = [Drawing.Graphics]::FromImage($bitmap)
      $dc = $graphics.GetHdc()
      try {
        if (-not [OnboardingWizard]::PrintWindow($window, $dc, 2)) { throw 'Owned wizard capture failed.' }
      } finally { $graphics.ReleaseHdc($dc) }
      $filename = 'fixture-wizard-' + $states.Count + '.png'
      try { $bitmap.Save((Join-Path $EvidenceDir $filename), [Drawing.Imaging.ImageFormat]::Png) }
      finally { $graphics.Dispose(); $bitmap.Dispose() }
      $root = [Windows.Automation.AutomationElement]::FromHandle($window)
      $controls = $root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
      $accessible = @($controls | ForEach-Object {
        if (-not $_.Current.IsOffscreen -and $_.Current.Name) {
          @{ name = $_.Current.Name; keyboardFocusable = $_.Current.IsKeyboardFocusable; type = $_.Current.ControlType.ProgrammaticName }
        }
      })
      $states.Add(@{ step = $step; caption = $text; image = $filename; fixture = $true;
        installed = $false; dpi = [OnboardingWizard]::GetDpiForWindow($window);
        accessibility = $accessible; screenshotSha256 = (Get-FileHash (Join-Path $EvidenceDir $filename)).Hash.ToLower() })
      if ($text.Contains('Ready to install this unsigned Bloomstep preview')) {
        $memo = [OnboardingWizard]::Memo($window)
        if ($memo -eq [IntPtr]::Zero) { throw 'Native ready memo missing.' }
        [void][OnboardingWizard]::SendMessage($memo, 0x0115, [IntPtr]7, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 300
        $bitmap = [Drawing.Bitmap]::new($width, $height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $dc = $graphics.GetHdc()
        try {
          if (-not [OnboardingWizard]::PrintWindow($window, $dc, 2)) { throw 'Ready teaching capture failed.' }
        } finally { $graphics.ReleaseHdc($dc) }
        try { $bitmap.Save((Join-Path $EvidenceDir 'fixture-ready-teaching.png'), [Drawing.Imaging.ImageFormat]::Png) }
        finally { $graphics.Dispose(); $bitmap.Dispose() }
        $ready = $true
        break
      }
      $next = [OnboardingWizard]::Find($window, '&Next')
      if ($next -eq [IntPtr]::Zero) { $next = [OnboardingWizard]::Find($window, '&Next >') }
      if ($next -eq [IntPtr]::Zero) { throw "Unexpected capture step; will not click Install or Finish: $text" }
      if (-not [OnboardingWizard]::SetForegroundWindow($window)) { throw 'Owned wizard could not obtain keyboard focus.' }
      $shell = New-Object -ComObject WScript.Shell
      if ($step -eq 'recipe') {
        $shell.SendKeys('%b')
        Start-Sleep -Milliseconds 200
        if (-not [OnboardingWizard]::Describe($window).Contains('Welcome to Bloomstep')) { throw 'Keyboard Back did not return to Welcome.' }
        $shell.SendKeys('%n')
        Start-Sleep -Milliseconds 200
        if (-not [OnboardingWizard]::Describe($window).Contains('Plant a tiny recipe')) { throw 'Keyboard Next did not restore recipe teaching.' }
        $backVerified = $true
      }
      $shell.SendKeys('%n')
      Start-Sleep -Milliseconds 300
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $ready) { throw 'Owned fixture did not reach Ready within bounded capture deadline.' }
  if (($states.step -join ',') -ne ($expectedOrder -join ',')) { throw 'Incomplete educational/options order.' }
  if (Test-Path $receipt) { throw 'Pre-consent educational capture wrote an installer receipt.' }
  @{
    sourceRevision = $env:GITHUB_SHA
    installerSha256 = (Get-FileHash $Installer).Hash.ToLower()
    expectedOrder = $expectedOrder
    states = $states
    receiptAbsent = $true
    targetAbsent = -not (Test-Path $target)
    keyboardNavigation = 'Actual Alt+N on owned native wizard; Install and Finish never selected'
    keyboardBackVerified = $backVerified
    screenReaderAcceptance = 'Not established; UI Automation names recorded, not a Narrator acceptance claim'
    installed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceDir 'fixture-wizard-proof.json') -Encoding utf8
} finally {
  foreach ($window in [OnboardingWizard]::Windows()) {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
    if ($owned.Contains([int]$owner)) {
      [void][OnboardingWizard]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    }
  }
  Start-Sleep -Milliseconds 300
  foreach ($window in [OnboardingWizard]::Windows()) {
    [uint32]$owner = 0
    [void][OnboardingWizard]::GetWindowThreadProcessId($window, [ref]$owner)
    if ($owned.Contains([int]$owner)) {
      $yes = [OnboardingWizard]::Find($window, '&Yes')
      if ($yes -ne [IntPtr]::Zero) {
        [void][OnboardingWizard]::PostMessage($yes, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
      }
    }
  }
  Start-Sleep -Milliseconds 300
  foreach ($id in $owned) {
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -ne $process) { Stop-Process -Id $id -ErrorAction SilentlyContinue }
  }
}
if (Test-Path $target) { throw 'Capture unexpectedly created installation content.' }
Write-Output 'Captured native fixture directory, unchecked consent and Ready steps; never clicked Install or Finish.'
