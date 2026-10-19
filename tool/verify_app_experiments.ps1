param([Parameter(Mandatory = $true)][string]$EvidenceDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$oldEvidence = $env:EXPERIENCE_EVIDENCE_DIR
Push-Location $root
try {
    if (Test-Path $EvidenceDir) { throw 'EvidenceDir must be a fresh artifact directory.' }
    $source = (git rev-parse HEAD).Trim()
    $dirty = @(git status --porcelain).Count -ne 0
    $env:EXPERIENCE_EVIDENCE_DIR = [IO.Path]::GetFullPath($EvidenceDir)
    New-Item -ItemType Directory -Path $env:EXPERIENCE_EVIDENCE_DIR | Out-Null
    node tool\generate_experience_policy.mjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Generated app policy drift.' }
    node tool\generate_event_registry.mjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Generated event registry drift.' }
    npm --prefix api run check --silent
    if ($LASTEXITCODE -ne 0) { throw 'API type check failed.' }
    node --test --test-reporter=dot api\test\experience-experiments.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'GrowthBook observation/purge contract failed.' }
    flutter test --no-pub --dart-define=BUDLARK_TEST_BUILD=true --reporter expanded test\growthbook_experience_provider_test.dart test\experience_experiments_test.dart test\experience_copy_test.dart test\experience_http_test.dart test\sync_outbox_test.dart test\record_deletion_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'App implementation HTTP/SQLite/widget acceptance failed.' }
    $appPath = Join-Path $env:EXPERIENCE_EVIDENCE_DIR 'app-http-receipt.json'
    $app = Get-Content $appPath -Raw | ConvertFrom-Json
    if (!$app.passed -or !$app.syntheticOnly -or $app.productionWrites -or $app.persistedObservations -ne 4 -or !$app.purgedRemoteExperimentEvents) {
        throw 'Independent app functional receipt assertions failed.'
    }
    $receipt = [ordered]@{
        kind = 'isolated-app-experience-acceptance'; sourceRevision = $source; sourceDirty = $dirty
        implementationValidation = 'real SQLite/authenticated loopback HTTP; synthetic identity and timestamps'
        provider = 'growthbook_sdk_flutter 4.4.0'; providerEvidence = 'official SDK local fixture and fake swap'
        statisticalEvidence = 'NOT_CONNECTED'; hostedGrowthBook = 'PENDING_SETUP'; customerEfficacy = 'NOT_ESTABLISHED'
        productionEnabled = $false; productionWrites = $false; passed = $true
        appReceiptHash = (Get-FileHash -Algorithm SHA256 $appPath).Hash.ToLowerInvariant()
        policyFileHash = (Get-FileHash -Algorithm SHA256 shared\experience-experiments.json).Hash.ToLowerInvariant()
        paidServices = @(); newBillableResources = @()
    }
    $out = Join-Path $env:EXPERIENCE_EVIDENCE_DIR 'acceptance-receipt.json'
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $out
    Write-Output ("RECEIPT " + (Get-FileHash -Algorithm SHA256 $out).Hash.ToLowerInvariant())
} finally {
    $env:EXPERIENCE_EVIDENCE_DIR = $oldEvidence
    Pop-Location
}
