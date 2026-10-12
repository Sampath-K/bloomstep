param([Parameter(Mandatory = $true)][string]$EvidenceDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    if (Test-Path $EvidenceDir) { throw 'EvidenceDir must be a fresh owned artifact directory.' }
    $env:EVIDENCE_DIR = [IO.Path]::GetFullPath($EvidenceDir)
    npm --prefix api run check --silent
    if ($LASTEXITCODE -ne 0) { throw 'API type check failed.' }
    node --test --test-reporter=dot api\test\attribution.test.mjs api\test\website-funnel.test.mjs api\test\local_api_e2e.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Collector contract tests failed.' }
    node --test --test-reporter=dot site\test\attribution.test.mjs site\test\customer.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Website contract tests failed.' }
    npm --prefix site run build --silent
    if ($LASTEXITCODE -ne 0) { throw 'Website bundle failed.' }
    node site\verify-telemetry.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Browser persisted-readback acceptance failed.' }
    $env:BLOOMSTEP_TEST_RECEIPT_PATH = Join-Path $env:EVIDENCE_DIR 'website-receipt.json'
    flutter test --no-pub --dart-define=BLOOMSTEP_TEST_BUILD=true --reporter expanded test\telemetry_http_test.dart test\telemetry_test.dart test\measurement_receipt_test.dart test\sync_outbox_test.dart test\record_deletion_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'App telemetry HTTP/SQLite acceptance failed.' }
    node site\verify-telemetry-app-results.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Independent app report assertions failed.' }
} finally {
    Remove-Item Env:\BLOOMSTEP_TEST_RECEIPT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\EVIDENCE_DIR -ErrorAction SilentlyContinue
    Pop-Location
}
