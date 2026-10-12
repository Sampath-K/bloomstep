param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Test-Path -LiteralPath $Output) { throw 'Use a new isolated fixture output directory.' }
$sdk = Get-ChildItem -LiteralPath "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory |
  Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
  Sort-Object { [version]$_.Name } -Descending |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64\makeappx.exe') } |
  Select-Object -First 1
if (-not $sdk) { throw 'Windows SDK is required.' }
$makeappx = Join-Path $sdk.FullName 'x64\makeappx.exe'
$signtool = Join-Path $sdk.FullName 'x64\signtool.exe'
function Invoke-Checked([string]$File, [string[]]$Arguments) {
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$File failed (exit $LASTEXITCODE)." }
}
New-Item -ItemType Directory -Path $Output | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security.Cryptography.Pkcs
$rsa = [Security.Cryptography.RSA]::Create(2048)
$request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
  'CN=Bloomstep isolated packaging fixture', $rsa,
  [Security.Cryptography.HashAlgorithmName]::SHA256,
  [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$usages = [Security.Cryptography.OidCollection]::new()
[void]$usages.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
$request.CertificateExtensions.Add(
  [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($usages, $true))
$request.CertificateExtensions.Add(
  [Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
    [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
$certificate = $request.CreateSelfSigned(
  [DateTimeOffset]::UtcNow.AddMinutes(-1), [DateTimeOffset]::UtcNow.AddHours(1))
$pfx = Join-Path $Output 'ephemeral-fixture.pfx'
try {
  [IO.File]::WriteAllBytes($pfx, $certificate.Export(
    [Security.Cryptography.X509Certificates.X509ContentType]::Pfx))
  foreach ($version in @('0.1.0-preview.13', '0.1.0-preview.14')) {
    $packages = New-Item -ItemType Directory -Path (Join-Path $Output "$version-packages")
    foreach ($arch in @('x64', 'arm64')) {
      $stage = Join-Path $Output "$version-$arch"
      Invoke-Checked 'node' @('tool\msix_update.mjs', $stage, $version, $certificate.Subject, $arch)
      # This payload is deliberately non-executable: SDK/signature proof is not launch proof.
      [IO.File]::WriteAllText((Join-Path $stage 'bloomstep.exe'), 'INERT FIXTURE - NEVER INSTALL OR EXECUTE')
      Move-Item -LiteralPath (Join-Path $stage 'Bloomstep.appinstaller') -Destination (Join-Path $Output "$version-$arch.appinstaller")
      $assets = New-Item -ItemType Directory -Path (Join-Path $stage 'Assets')
      foreach ($item in @(@('StoreLogo', 50), @('Logo44', 44), @('Logo150', 150))) {
        $image = New-Object Drawing.Bitmap -ArgumentList ([int]$item[1]), ([int]$item[1])
        try {
          $image.Save((Join-Path $assets.FullName "$($item[0]).png"), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $image.Dispose() }
      }
      $package = Join-Path $packages.FullName "Bloomstep-$arch.msix"
      Invoke-Checked $makeappx @('pack', '/d', $stage, '/p', $package, '/o')
      Invoke-Checked $signtool @('sign', '/fd', 'SHA256', '/f', $pfx, $package)
    }
    $bundle = Join-Path $Output "$version.msixbundle"
    Invoke-Checked $makeappx @('bundle', '/d', $packages.FullName, '/p', $bundle, '/o')
    Invoke-Checked $signtool @('sign', '/fd', 'SHA256', '/f', $pfx, $bundle)
    $unpacked = Join-Path $Output "$version-unpacked"
    Invoke-Checked $makeappx @('unbundle', '/p', $bundle, '/d', $unpacked, '/o')
    $zip = [IO.Compression.ZipFile]::OpenRead($bundle)
    try {
      $stream = $zip.GetEntry('AppxSignature.p7x').Open()
      $memory = [IO.MemoryStream]::new()
      try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
      $signature = $memory.ToArray()
      $memory.Dispose()
      $cms = [Security.Cryptography.Pkcs.SignedCms]::new()
      $cms.Decode([byte[]]$signature[4..($signature.Length - 1)])
      $cms.CheckSignature($true)
      if ($cms.SignerInfos[0].Certificate.Thumbprint -ne $certificate.Thumbprint) {
        throw 'Fixture publisher signature mismatch.'
      }
    } finally { $zip.Dispose() }
    & $signtool verify /pa $bundle 2>&1 | Out-File (Join-Path $Output "$version-trust-rejection.txt")
    if ($LASTEXITCODE -eq 0) { throw 'An unprovisioned fixture publisher must not be trusted.' }
    $rejection = Get-Content -LiteralPath (Join-Path $Output "$version-trust-rejection.txt") -Raw
    if ($rejection -notmatch 'not trusted|untrusted') {
      throw 'Signature validation failed for a reason other than expected absent publisher trust.'
    }
  }
  [ordered]@{
    schema = 1; versions = @('0.1.0-preview.13', '0.1.0-preview.14')
    nativeArchitectures = @('x64', 'arm64'); sdkSchemaAndBundle = 'PASS'
    ephemeralPublisherSignature = 'PASS'; unprovisionedPublisherRejected = 'PASS'
    privateKeyPersisted = $false; installed = $false; appLaunch = 'NOT TESTED'
    automaticApplication = 'NOT TESTED'; dataMigration = 'NOT TESTED'
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'packaging-proof.json') -Encoding utf8
  # The last native command intentionally rejected the untrusted certificate.
  # Only reset its exit status after all expected-rejection assertions pass.
  $global:LASTEXITCODE = 0
} finally {
  if (Test-Path -LiteralPath $pfx) { Remove-Item -LiteralPath $pfx }
  $certificate.Dispose()
  $rsa.Dispose()
}
