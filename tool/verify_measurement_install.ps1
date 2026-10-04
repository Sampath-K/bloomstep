param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$Target
)
$ErrorActionPreference = 'Stop'
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
if (Test-Path $receipt) { throw 'Synthetic installer verification refuses to replace an existing receipt.' }
if (Test-Path $Target) { throw 'Synthetic installer target must not already exist.' }
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class MeasurementWizard {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr x);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr x);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder b, int c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static IntPtr[] Windows() {
    var a = new List<IntPtr>();
    EnumWindows((h,p) => { if (IsWindowVisible(h)) a.Add(h); return true; }, IntPtr.Zero);
    return a.ToArray();
  }
  public static IntPtr Find(IntPtr owner, string caption) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(owner,(h,p) => {
      var b = new StringBuilder(512); GetWindowText(h,b,512);
      if (IsWindowVisible(h) && IsWindowEnabled(h) &&
          b.ToString().Replace("&","").Trim() == caption.Replace("&","").Trim()) found=h;
      return true;
    },IntPtr.Zero);
    return found;
  }
  public static string Describe(IntPtr owner) {
    var texts = new List<string>();
    var title = new StringBuilder(512); GetWindowText(owner,title,512);
    texts.Add("Window: " + title.ToString());
    EnumChildWindows(owner,(h,p) => {
      var text = new StringBuilder(1024); GetWindowText(h,text,1024);
      if (IsWindowVisible(h) && text.Length > 0)
        texts.Add((IsWindowEnabled(h) ? "enabled " : "disabled ") + text.ToString());
      return true;
    },IntPtr.Zero);
    return string.Join(" | ",texts);
  }
}
'@
$setup = Start-Process $Installer -ArgumentList "/SP- /NORESTART /DIR=`"$Target`"" -PassThru
$owned = [Collections.Generic.HashSet[int]]::new()
[void]$owned.Add($setup.Id)
$selected = $false
$finished = $false
$appId = $null
$states = [Collections.Generic.HashSet[string]]::new()
try {
  $deadline = (Get-Date).AddMinutes(3)
  while ((Get-Date) -lt $deadline -and -not $finished) {
    $processes = Get-CimInstance Win32_Process
    for ($i=0; $i -lt 5; $i++) {
      foreach ($process in $processes) {
        if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
      }
    }
    foreach ($window in [MeasurementWizard]::Windows()) {
      [uint32]$owner = 0
      [void][MeasurementWizard]::GetWindowThreadProcessId($window, [ref]$owner)
      if (-not $owned.Contains([int]$owner)) { continue }
      $description = [MeasurementWizard]::Describe($window)
      if ($states.Add($description)) { Write-Output "Owned synthetic installer PID${owner}: $description" }
      $checkbox = [MeasurementWizard]::Find($window, 'Save optional local observations (unchecked by default)')
      if ($checkbox -ne [IntPtr]::Zero -and -not $selected) {
        if ([MeasurementWizard]::SendMessage($checkbox, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -ne 0) {
          throw 'Installer observation consent was not default-off.'
        }
        [void][MeasurementWizard]::SendMessage($checkbox, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        if ([MeasurementWizard]::SendMessage($checkbox, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -ne 1) {
          throw 'Owned synthetic installer checkbox did not record explicit selection.'
        }
        $selected = $true
      }
      foreach ($caption in @('&Next >','&Install','&Finish','Finish')) {
        $button = [MeasurementWizard]::Find($window, $caption)
        if ($button -eq [IntPtr]::Zero) { continue }
        if ($caption -match 'Finish') {
          if (-not $selected) { throw 'Optional consent page was not exercised.' }
          $finished = $true
        }
        [void][MeasurementWizard]::SendMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 300
        break
      }
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $finished) {
    Write-Output "Owned synthetic PID tree: $(@($owned) -join ','); distinct wizard states: $($states.Count)"
    throw 'Owned installer wizard did not complete within its deadline.'
  }
  if (-not (Test-Path $receipt)) { throw 'Opt-in installation phase did not produce a receipt.' }
  $installed = Get-Content $receipt -Raw | ConvertFrom-Json
  if ($installed.schemaVersion -ne 1 -or $installed.source -ne 'installer') { throw 'Invalid installer receipt envelope.' }
  if ($installed.events[0].name -ne 'installer_started' -or $installed.events[1].name -ne 'install_completed') { throw 'Actual installation observations missing.' }
  $marker = Get-Content (Join-Path $Target 'measurement-owner.txt') -Raw
  if ($marker -ne $installed.events[0].id) { throw 'Installation receipt ownership marker differs.' }
  $executable = Join-Path $Target 'bloomstep.exe'
  Start-Sleep -Seconds 2
  $app = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $executable } | Select-Object -First 1
  if ($null -eq $app) { $launched = Start-Process $executable -PassThru; $appId = $launched.Id }
  else { $appId = [int]$app.ProcessId }
  $deadline = (Get-Date).AddSeconds(45)
  do {
    Start-Sleep -Milliseconds 500
    $observed = Get-Content $receipt -Raw | ConvertFrom-Json
    $names = @($observed.events | ForEach-Object name)
  } while (($names -notcontains 'signin_view') -and (Get-Date) -lt $deadline)
  if (($names -join ',') -ne 'installer_started,install_completed,first_launch,signin_view') {
    throw 'Genuine installed entry/sign-in observations are incomplete or duplicated.'
  }
  foreach ($event in $observed.events) {
    if ((($event.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'id,name,ts') { throw 'Unexpected private measurement field.' }
    if ($event.id -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { throw 'Observation ID is not a random UUIDv4.' }
  }
  Stop-Process -Id $appId
  $appId = $null
  Start-Process (Join-Path $Target 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
  if (Test-Path $receipt) { throw 'Owned uninstall did not remove the installer receipt.' }
  if (Test-Path $executable) { throw 'Synthetic measurement installation did not uninstall.' }
  Write-Output 'Actual default-off wizard, explicit synthetic selection, installation/entry observations and owned receipt uninstall passed. No customer or cohort evidence.'
} finally {
  if ($null -ne $appId -and (Get-Process -Id $appId -ErrorAction SilentlyContinue)) { Stop-Process -Id $appId }
  foreach ($id in $owned) {
    if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id }
  }
}
