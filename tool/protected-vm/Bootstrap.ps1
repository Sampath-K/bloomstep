param([switch]$Resume)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $PSScriptRoot
$state = Join-Path $root 'state'
$receipt = $null
try {
  if ($env:OS -ne 'Windows_NT') { throw 'Run only inside the dedicated disposable Windows Hyper-V VM.' }
  . "$root\Bootstrap.Common.ps1"
  $manifest = Assert-PackageInventory $root
  New-Item -ItemType Directory -Force -Path $state | Out-Null
  $native = $env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $native = $env:PROCESSOR_ARCHITEW6432 }
  $arch = switch ($native) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { throw 'Only native x64/ARM64 Windows guests are supported.' } }
  $receipt = New-BootstrapReceipt 'Checking' $manifest.source $arch
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
      @($identity.Groups | ForEach-Object Value) -contains 'S-1-5-32-544') {
    throw 'Start as a true standard user, never an administrator or filtered admin token. No runner will start.'
  }
  Confirm-Bootstrap 'Dedicated disposable Hyper-V guest, no customer data, corporate DevBox/IT approval obtained if applicable?' 'PREPARE VM'
  $env:BLOOMSTEP_DISPOSABLE_VM = 'true'
  & "$root\harness\setup_defender_test_vm.ps1" -Mode Check -EvidenceDir (Join-Path $state 'preflight')
  if (-not $?) { throw 'Existing protected VM preflight failed.' }
  foreach ($path in @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'),
    (Join-Path $env:LOCALAPPDATA 'Bloomstep'),
    (Join-Path $env:APPDATA 'Bloomstep'),
    'HKCU:\Software\Classes\bloomstep'
  )) {
    if (Test-Path -LiteralPath $path) { throw 'Existing product state; restore the clean checkpoint. Nothing is deleted.' }
  }
  if (Get-Process -Name bloomstep -ErrorAction SilentlyContinue) { throw 'Existing product process; restore the clean checkpoint.' }
  if ($Resume) { Write-Output 'Resume revalidates protection, source and dependencies; no prior approval is reused.' }
  $checkpointFile = Join-Path $state 'checkpoint.json'
  if (-not (Test-Path -LiteralPath $checkpointFile)) {
    $checkpoint = Read-Host 'Create a clean checkpoint in Hyper-V Manager on the HOST, then enter its name here (not a password)'
    if ([string]::IsNullOrWhiteSpace($checkpoint)) { throw 'A clean host checkpoint is required before setup.' }
    @{ operatorAttested = $true; name = $checkpoint; source = $manifest.source } |
      ConvertTo-Json | Set-Content -LiteralPath $checkpointFile -Encoding utf8
  }
  $assets = (Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json).assets
  Confirm-Bootstrap 'Download/check pinned portable PowerShell, Git and Node into this package only?' 'PREPARE TOOLS'
  $toolPaths = @{}
  foreach ($tool in @('pwsh', 'git', 'node')) {
    $asset = $assets.("$tool-$arch")
    $archive = Get-PinnedDownload $asset (Join-Path $state 'downloads')
    $destination = Join-Path $state "tools\$tool-$arch"
    Expand-VerifiedPortable $archive $destination
    $executable = Join-Path $destination $asset.executable
    if (-not (Test-Path -LiteralPath $executable)) { throw 'Portable tool archive lacks its pinned expected executable.' }
    $toolPaths[$tool] = $executable
    $env:PATH = (Split-Path $executable) + [IO.Path]::PathSeparator + $env:PATH
  }
  $pwshVersion = & $toolPaths.pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
  if ($LASTEXITCODE -ne 0 -or $pwshVersion -ne '7.6.7') { throw 'Pinned portable PowerShell version check failed.' }
  $gitVersion = & $toolPaths.git --version
  if ($LASTEXITCODE -ne 0 -or $gitVersion -ne 'git version 2.56.0.windows.2') { throw 'Pinned portable Git version check failed.' }
  $nodeVersion = & $toolPaths.node --version
  if ($LASTEXITCODE -ne 0 -or $nodeVersion -ne 'v22.23.3') { throw 'Pinned portable Node version check failed.' }
  $inno = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
  if (-not (Test-Path -LiteralPath $inno)) {
    $receipt.stage = 'DependencySetupRequired'
    $receipt.nextAction = 'Approve the separate dependency-only UAC window, install Inno, close it, restart if requested, then rerun this same script -Resume as STANDARD user.'
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'bootstrap-receipt.json') -Encoding utf8
    Confirm-Bootstrap 'Open a separate UAC administrator window ONLY to install pinned Inno? It will not run the runner.' 'OPEN DEPENDENCY SETUP'
    $shell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $helper = Join-Path $root 'Install-Inno.ps1'
    $child = Start-Process -FilePath $shell -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -File `"$helper`" -PackageRoot `"$root`""
    if ($child.ExitCode -ne 0) { throw 'Dependency setup did not complete. Inspect dependency-receipt.json locally.' }
    Write-Output $receipt.nextAction
    exit 2
  }
  $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not (Test-Path -LiteralPath $csc)) { throw 'Required Windows .NET Framework compiler missing; use a supported Windows image.' }
  . "$root\harness\inno_compiler_version.ps1"
  $engineOutput = & $inno (Join-Path $root 'harness\inno-toolchain-probe.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Compile-only Inno engine probe failed.' }
  $version = Get-InnoEngineVersion @($engineOutput)
  if ($version -ne [version]'6.7.1') { throw 'Inno engine differs from pinned 6.7.1. Do not overwrite it silently; restore the clean checkpoint.' }
  & "$root\harness\setup_defender_test_vm.ps1" -Mode Check -EvidenceDir (Join-Path $state 'preflight-after')
  if (-not $?) { throw 'Post-setup protection preflight failed.' }
  $receipt.stage = 'TrustBlocked'
  $receipt.nextAction = 'Return state/bootstrap-receipt.json and preflight receipts to the coordinator. Public-repo runner access is NOT restricted to a reviewed workflow/ref. Do NOT register or run a runner. Await an independently verifiable enforceable restriction; a yes, label, queue audit or ephemeral flag is insufficient.'
  $receipt.tools = @{ powershell = '7.6.7'; git = '2.56.0.2'; node = '22.23.3'; inno = $version.ToString() }
  Write-Output 'Prerequisites prepared. NOT complete: registration and execution remain blocked.'
  Write-Output $receipt.nextAction
  exit 3
} catch {
  if ($null -ne $receipt) {
    $receipt.stage = 'Failed'
    $receipt.nextAction = 'STOP. Read the local error, resolve the stated prerequisite without bypassing policy/protection, then rerun Bootstrap.ps1 -Resume. Share sanitized receipts only, never credentials.'
  }
  Write-Error $_
  exit 1
} finally {
  if ($null -ne $receipt) {
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $state 'bootstrap-receipt.json') -Encoding utf8
    Write-Output "Sanitized status: $state\bootstrap-receipt.json"
  }
}
