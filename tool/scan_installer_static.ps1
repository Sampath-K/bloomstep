param(
  [Parameter(Mandatory)][string]$PackageDir
)
$ErrorActionPreference = 'Stop'
$manifest = Get-Content (Join-Path $PackageDir 'universal-manifest.json') -Raw | ConvertFrom-Json
$installer = Join-Path $PackageDir $manifest.installerFile
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLower()
if ($manifest.source -ne (git rev-parse HEAD) -or $hash -ne $manifest.installerSha256) {
  throw 'Static scan package source/hash mismatch.'
}
$receipt = [ordered]@{
  kind = 'defender-static-scan-not-runtime-acceptance-v1'
  source = $manifest.source
  installerSha256 = $hash
  installerExecuted = $false
  outcome = 'UNVERIFIED'
  reason = $null
  exitCode = $null
  antivirusSignatureVersion = $null
}
try {
  if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Static scan requires a GitHub-hosted Windows worker.'
  }
  $command = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
  if (-not $command) {
    $receipt.reason = 'Defender status command unavailable on hosted worker.'
  } else {
    $status = Get-MpComputerStatus
    $receipt.antivirusSignatureVersion = $status.AntivirusSignatureVersion
    if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) {
      $receipt.reason = 'Defender antivirus/service unavailable on hosted worker.'
    } else {
      $scanner = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
      if (-not (Test-Path -LiteralPath $scanner)) {
        $receipt.reason = 'MpCmdRun executable unavailable on hosted worker.'
      } else {
        & $scanner -Scan -ScanType 3 -File $installer -DisableRemediation
        $receipt.exitCode = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) {
          throw "Defender static scan returned $LASTEXITCODE; detection or scan error, not a clean result."
        }
        $receipt.outcome = 'STATIC_SCAN_COMPLETED_NO_THREATS_REPORTED'
        $receipt.reason = 'Static result only; does not override prior behavior detection or establish runtime safety.'
      }
    }
  }
} catch {
  $receipt.outcome = 'FAILED'
  $receipt.reason = $_.Exception.Message
  throw
} finally {
  $receipt | ConvertTo-Json | Set-Content (Join-Path $PackageDir 'defender-static-scan.json') -Encoding utf8
  $summary = "Defender static scan: $($receipt.outcome). $($receipt.reason) Installer SHA-256: $hash. Installer never executed."
  Write-Output $summary
  if ($env:GITHUB_STEP_SUMMARY) { $summary | Add-Content $env:GITHUB_STEP_SUMMARY }
}
