param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [Parameter(Mandatory=$true)][string]$Target
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
  throw 'Legacy receipt privacy proof is restricted to disposable CI.'
}
$root = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
$Target = [IO.Path]::GetFullPath($Target)
if (-not $Target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path $Target)) {
  throw 'Privacy proof requires a new isolated runner target.'
}
. "$PSScriptRoot\universal_integrity_contract.ps1"
if (-not (Test-BloomstepInnoProductName (Get-Item $Installer).VersionInfo.ProductName)) {
  throw 'Privacy proof requires the genuine compiled Bloomstep package.'
}
$receipt = Join-Path $env:LOCALAPPDATA 'Bloomstep\measurement\installer-receipt.json'
if ((Test-Path $receipt) -or (Test-Path ($receipt + '.pending'))) {
  throw 'Privacy proof refuses existing installer receipts.'
}
$EvidenceDir = Join-Path $env:RUNNER_TEMP 'disabled-installer-observations-proof'
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $Installer -EvidenceDir $EvidenceDir
$owner = [guid]::NewGuid().ToString()
$synthetic = '{"schemaVersion":1,"source":"installer","consentedAt":"' + [DateTime]::UtcNow.ToString('o') +
  '","events":[{"id":"' + $owner + '","name":"installer_started","ts":"' + [DateTime]::UtcNow.ToString('o') + '"}]}'
$report = [ordered]@{ kind = 'isolated-legacy-receipt-privacy-not-app-acceptance';
  source = (git rev-parse HEAD); installerSha256 = (Get-FileHash $Installer).Hash.ToLower(); outcome = 'running' }
function Install-PrivacyFixture([string]$Stage) {
  $process = Start-CaptureProcess $Installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$Target`"" $Stage
  Wait-CaptureTree $Stage
  if ($process.ExitCode -ne 0 -or -not (Test-Path "$Target\bloomstep.exe")) { throw 'Privacy proof silent install failed.' }
  if (Test-Path "$Target\measurement-owner.txt") { throw 'Installer observations must not exist: new owner marker.' }
}
function Uninstall-PrivacyFixture([string]$Stage) {
  $process = Start-CaptureProcess "$Target\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' $Stage
  Wait-CaptureTree $Stage
  if ($process.ExitCode -ne 0 -or (Test-Path "$Target\bloomstep.exe")) { throw 'Privacy proof owned uninstall failed.' }
}
try {
  Install-PrivacyFixture 'silent-install-no-observations'
  if (Test-Path $receipt) { throw 'Installer observations must not exist: silent receipt.' }
  $report.silentNoObservations = $true
  New-Item -ItemType Directory -Path (Split-Path $receipt) -Force | Out-Null
  [IO.File]::WriteAllText($receipt, $synthetic)
  [IO.File]::WriteAllText("$Target\measurement-owner.txt", $owner)
  Install-PrivacyFixture 'upgrade-removes-old-owner-does-not-adopt-consent'
  if ([IO.File]::ReadAllText($receipt) -ne $synthetic) { throw 'Legacy unmatched receipt changed during upgrade.' }
  Uninstall-PrivacyFixture 'upgraded-uninstall-unmatched-receipt'
  if ([IO.File]::ReadAllText($receipt) -ne $synthetic) { throw 'Legacy unmatched receipt changed during uninstall.' }
  $report.upgradeClearsOwnerAndPreservesLegacyReceipt = $true
  Remove-Item -LiteralPath $receipt
  Install-PrivacyFixture 'legacy-matched-uninstall-setup'
  [IO.File]::WriteAllText($receipt, $synthetic)
  [IO.File]::WriteAllText($receipt + '.pending', $synthetic)
  [IO.File]::WriteAllText("$Target\measurement-owner.txt", $owner)
  Uninstall-PrivacyFixture 'legacy-matched-uninstall'
  if (Test-Path $receipt) { throw 'Owned uninstall did not remove the installer receipt.' }
  if (Test-Path ($receipt + '.pending')) { throw 'Legacy pending receipt was not removed by owned uninstall.' }
  $report.matchedLegacyReceiptAndPendingRemoved = $true
  Install-PrivacyFixture 'legacy-mismatched-uninstall-setup'
  [IO.File]::WriteAllText($receipt, $synthetic)
  [IO.File]::WriteAllText("$Target\measurement-owner.txt", [guid]::NewGuid().ToString())
  Uninstall-PrivacyFixture 'legacy-mismatched-uninstall'
  if ([IO.File]::ReadAllText($receipt) -ne $synthetic) { throw 'Legacy unmatched receipt changed by another owner uninstall.' }
  $report.unmatchedLegacyReceiptPreserved = $true
  $report.outcome = 'verified-legacy-privacy-and-zero-new-installer-observations'
} finally {
  try {
    Stop-CaptureTree
    if (Test-Path "$Target\unins000.exe") { Uninstall-PrivacyFixture 'finally-uninstall' }
    foreach ($file in @($receipt, ($receipt + '.pending'))) {
      if ((Test-Path $file) -and [IO.File]::ReadAllText($file) -eq $synthetic) { Remove-Item -LiteralPath $file }
    }
  } finally {
    try { Stop-CaptureTree }
    finally { $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceDir 'privacy-proof.json') -Encoding utf8 }
  }
}
