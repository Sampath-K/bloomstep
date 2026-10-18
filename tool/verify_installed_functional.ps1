<#
.SYNOPSIS
Bounded, partial installed-build observations on a fresh GitHub-hosted Windows VM.
.DESCRIPTION
Run with 64-bit Windows PowerShell (powershell.exe -STA -File ...). No accounts,
uploads, protection changes, synthetic fixture, or release approval. Output
must be a descendant of RUNNER_TEMP containing only the workflow's identity.json.
InstallDir must be a NEW descendant of RUNNER_TEMP. Supply the downloaded installer exactly;
the harness never builds an app. CandidateCommit may also be the baseline's full SHA.
Nonzero exit is intentional until ALL functional requirements have real proof.
results.json uses the release evidence shape but deliberately cannot pass the gate:
partial probe PASS is NOT requirement PASS; no baseline failure is inferred.
User-profile data generated on this disposable VM is retained, never broadly deleted.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$ExpectedSha256,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][ValidateSet('candidate','baseline')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$Requirements,
  [Parameter(Mandatory=$true)][string]$Identity,
  [Parameter(Mandatory=$true)][string]$Output
)
$InstallerPath = $Installer
$OutputDirectory = $Output
$CandidateCommit = 'UNVERIFIED'
$RunId = 'UNVERIFIED'
$ArtifactId = 'UNVERIFIED'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:app = $null
$script:installer = $null
$script:uninstaller = $null
$script:root = $null
$script:exe = $null
$script:installStarted = $false
$script:threatIds = @()
$script:checks = [Collections.Generic.List[object]]::new()
$script:failure = $null
$script:phase = 'preflight'
$script:clock = [Diagnostics.Stopwatch]::StartNew()

