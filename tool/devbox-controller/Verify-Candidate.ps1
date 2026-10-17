param(
  [Parameter(Mandatory=$true)][string]$CandidateId,
  [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'approved-candidates.json') -Raw | ConvertFrom-Json
$property = @($policy.candidates.PSObject.Properties | Where-Object Name -CEQ $CandidateId)
if ($policy.schema -ne 1 -or $property.Count -ne 1) { throw 'Candidate is not in the committed reviewed allowlist.' }
$candidate = $property[0].Value
if ($candidate.repository -cne 'Sampath-K/bloomstep' -or
    $candidate.source -notmatch '^[a-f0-9]{40}$' -or
    $candidate.installerSha256 -notmatch '^[a-f0-9]{64}$' -or
    $candidate.packageSha256 -notmatch '^[a-f0-9]{64}$' -or
    $candidate.runId -notmatch '^\d+$' -or $candidate.artifactId -notmatch '^\d+$' -or
    $candidate.packageUrl -notmatch '^https://raw\.githubusercontent\.com/Sampath-K/bloomstep/[a-f0-9]{40}/docs/downloads/bloomstep-devbox-installer-trial\.zip$') {
  throw 'Reviewed candidate provenance is invalid.'
}
$headers = @{Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28'; 'User-Agent'='bloomstep-private-controller'}
# Public read-only metadata; the controller token is never sent to the public repository.
$run = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/Sampath-K/bloomstep/actions/runs/$($candidate.runId)" -TimeoutSec 60
if ($run.head_sha -cne $candidate.source -or $run.repository.full_name -cne $candidate.repository -or
    $run.head_repository.full_name -cne $candidate.repository -or $run.path -cne '.github/workflows/ci.yml' -or
    $run.event -notin @('push','pull_request','workflow_dispatch')) {
  throw 'Upstream workflow/source/repository identity differs from the reviewed build.'
}
$artifact = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/Sampath-K/bloomstep/actions/artifacts/$($candidate.artifactId)" -TimeoutSec 60
if ([string]$artifact.id -cne $candidate.artifactId -or $artifact.name -cne 'bloomstep-universal-installer' -or
    [string]$artifact.workflow_run.id -cne $candidate.runId -or $artifact.workflow_run.head_sha -cne $candidate.source) {
  throw 'Upstream artifact identity differs from the reviewed build.'
}
# The retained public pinned ZIP remains hash-authoritative even after Actions artifact expiry.
# The overall run may remain in progress because protected jobs are still queued.
$jobs = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/Sampath-K/bloomstep/actions/runs/$($candidate.runId)/jobs?per_page=100" -TimeoutSec 60
if ($jobs.total_count -gt 100) { throw 'Build job list exceeds the bounded audit; no incomplete pagination is accepted.' }
foreach ($name in @('test-and-build-windows (windows-latest, x64)', 'test-and-build-windows (windows-11-arm, arm64)', 'universal-installer')) {
  $matches = @($jobs.jobs | Where-Object { $_.name -ceq $name -and $_.head_sha -ceq $candidate.source -and $_.conclusion -ceq 'success' })
  if ($matches.Count -ne 1) { throw "Exact-head hosted build gate not verified: $name" }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$archive = Join-Path $OutputDirectory 'candidate.zip'
Invoke-WebRequest -Uri $candidate.packageUrl -OutFile $archive -TimeoutSec 180
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $candidate.packageSha256) {
  throw 'Reviewed candidate package digest mismatch.'
}
@{
  kind='reviewed-supplemental-candidate'
  candidate=$CandidateId
  source=$candidate.source
  runId=$candidate.runId
  installerSha256=$candidate.installerSha256
  packageSha256=$candidate.packageSha256
  protectedGateStatus='UNVERIFIED'
  protectedGatesAccepted=$false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'candidate-provenance.json') -Encoding utf8
