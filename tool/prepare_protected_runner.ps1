param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('x64', 'arm64')][string]$ExpectedArch,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedSource,
  [string]$EvidenceDir = (Join-Path $env:TEMP 'bloomstep-runner-readiness')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
  throw 'Run in PowerShell 7 on the disposable Windows guest, not the owner host.'
}
if ((Read-Host 'Type CHECK DISPOSABLE VM to authorize readiness checks only') -cne 'CHECK DISPOSABLE VM') {
  throw 'Readiness checks were not authorized.'
}
if ($env:BLOOMSTEP_DISPOSABLE_VM -ne 'true') {
  throw 'Explicitly mark the disposable guest before checking it.'
}
foreach ($command in @('git', 'node', 'pwsh')) {
  Get-Command $command -ErrorAction Stop | Out-Null
}
$root = Split-Path $PSScriptRoot
$source = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $source -ne $ExpectedSource) {
  throw 'Checkout does not match the independently reviewed source SHA.'
}
$dirty = & git -C $root status --porcelain
if ($LASTEXITCODE -ne 0 -or $dirty) {
  throw 'Readiness requires an unmodified reviewed checkout.'
}
$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($arch -ne $ExpectedArch) { throw 'Native OS architecture does not match the required job.' }
$nodeVersion = & node --version
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 22) {
  throw 'Preinstall supported Node.js 22 or newer before checking readiness.'
}
$inno = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path -LiteralPath $inno)) {
  throw 'Preinstall Inno Setup 6.7.1 at the path used by ci.yml.'
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw 'The workflow requires the Windows .NET Framework compiler.' }
foreach ($path in @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'),
  (Join-Path $env:LOCALAPPDATA 'Bloomstep'),
  (Join-Path $env:APPDATA 'Bloomstep'),
  'HKCU:\Software\Classes\bloomstep'
)) {
  if (Test-Path -LiteralPath $path) { throw 'Existing Bloomstep state: restore a clean checkpoint, do not delete data.' }
}
if (Get-Process -Name bloomstep -ErrorAction SilentlyContinue) {
  throw 'Existing Bloomstep process: restore a clean checkpoint.'
}
& "$PSScriptRoot\setup_defender_test_vm.ps1" -Mode Check -EvidenceDir $EvidenceDir
if (-not $?) { throw 'Existing protected-VM preflight failed.' }
$receipt = Get-Content -LiteralPath (Join-Path $EvidenceDir 'vm-security-receipt.json') -Raw | ConvertFrom-Json
if ($receipt.result -ne 'PREFLIGHT PASS ONLY; no installer or app execution') {
  throw 'Existing protected-VM preflight did not attest readiness.'
}
. "$PSScriptRoot\inno_compiler_version.ps1"
$engineOutput = & $inno (Join-Path $root 'packaging\inno-toolchain-probe.iss')
if ($LASTEXITCODE -ne 0) { throw 'Compile-only Inno toolchain probe failed.' }
$compiler = Get-InnoEngineVersion @($engineOutput)
if ($compiler -ne [version]'6.7.1') { throw 'Expected reviewed Inno Setup engine 6.7.1.' }
[ordered]@{
  source = $source
  nativeOSArchitecture = $arch
  nodeVersion = $nodeVersion
  powershellVersion = $PSVersionTable.PSVersion.ToString()
  innoVersion = $compiler.ToString()
  result = 'READINESS ONLY; registration, dispatch and installer execution NOT authorized'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'runner-readiness.json') -Encoding utf8
Write-Output "Readiness receipts: $EvidenceDir"
Write-Output 'STOP. Review docs/protected-runner-operator.md before any separate registration or execution.'