function Assert-Time {
  if ($script:clock.Elapsed.TotalSeconds -gt 240) { throw 'Overall observation budget (240s) exhausted.' }
}
function Assert-NoReparse([string]$Path) {
  $p = $Path
  while ($p) {
    if (Test-Path -LiteralPath $p) {
      if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Reparse path refused: $p"
      }
    }
    $next = Split-Path -Parent $p
    if ($next -eq $p) { break }
    $p = $next
  }
}
function Assert-Defender {
  $status = Get-MpComputerStatus -ErrorAction Stop
  $result['defender'] = [ordered]@{
    observedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    AMServiceEnabled = $status.AMServiceEnabled
    AntivirusEnabled = $status.AntivirusEnabled
    RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
    AMRunningMode = $status.AMRunningMode
    AntivirusSignatureVersion = $status.AntivirusSignatureVersion
  }
  if (!$status.AMServiceEnabled -or !$status.AntivirusEnabled -or !$status.RealTimeProtectionEnabled) {
    throw "Defender protection unavailable/disabled; no bypass permitted. AMServiceEnabled=$($status.AMServiceEnabled); AntivirusEnabled=$($status.AntivirusEnabled); RealTimeProtectionEnabled=$($status.RealTimeProtectionEnabled); AMRunningMode=$($status.AMRunningMode)"
  }
  $detections = @(Get-MpThreatDetection -ErrorAction Stop)
  foreach ($d in $detections) {
    $related = @($d.Resources | Where-Object {
      $_ -like "*$InstallerPath*" -or $_ -like "*$script:appDir*"
    }).Count -gt 0
    if ($related -or ($script:defenderInitialized -and "$($d.DetectionID)" -notin $script:threatIds)) {
      throw "Defender detection $($d.DetectionID); hard failure, never retry or bypass."
    }
  }
  if (!$script:defenderInitialized) {
    $script:threatIds = @($detections | ForEach-Object { "$($_.DetectionID)" })
    $script:defenderInitialized = $true
  }
}
function Assert-Owned {
  Assert-Time
  $script:app.Refresh()
  if ($script:app.HasExited) { throw 'Installed app exited.' }
  if ((Get-Process -Id $script:app.Id -ErrorAction Stop).Path -ne $script:exe) {
    throw 'Installed process path ownership lost.'
  }
  [InstalledFunctionalNative]::Owned($script:window, [uint32]$script:app.Id)
}
function Get-Control([string]$Name, [string]$Type = '') {
  Assert-Owned
  $nameCondition = [Windows.Automation.PropertyCondition]::new(
    [Windows.Automation.AutomationElement]::NameProperty, $Name)
  $matches = @($script:root.FindAll([Windows.Automation.TreeScope]::Descendants, $nameCondition) |
    Where-Object {
      $_.Current.ProcessId -eq $script:app.Id -and !$_.Current.IsOffscreen -and
      (!$Type -or $_.Current.ControlType.ProgrammaticName -eq "ControlType.$Type")
    })
  if ($matches.Count -gt 1) { throw "Ambiguous owned UIA control: $Name" }
  if ($matches.Count -eq 1) { return $matches[0] }
  return $null
}
function Wait-Control([string]$Name, [string]$Type = '') {
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  do {
    $control = Get-Control $Name $Type
    if ($null -ne $control) { return $control }
    Start-Sleep -Milliseconds 150
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Owned UIA control unavailable within 8s: $Name ($Type)"
}
function Invoke-Control([string]$Name) {
  $control = Wait-Control $Name 'Button'
  Assert-Owned
  if (!$control.Current.IsEnabled) { throw "Disabled owned control: $Name" }
  $pattern = $control.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
  $pattern.Invoke()
}
function Set-Field([string]$Name, [string]$Value) {
  $control = Wait-Control $Name 'Edit'
  Assert-Owned
  $pattern = $control.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
  if ($pattern.Current.IsReadOnly) { throw "Read-only field: $Name" }
  $pattern.SetValue($Value)
  if ($pattern.Current.Value -cne $Value) { throw "Typed-entry readback mismatch: $Name" }
}
function Save-Observation([string]$Name) {
  Assert-Owned
  # PrintWindow captures only the owned window, never the entire desktop.
  # This is deliberately NOT labelled light/dark: current app has no theme picker.
  [InstalledFunctionalNative]::Capture($script:window, [uint32]$script:app.Id,
    (Join-Path $OutputDirectory "$Name-observed.png"))
  $nodes = $script:root.FindAll([Windows.Automation.TreeScope]::Descendants,
    [Windows.Automation.Condition]::TrueCondition)
  if ($nodes.Count -gt 3000) { throw 'UIA snapshot node bound exceeded.' }
  @($nodes | Where-Object { $_.Current.ProcessId -eq $script:app.Id } |
    ForEach-Object {
      [ordered]@{ name=$_.Current.Name; type=$_.Current.ControlType.ProgrammaticName;
        enabled=$_.Current.IsEnabled; offscreen=$_.Current.IsOffscreen }
    }) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Name-uia.json") -Encoding UTF8
}
function Probe([string]$Requirement, [string]$Name, [scriptblock]$Body) {
  $script:phase = $Name
  try {
    Assert-Defender
    & $Body
    Assert-Defender
    $script:checks.Add([ordered]@{requirement=$Requirement; name=$Name; result='PASS';
      detail='Only the named sub-observation completed; not full requirement acceptance.'})
  } catch {
    $script:checks.Add([ordered]@{requirement=$Requirement; name=$Name; result='FAIL';
      detail=$_.Exception.Message})
    throw
  }
}
function Stop-Owned([Diagnostics.Process]$Process, [string]$Path) {
  if ($null -eq $Process) { return }
  $Process.Refresh()
  if ($Process.HasExited) { return }
  if ((Get-Process -Id $Process.Id -ErrorAction Stop).Path -ne $Path) {
    throw 'Cleanup path ownership mismatch; process not touched.'
  }
  [void]$Process.CloseMainWindow()
  if (!$Process.WaitForExit(3000)) {
    Stop-Process -Id $Process.Id -ErrorAction Stop
    if (!$Process.WaitForExit(3000)) { throw 'Owned process cleanup timeout.' }
  }
}

# Establish a safe, fresh receipts directory before any executable is run.
# Invalid output paths are rejected without writing outside the allowed scope.
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows required; no installed UIA execution occurred.' }
if (!$env:RUNNER_TEMP -or ![IO.Path]::IsPathRooted($OutputDirectory)) { throw 'Absolute outputDirectory under RUNNER_TEMP required.' }
$runnerTemp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (!$OutputDirectory.StartsWith($runnerTemp + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'outputDirectory must be a scoped descendant of RUNNER_TEMP.'
}
Assert-NoReparse $OutputDirectory
if (Test-Path -LiteralPath $OutputDirectory) {
  if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force |
      Where-Object { $_.Name -ne 'identity.json' -or $_.PSIsContainer }).Count) {
    throw 'Existing output evidence refused; only identity.json may preexist.'
  }
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$script:appDir = $null
$script:defenderInitialized = $false
$contract = $null
$result = [ordered]@{
  schema='budlark-functional-evidence-v1'; candidateCommit=$CandidateCommit
  installerSha256=$ExpectedSha256; artifact=@{runId=$RunId; artifactId=$ArtifactId}
  environment=@{kind='UNVERIFIED'; os=[Environment]::OSVersion.VersionString; interactive=$false}
  run=$null; executedAt=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  baseline=@{commit='083f2def66c1e084c56653238b85802ff260c3c3'; run=$null; result='UNVERIFIED'}
  result='UNVERIFIED'; customerAcceptance=$false; phase='preflight'; tests=@(); probes=@()
  blockers=@(
    'No account/provider, invitation delivery, feedback receipt or reminder delivery proof.',
    'No app theme setting in current UI: paired light/dark screenshots UNVERIFIED; observed captures are not theme evidence.',
    'No baseline comparison inferred. Run this same harness separately on exact baseline bytes.',
    'Subset observations do not cover every text field, every check-in action, persistence or all visual requirements.',
    'Artifact inputs bind receipts, not authenticated GitHub provenance; existing release gate must verify provenance.'
  )
}
try {
  $expectedRequirements = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\release\functional-requirements.json'))
  if ([IO.Path]::GetFullPath($Requirements) -ne $expectedRequirements) { throw 'Only repository functional requirements permitted.' }
  $contract = Get-Content -LiteralPath $expectedRequirements -Raw | ConvertFrom-Json
  $expectedIdentity = Join-Path $OutputDirectory 'identity.json'
  if ([IO.Path]::GetFullPath($Identity) -ne $expectedIdentity) { throw 'Identity must be output/identity.json.' }
  Assert-NoReparse $Identity
  $identityRecord = Get-Content -LiteralPath $Identity -Raw | ConvertFrom-Json
  $CandidateCommit = [string]$identityRecord.candidate
  $RunId = [string]$identityRecord.runId
  $ArtifactId = [string]$identityRecord.artifactId
  $result.candidateCommit = $CandidateCommit
  $result.artifact = @{runId=$RunId; artifactId=$ArtifactId}
  if ($identityRecord.schema -ne 'budlark-functional-identity-v1' -or
      $identityRecord.installerSha256 -cne $ExpectedSha256 -or $identityRecord.mode -cne $Mode -or
      $identityRecord.runner -cne $env:RUNNER_NAME -or [string]::IsNullOrWhiteSpace($identityRecord.os)) {
    throw 'Workflow identity mismatch.'
  }
  if ($Mode -eq 'baseline' -and $CandidateCommit -cne $contract.baselineCommit) {
    throw 'Baseline mode must target the exact functional-contract baseline commit.'
  }
  if (![IO.Path]::IsPathRooted($InstallDir)) { throw 'Absolute installDir required.' }
  $script:appDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
  if (!$script:appDir.StartsWith($runnerTemp + '\', [StringComparison]::OrdinalIgnoreCase) -or
      $script:appDir -eq $OutputDirectory -or
      $script:appDir.StartsWith($OutputDirectory + '\', [StringComparison]::OrdinalIgnoreCase) -or
      $OutputDirectory.StartsWith($script:appDir + '\', [StringComparison]::OrdinalIgnoreCase) -or
      $identityRecord.installDir -cne $script:appDir) { throw 'InstallDir must be separately scoped under RUNNER_TEMP and match identity.' }
  Assert-NoReparse $script:appDir
  if (Test-Path -LiteralPath $script:appDir) { throw 'Existing installDir refused.' }
  $result['mode'] = $Mode
  $result['installDir'] = $script:appDir
  if ($CandidateCommit -cnotmatch '^[0-9a-f]{40}$' -or $ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or
      $RunId -notmatch '^[1-9][0-9]*$' -or $ArtifactId -notmatch '^[1-9][0-9]*$') {
    throw 'Full lowercase candidate SHA, SHA-256 and numeric run/artifact ids required.'
  }
  if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
      $env:RUNNER_OS -ne 'Windows' -or $env:ImageOS -notmatch '^win' -or
      $env:GITHUB_RUN_ID -notmatch '^[1-9][0-9]*$' -or $env:GITHUB_REPOSITORY -notmatch '^[\w.-]+/[\w.-]+$') {
    throw 'Fresh GitHub-hosted Windows job with actual run identity required; self-hosted reuse refused.'
  }
  # RunId identifies the build artifact; this run identifies the actual execution.
  $result.run = "https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
  if ($identityRecord.run -cne $result.run) { throw 'Identity run must equal actual executing GitHub run URL.' }
  if (![Environment]::Is64BitProcess -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') {
    throw 'Native x64 Windows and 64-bit PowerShell required; no emulation claim.'
  }
  if (![Environment]::UserInteractive -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Interactive STA desktop unavailable; invoke powershell.exe -STA. No UIA proof.'
  }
  if (![IO.Path]::IsPathRooted($InstallerPath)) { throw 'Exact absolute installer path required.' }
  $InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
  if (!$InstallerPath.StartsWith($runnerTemp + '\', [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetExtension($InstallerPath) -ne '.exe' -or
      $InstallerPath.StartsWith($script:appDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only the exact downloaded .exe under RUNNER_TEMP is permitted.'
  }
  Assert-NoReparse $InstallerPath
  $item = Get-Item -LiteralPath $InstallerPath
  if ($item.PSIsContainer -or $item.Length -gt 1GB) { throw 'Invalid/beyond-bound installer file.' }
  $actualHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -cne $ExpectedSha256) { throw 'Installer SHA-256 mismatch; not executed.' }
  $result.installerSha256 = $actualHash
  $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
  $result['authenticode'] = $signature.Status.ToString()
  # Signing is not an owner prerequisite. Preserve its actual status; an invalid
  # present signature is not equivalent to unsigned bytes verified by exact hash.
  if ($signature.Status.ToString() -notin @('Valid','NotSigned')) {
    throw "Invalid/unverifiable present Authenticode signature: $($signature.Status); no trust bypass."
  }
  if (@(Get-Process -Name bloomstep -ErrorAction SilentlyContinue).Count) { throw 'Existing app process; refusing input or cleanup.' }
  foreach ($p in @(
    "$env:APPDATA\com.bloomstep\bloomstep", "$env:LOCALAPPDATA\com.bloomstep\bloomstep",
    "$env:LOCALAPPDATA\Programs\Bloomstep", "$env:LOCALAPPDATA\Programs\Budlark",
    'HKCU:\Software\Classes\bloomstep',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}_is1'
  )) {
    if (Test-Path -LiteralPath $p) { throw "Existing user app state/install registration: $p; no deletion permitted." }
  }
  foreach ($registry in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )) {
    if (Test-Path -LiteralPath $registry) {
      foreach ($key in Get-ChildItem -LiteralPath $registry) {
        $displayName = $key.GetValue('DisplayName', '')
        if ($displayName -match '(?i)bloomstep|budlark') {
          throw 'Existing user/machine app uninstall registration; no installation permitted.'
        }
      }
    }
  }
  Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
  Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class InstalledFunctionalNative {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] struct GUI {
    public int size,flags; public IntPtr active,focus,capture,menu,move,caret; public RECT rect;
  }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
  [StructLayout(LayoutKind.Explicit)] struct UNION {
    [FieldOffset(0)] public KEY key; [FieldOffset(0)] public MOUSE mouse;
  }
  [StructLayout(LayoutKind.Sequential)] struct KEY {
    public ushort vk,scan; public uint flags,time; public UIntPtr extra;
  }
  [StructLayout(LayoutKind.Sequential)] struct MOUSE {
    public int x,y; public uint data,flags,time; public UIntPtr extra;
  }
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
  [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI info);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool GetUserObjectInformation(
    IntPtr obj,int index,System.Text.StringBuilder name,int count,out int needed);
  [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
  [DllImport("user32.dll")] static extern bool EmptyClipboard();
  [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format,IntPtr data);
  [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
  [DllImport("user32.dll")] static extern bool CloseClipboard();
  [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags,UIntPtr size);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr memory);
  [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
  [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w,out RECT rect);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr w,IntPtr dc,uint flags);
  public static void Desktop() {
    var desktop=OpenInputDesktop(0,false,1);
    if(desktop==IntPtr.Zero)throw new InvalidOperationException("No accessible interactive input desktop.");
    try {
      int needed;var name=new System.Text.StringBuilder(128);
      if(!GetUserObjectInformation(desktop,2,name,256,out needed)||name.ToString()!="Default")
        throw new InvalidOperationException("Locked/secure/non-default desktop; no UIA/input.");
    } finally {CloseDesktop(desktop);}
  }
  public static void Owned(IntPtr window,uint expected) {
    Desktop(); uint actual;
    if(window==IntPtr.Zero||GetWindowThreadProcessId(window,out actual)==0||actual!=expected)
      throw new InvalidOperationException("Owned installed window PID mismatch.");
  }
  public static void Focus(uint expected) {
    Desktop(); uint actual;var foreground=GetForegroundWindow();
    uint thread=GetWindowThreadProcessId(foreground,out actual);
    var info=new GUI();info.size=Marshal.SizeOf(typeof(GUI));
    if(actual!=expected||!GetGUIThreadInfo(thread,ref info)||info.focus==IntPtr.Zero)
      throw new InvalidOperationException("Owned interactive foreground/focus unavailable; no keys sent.");
    GetWindowThreadProcessId(info.focus,out actual);
    if(actual!=expected)throw new InvalidOperationException("Foreign focus; no keys sent.");
  }
  public static void Clipboard(IntPtr window,uint pid,string text) {
    Owned(window,pid);Focus(pid);
    if(!OpenClipboard(window))throw new InvalidOperationException("Clipboard busy; no retry/bypass.");
    IntPtr memory=IntPtr.Zero;
    try {
      if(!EmptyClipboard())throw new InvalidOperationException("Clipboard clear failed.");
      byte[] bytes=System.Text.Encoding.Unicode.GetBytes(text+"\0");
      memory=GlobalAlloc(0x42,(UIntPtr)bytes.Length);
      if(memory==IntPtr.Zero)throw new InvalidOperationException("Clipboard allocation failed.");
      var data=GlobalLock(memory);
      if(data==IntPtr.Zero)throw new InvalidOperationException("Clipboard lock failed.");
      Marshal.Copy(bytes,0,data,bytes.Length);GlobalUnlock(memory);
      if(SetClipboardData(13,memory)==IntPtr.Zero)throw new InvalidOperationException("Clipboard set failed.");
      memory=IntPtr.Zero; // Clipboard now owns this HGLOBAL.
      var read=GetClipboardData(13);var locked=GlobalLock(read);
      if(locked==IntPtr.Zero)throw new InvalidOperationException("Clipboard readback lock failed.");
      try {
        if(Marshal.PtrToStringUni(locked)!=text)throw new InvalidOperationException("Clipboard readback mismatch.");
      } finally {GlobalUnlock(read);}
    } finally {if(memory!=IntPtr.Zero)GlobalFree(memory);CloseClipboard();}
  }
  public static void Paste(uint pid) {
    Focus(pid);
    foreach(int key in new[]{0x10,0x11,0x12,0x5B,0x5C})
      if((GetAsyncKeyState(key)&0x8000)!=0)throw new InvalidOperationException("Held modifier; no input.");
    var keys=new INPUT[4];
    for(int i=0;i<4;i++) {keys[i].type=1;keys[i].data.key.vk=(ushort)((i==0||i==3)?0x11:0x56);
      keys[i].data.key.flags=(uint)(i>=2?2:0);}
    // One atomic batch, only after native foreground+focus checks; never activate a foreign app.
    Focus(pid);
    if(SendInput(4,keys,Marshal.SizeOf(typeof(INPUT)))!=4)
      throw new InvalidOperationException("Ctrl+V input rejected/partial; no fallback.");
    Focus(pid);
  }
  public static void Capture(IntPtr window,uint pid,string path) {
    Owned(window,pid);Focus(pid);RECT r;
    if(!GetWindowRect(window,out r)||r.R-r.L<20||r.B-r.T<20||r.R-r.L>4096||r.B-r.T>4096)
      throw new InvalidOperationException("Unsafe owned capture dimensions.");
    using(var bitmap=new Bitmap(r.R-r.L,r.B-r.T))
    using(var graphics=Graphics.FromImage(bitmap)) {
      IntPtr dc=graphics.GetHdc();bool ok;
      try {ok=PrintWindow(window,dc,2);}finally {graphics.ReleaseHdc(dc);}
      if(!ok)throw new InvalidOperationException("Owned PrintWindow failed; no fabricated screenshot.");
      // A successful API call can still return a blank compositor surface.
      int first=bitmap.GetPixel(0,0).ToArgb();bool varied=false;
      for(int y=0;y<bitmap.Height;y+=16)for(int x=0;x<bitmap.Width;x+=16)
        if(bitmap.GetPixel(x,y).ToArgb()!=first)varied=true;
      if(!varied)throw new InvalidOperationException("Blank capture; screenshot UNVERIFIED.");
      bitmap.Save(path,ImageFormat.Png);
    }
  }
}
'@
  [InstalledFunctionalNative]::Desktop()
  $result.environment.interactive = $true
  Assert-Defender
  $result.environment.kind = 'clean-windows-vm'
  $script:phase = 'install'
  # Rehash immediately before execution; never unblock, elevate, or alter protection.
  if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSha256) {
    throw 'Installer changed since verification.'
  }
  $script:installStarted = $true
  $script:installer = Start-Process -FilePath $InstallerPath -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOCANCEL',
    "/DIR=`"$script:appDir`"", "/LOG=`"$(Join-Path $OutputDirectory 'install.log')`""
  ) -PassThru
  if (!$script:installer.WaitForExit(60000)) { throw 'Installer exceeded 60s; no success inferred.' }
  Assert-Defender
  if ($script:installer.ExitCode -ne 0) { throw "Installer exit $($script:installer.ExitCode)." }
  $script:exe = Join-Path $script:appDir 'bloomstep.exe'
  Assert-NoReparse $script:exe
  $bytes = [IO.File]::ReadAllBytes($script:exe)
  if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw 'Installed app is not PE.' }
  $pe = [BitConverter]::ToInt32($bytes,60)
  if ($pe -lt 64 -or $pe -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or
      [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw 'Installed app is not native x64 PE.' }
  if (@(Get-Process -Name bloomstep -ErrorAction SilentlyContinue).Count) { throw 'Unexpected app already running after silent install.' }
  $script:app = Start-Process -FilePath $script:exe -WorkingDirectory $script:appDir -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Assert-Time
    $script:app.Refresh()
    if ($script:app.HasExited) { throw 'Installed app exited before window readiness.' }
    if ($script:app.MainWindowHandle -ne 0) { break }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)
  $script:window = $script:app.MainWindowHandle
  [InstalledFunctionalNative]::Owned($script:window,[uint32]$script:app.Id)
  [void][InstalledFunctionalNative]::SetForegroundWindow($script:window)
  [InstalledFunctionalNative]::Focus([uint32]$script:app.Id)
  $script:root = [Windows.Automation.AutomationElement]::FromHandle($script:window)
  if ($script:root.Current.ProcessId -ne $script:app.Id) { throw 'UIA root PID mismatch.' }
  Probe 'FR-INSTALL' 'installed-launch' {
    [void](Wait-Control 'Plant a habit' 'Button')
    Save-Observation 'installed-launch'
  }
  # Exercise the reported clipboard regression before optional planting paths.
  Probe 'FR-PASTE' 'feedback-ctrl-v' {
    Invoke-Control 'Help us grow'
    $field = Wait-Control 'Your feedback' 'Edit'
    $value = $field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    if ($value.Current.IsReadOnly -or $value.Current.Value -ne '') { throw 'Feedback field not empty/editable; refusing overwrite.' }
    $field.SetFocus()
    Assert-Owned
    $focus = [Windows.Automation.AutomationElement]::FocusedElement
    if ($focus.Current.ProcessId -ne $script:app.Id -or
        ![Windows.Automation.Automation]::Compare($focus,$field)) { throw 'Exact feedback UIA focus not established; no keys sent.' }
    $text = 'Installed UIA clipboard ' + [Guid]::NewGuid().ToString('N')
    [InstalledFunctionalNative]::Clipboard($script:window,[uint32]$script:app.Id,$text)
    [InstalledFunctionalNative]::Paste([uint32]$script:app.Id)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
      Assert-Owned
      if ($value.Current.Value -ceq $text) { break }
      Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($value.Current.Value -cne $text) { throw 'Real Ctrl+V exact UIA readback failed; no setter/message fallback.' }
    Save-Observation 'feedback-ctrl-v'
    # Never send feedback or claim team receipt without an authorized account.
    Invoke-Control 'Close'
  }
  Probe 'FR-PLANT' 'suggested-plant' {
    Invoke-Control 'Plant a habit'
    Invoke-Control 'pour my morning drink'
    Invoke-Control 'Choose a tiny action'
    Invoke-Control 'take one slow breath'
    Invoke-Control 'Choose a celebration'
    Invoke-Control 'relax my shoulders and smile'
    Invoke-Control 'Plant this seed'
    [void](Wait-Control 'Your seed is planted')
    Save-Observation 'suggested-plant'
    Invoke-Control 'See my garden'
  }
  Probe 'FR-SEED-CARD' 'did-it-checkin' {
    Invoke-Control 'Did it'
    [void](Wait-Control 'Undo today' 'Button')
    Save-Observation 'did-it-checkin'
  }
  Probe 'FR-PLANT' 'custom-plant' {
    Invoke-Control 'Plant a habit'
    Set-Field 'After I...' 'installed UIA finish my test'
    Invoke-Control 'Choose a tiny action'
    Set-Field 'I will...' 'installed UIA take a breath'
    Invoke-Control 'Choose a celebration'
    Set-Field 'Then I celebrate by...' 'installed UIA smile'
    Invoke-Control 'Plant this seed'
    [void](Wait-Control 'Your seed is planted')
    Save-Observation 'custom-plant'
    Invoke-Control 'See my garden'
  }
  Probe 'FR-SETTINGS' 'settings-open' {
    Invoke-Control 'Settings and privacy'
    [void](Wait-Control 'Settings')
    Save-Observation 'settings-open'
    Invoke-Control 'Done'
  }
} catch {
  $script:failure = $_.Exception.Message
  $result.result = 'FAIL'
} finally {
  $cleanup = [Collections.Generic.List[string]]::new()
  try {
    if ($script:defenderInitialized) { Assert-Defender }
  } catch { $script:failure = "Defender final check: $($_.Exception.Message)"; $result.result = 'FAIL' }
  try { Stop-Owned $script:app $script:exe } catch { $cleanup.Add($_.Exception.Message) }
  try { Stop-Owned $script:installer $InstallerPath } catch { $cleanup.Add($_.Exception.Message) }
  # No recursive deletion, user-data cleanup, or deletion of unknown processes.
  # Uninstall only a completed installation's exact uninstaller; partial installs
  # are retained for diagnosis rather than executing possibly incomplete payloads.
  if ($script:installStarted -and $script:installer -and $script:installer.HasExited -and
      $script:installer.ExitCode -eq 0) {
    try {
      $uninstall = Join-Path $script:appDir 'unins000.exe'
      Assert-NoReparse $uninstall
      if (!(Test-Path -LiteralPath $uninstall -PathType Leaf)) { throw 'Owned uninstaller missing; scoped install retained.' }
      $script:uninstaller = Start-Process -FilePath $uninstall -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',
        "/LOG=`"$(Join-Path $OutputDirectory 'uninstall.log')`""
      ) -PassThru
      if (!$script:uninstaller.WaitForExit(30000)) { throw 'Owned uninstall exceeded 30s.' }
      if ($script:uninstaller.ExitCode -ne 0) { throw "Owned uninstall exit $($script:uninstaller.ExitCode)." }
    } catch {
      $cleanup.Add($_.Exception.Message)
      try { Stop-Owned $script:uninstaller $uninstall } catch { $cleanup.Add($_.Exception.Message) }
    }
  }
  if ($cleanup.Count) { $result.result = 'FAIL' }
  try {
    if ($script:defenderInitialized) { Assert-Defender }
  } catch { $script:failure = "Defender post-cleanup check: $($_.Exception.Message)"; $result.result = 'FAIL' }
  $result.phase = $script:phase
  $result.probes = @($script:checks.ToArray())
  $result['failure'] = $script:failure
  $result['cleanupErrors'] = @($cleanup.ToArray())
  $result['retainedUserData'] = 'Disposable runner profile data intentionally not deleted; never reuse this VM for another run.'
  $prefix = "release/evidence/$CandidateCommit/functional/"
  if ($contract) {
    $result.tests = @($contract.requirements | ForEach-Object {
      $requirement = $_
      $observations = @($script:checks | Where-Object { $_.requirement -eq $requirement.id })
      $verdict = if (@($observations | Where-Object { $_.result -eq 'FAIL' }).Count) { 'FAIL' } else { 'UNVERIFIED' }
      $log = "$($requirement.id).log"
      @("Requirement: $($requirement.id)", "Result: $verdict",
        'Full requirement not established; probe PASS is only a partial observation.',
        "Interrupted phase: $script:phase", "Harness failure: $script:failure",
        ($observations | ConvertTo-Json -Depth 6), ($result.blockers -join "`n")) |
        Set-Content -LiteralPath (Join-Path $OutputDirectory $log) -Encoding UTF8
      [ordered]@{id="installed-$($requirement.id)"; requirement=$requirement.id; result=$verdict;
        log=$prefix+$log; screenshots=@{}; baselineResult='UNVERIFIED'}
    })
  }
  # Windows PowerShell's Set-Content -Encoding UTF8 adds a BOM, which the Node
  # release verifier's JSON.parse does not accept.
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'results.json'),
    ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
  @(
    '# Installed Windows functional observations — NOT release acceptance',
    "Candidate: $CandidateCommit", "Expected installer SHA-256: $ExpectedSha256",
    "Run/artifact: $RunId / $ArtifactId", "Overall: $($result.result)",
    "Phase: $script:phase", "Failure: $script:failure",
    'Copy the entire pack without edits under release/evidence/<candidate>/functional/ only after review.',
    'results.json intentionally fails the release gate. No requirement or baseline FAIL was invented.',
    'Actual owned-window captures are *-observed.png, not authenticated light/dark pairs.',
    'Install/uninstall logs and per-requirement logs are retained even on failure.',
    ($result.blockers -join "`n"), ($cleanup -join "`n")
  ) | Set-Content -LiteralPath (Join-Path $OutputDirectory 'README.md') -Encoding UTF8
}
# A subset-only run is never a successful release-functional run.
exit 1
