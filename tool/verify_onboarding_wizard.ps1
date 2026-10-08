param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$EvidenceDir,
  [string]$FixtureManifest,
  [switch]$LoadHelpersOnly,
  [switch]$AllowUnavailableKeyboard
)
$ErrorActionPreference = 'Stop'
if (-not $LoadHelpersOnly) {
  if (-not $FixtureManifest) { throw 'Compile-only fixture authority is required before capture.' }
  $compiledFixture = Get-Content -LiteralPath $FixtureManifest -Raw | ConvertFrom-Json
  $compiledSourcePath = Join-Path (Split-Path -Parent $FixtureManifest) 'fixture-preprocessed.iss'
  $compiledSource = Get-Content -LiteralPath $compiledSourcePath -Raw
  if ($compiledFixture.kind -ne 'compile-only-onboarding-fixture-v1' -or
      $compiledFixture.fixtureAppId -ne '8E9B101B-CB3D-4C0F-B733-FC1DFFB75129' -or
      $compiledFixture.installationProhibited -ne $true -or
      $compiledFixture.sourceRevision -notmatch '^[a-f0-9]{40}$' -or
      $compiledFixture.preprocessedSha256 -ne (Get-FileHash -LiteralPath $compiledSourcePath).Hash.ToLower() -or
      $compiledSource -notmatch 'AppId=\{\{8E9B101B-CB3D-4C0F-B733-FC1DFFB75129\}' -or
      $compiledSource -notmatch "function PrepareToInstall[\s\S]*?Result := 'Compile-only onboarding fixture\. Installation is prohibited; cancel this wizard\.';[\s\S]*?end;" -or
      $compiledFixture.installerFile -ne [IO.Path]::GetFileName($Installer) -or
      $compiledFixture.installerSha256 -ne (Get-FileHash -LiteralPath $Installer).Hash.ToLower()) {
    throw 'Only the exact hash-authorized compile-only onboarding fixture may be captured; never a customer installer.'
  }
}
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
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public struct Rect { public int Left, Top, Right, Bottom; }
  public static string ClassName(IntPtr h) {
    var b = new StringBuilder(256); GetClassName(h,b,b.Capacity); return b.ToString();
  }
  public static string GetWindowTitle(IntPtr h) {
    var b = new StringBuilder(4096); GetWindowText(h,b,b.Capacity); return b.ToString();
  }
  public static bool HasVisibleChildren(IntPtr owner) {
    bool found = false;
    EnumChildWindows(owner,(h,p) => {
      if (IsWindowVisible(h)) found = true;
      return true;
    },IntPtr.Zero);
    return found;
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
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Native fixture capture is restricted to disposable CI.' }
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $Installer -EvidenceDir $EvidenceDir
if (-not [OnboardingWizard]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  throw 'Capture process could not use per-monitor DPI coordinates.'
}
$target = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
if ((Test-Path $target) -or (Test-Path $receipt)) { throw 'Capture refuses existing installation/receipt state.' }
$states = [Collections.Generic.List[object]]::new()
$report = @{ sourceRevision = $compiledFixture.sourceRevision; installerSha256 = $compiledFixture.installerSha256;
  expectedOrder = @('welcome', 'destination'); states = $states; installed = $false; outcome = 'running' }
try {
  $setup = Start-CaptureProcess $Installer '/SP- /NORESTART' 'destination-fixture'
  $observed = $false
  $cancelled = $false
  $welcomeAt = $null
  $deadline = $captureClock.ElapsedMilliseconds + 40000
  while (-not $cancelled -and $captureClock.ElapsedMilliseconds -lt $deadline) {
    Update-CaptureTree
    foreach ($window in Get-CaptureWindows) {
      $text = [OnboardingWizard]::Describe($window)
      if ($null -eq $welcomeAt -and [OnboardingWizard]::ClassName($window) -eq 'TWizardForm') {
        if ($text -notmatch '(^| \| )Anchor( \| |$)' -or $text -notmatch '(^| \| )Action( \| |$)' -or
            $text -notmatch '(^| \| )Celebrate( \| |$)' -or $text.Contains('Select Destination Location')) {
          throw 'First observed wizard page was not the Anchor/Action/Celebrate welcome.'
        }
        if ([OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero -or
            [OnboardingWizard]::Find($window, 'Back') -ne [IntPtr]::Zero -or
            [OnboardingWizard]::Find($window, 'Cancel') -eq [IntPtr]::Zero) {
          throw 'Welcome must offer only Cancel; it advances on its own.'
        }
        $welcomeAt = $captureClock.ElapsedMilliseconds
        $frame = Save-CaptureFrame $window 'fixture-welcome.png'
        $frame.step = 'welcome'
        $frame.visibleWords = @('Anchor', 'Action', 'Celebrate')
        $states.Add($frame)
        continue
      }
      if (-not $observed -and $null -ne $welcomeAt -and [OnboardingWizard]::ClassName($window) -eq 'TWizardForm' -and
          $text.Contains('Select Destination Location')) {
        # The page text can appear a moment before Inno relabels the primary button; observe the settled page.
        if ([OnboardingWizard]::Find($window, 'Install') -eq [IntPtr]::Zero -and
            [OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero) { continue }
        $report.welcomeToDestinationMilliseconds = $captureClock.ElapsedMilliseconds - $welcomeAt
        if ($report.welcomeToDestinationMilliseconds -lt 3500) { throw 'Welcome advanced before about 4 seconds.' }
        if ($text -match 'click Next|select Next') { throw 'Destination hint still instructs Next instead of Install.' }
        if ([OnboardingWizard]::Find($window, $target) -eq [IntPtr]::Zero) {
          throw 'Native destination did not preserve the current per-user default.'
        }
        $report.defaultDirectoryMatches = $true
        foreach ($caption in @('Install', 'Browse...', 'Cancel')) {
          if ([OnboardingWizard]::Find($window, $caption) -eq [IntPtr]::Zero) { throw "Destination control missing: $caption" }
        }
        if ([OnboardingWizard]::Find($window, 'Next') -ne [IntPtr]::Zero) { throw 'Destination displayed Next instead of Install.' }
        if ([OnboardingWizard]::Find($window, 'Back') -ne [IntPtr]::Zero) { throw 'Destination must not offer Back.' }
        $report.destinationBackAbsent = $true
        $frame = Save-CaptureFrame $window 'fixture-destination.png'
        $frame.step = 'destination'
        $root = [Windows.Automation.AutomationElement]::FromHandle($window)
        $controls = $root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
        $frame.accessibility = @($controls | ForEach-Object {
          if (-not $_.Current.IsOffscreen -and $_.Current.Name) {
            @{ name = $_.Current.Name; keyboardFocusable = $_.Current.IsKeyboardFocusable; type = $_.Current.ControlType.ProgrammaticName }
          }
        })
        $states.Add($frame)
        Invoke-CaptureButton ([OnboardingWizard]::Find($window, 'Cancel')) 'destination-cancel'
        $observed = $true
      } elseif ($observed -and $text -match 'Exit Setup|Setup is not complete|If you exit now') {
        $yes = [OnboardingWizard]::Find($window, 'Yes')
        if ($yes -ne [IntPtr]::Zero) {
          Invoke-CaptureButton $yes 'destination-cancel-confirmation'
          $cancelled = $true
        }
      }
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $cancelled) { Save-CaptureStage 'destination-timeout'; throw 'Actual destination/Cancel confirmation not observed before deadline.' }
  Wait-CaptureTree 'destination-cancel' 20
  if ($setup.ExitCode -ne 2) { throw 'Actual destination Cancel launcher did not exit2.' }
  if ((Test-Path $target) -or (Test-Path $receipt)) { throw 'Destination Cancel created install/observation content.' }
  $report.receiptAbsent = $true
  $report.targetAbsent = $true
  $report.cancelExit = $setup.ExitCode
  $report.outcome = 'actual-welcome-auto-advance-destination-and-Cancel; Install never selected'
  $report.keyboardNavigation = 'UNKNOWN; original native Install/Browse/Cancel controls and UIA names captured, not keyboard or Narrator acceptance'
} catch {
  $report.outcome = 'FAIL; actual destination evidence incomplete'
  Save-CaptureStage 'destination-proof-failed'
  throw
} finally {
  try { Stop-CaptureTree }
  finally { $report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'fixture-wizard-proof.json') -Encoding utf8 }
}
