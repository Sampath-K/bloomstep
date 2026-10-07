param(
  [Parameter(Mandatory)][string]$Artifacts,
  [Parameter(Mandatory)][string]$Version,
  [Parameter(Mandatory)][string]$SourceSha,
  [Parameter(Mandatory)][string]$Publisher,
  [string]$CertificateThumbprint,
  [Parameter(Mandatory)][string]$Output,
  [switch]$UnsignedValidationOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked([string]$File, [string[]]$Arguments) {
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$File failed (exit $LASTEXITCODE)." }
}

# All outputs are new candidate artifacts. Never overwrite an installed app or release.
if (Test-Path -LiteralPath $Output) { throw 'MSIX output must be a new directory.' }
if ($UnsignedValidationOnly) {
  if ($CertificateThumbprint) { throw 'Unsigned validation must not use a signing identity.' }
} else {
  if (-not $CertificateThumbprint -or $Version.EndsWith('-preview')) {
    throw 'Production candidate signing requires an approved certificate and a numbered release version.'
  }
  $cert = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint"
  if (-not $cert.HasPrivateKey -or $cert.Subject -cne $Publisher -or
      $cert.NotAfter -le (Get-Date) -or $cert.NotBefore -gt (Get-Date) -or
      -not ($cert.EnhancedKeyUsageList.ObjectId.Value -contains '1.3.6.1.5.5.7.3.3')) {
    throw 'An existing valid approved code-signing certificate and private key are required.'
  }
}
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory |
  Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
  Sort-Object { [version]$_.Name } -Descending |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64\makeappx.exe') } |
  Select-Object -First 1
if (-not $sdk) { throw 'Windows SDK MakeAppx/SignTool are required.' }
$makeappx = Join-Path $sdk.FullName 'x64\makeappx.exe'
$signtool = Join-Path $sdk.FullName 'x64\signtool.exe'

foreach ($arch in @('x64', 'arm64')) {
  $root = Join-Path $Artifacts "bloomstep-windows-$arch\build\windows\$arch\runner\Release"
  $receipt = Join-Path $Artifacts "bloomstep-windows-$arch\release-output\payload-manifest-$arch.json"
  Invoke-Checked 'node' @('tool\release_payload.mjs', 'verify', $root, $receipt, $arch, $SourceSha, $Version)
  $binary = [IO.File]::ReadAllBytes((Join-Path $root 'bloomstep.exe'))
  $machine = [BitConverter]::ToUInt16($binary, [BitConverter]::ToInt32($binary, 60) + 4)
  $expected = if ($arch -eq 'arm64') { 0xaa64 } else { 0x8664 }
  if ($machine -ne $expected) { throw "Wrong native architecture: $arch" }
}

New-Item -ItemType Directory -Path $Output | Out-Null
$packages = New-Item -ItemType Directory -Path (Join-Path $Output 'packages')
Add-Type -AssemblyName System.Drawing
foreach ($arch in @('x64', 'arm64')) {
  $root = Join-Path $Artifacts "bloomstep-windows-$arch\build\windows\$arch\runner\Release"
  $stage = Join-Path $Output "stage-$arch"
  New-Item -ItemType Directory -Path $stage | Out-Null
  Get-ChildItem -LiteralPath $root | Copy-Item -Destination $stage -Recurse
  Invoke-Checked 'node' @('tool\msix_update.mjs', $stage, $Version, $Publisher, $arch)
  # Feed is outside the payload: enrollment must use the .appinstaller, not bare MSIX.
  Move-Item -LiteralPath (Join-Path $stage 'Bloomstep.appinstaller') -Destination (Join-Path $Output "Bloomstep-$arch.appinstaller")
  $assets = New-Item -ItemType Directory -Path (Join-Path $stage 'Assets')
  $original = [Drawing.Image]::FromFile((Join-Path $PWD 'site\assets\bloomstep-icon.png'))
  try {
    foreach ($item in @(@('StoreLogo', 50), @('Logo44', 44), @('Logo150', 150))) {
      $image = New-Object Drawing.Bitmap -ArgumentList ([int]$item[1]), ([int]$item[1])
      $graphics = [Drawing.Graphics]::FromImage($image)
      try {
        $graphics.DrawImage($original, 0, 0, [int]$item[1], [int]$item[1])
        $image.Save((Join-Path $assets.FullName "$($item[0]).png"), [Drawing.Imaging.ImageFormat]::Png)
      } finally { $graphics.Dispose(); $image.Dispose() }
    }
  } finally { $original.Dispose() }
  $package = Join-Path $packages.FullName "Bloomstep-$arch.msix"
  Invoke-Checked $makeappx @('pack', '/d', $stage, '/p', $package, '/o')
  if (-not $UnsignedValidationOnly) {
    Invoke-Checked $signtool @('sign', '/fd', 'SHA256', '/sha1', $CertificateThumbprint, $package)
    Invoke-Checked $signtool @('verify', '/pa', '/v', $package)
  }
}
$bundle = Join-Path $Output "Bloomstep-$Version.msixbundle"
Invoke-Checked $makeappx @('bundle', '/d', $packages.FullName, '/p', $bundle, '/o')
if (-not $UnsignedValidationOnly) {
  Invoke-Checked $signtool @('sign', '/fd', 'SHA256', '/sha1', $CertificateThumbprint, $bundle)
  Invoke-Checked $signtool @('verify', '/pa', '/v', $bundle)
}
$x64Feed = Join-Path $Output 'Bloomstep-x64.appinstaller'
$armFeed = Join-Path $Output 'Bloomstep-arm64.appinstaller'
if ((Get-FileHash $x64Feed).Hash -ne (Get-FileHash $armFeed).Hash) {
  throw 'Architecture feeds disagree on publisher, channel or version.'
}
Move-Item -LiteralPath $x64Feed -Destination (Join-Path $Output 'Bloomstep.appinstaller')
Remove-Item -LiteralPath $armFeed
[ordered]@{
  schema = 1; source = $SourceSha; version = $Version; publisher = $Publisher
  certificate = $CertificateThumbprint; sha256 = (Get-FileHash $bundle).Hash.ToLower()
  signatureStatus = if ($UnsignedValidationOnly) { 'UNSIGNED-SDK-VALIDATION-ONLY' } else { 'Windows trust verified' }
  enrollment = 'Install using Bloomstep.appinstaller; bare MSIX does not enroll.'
  installedUpgrade = 'UNVERIFIED'; migration = 'UNVERIFIED'; productionActivated = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'candidate-receipt.json') -Encoding utf8
