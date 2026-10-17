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
function Get-GitHubBuildMetadata([string]$Path) {
  if ($Path -notmatch '^actions/(runs/\d+(/jobs\?per_page=100)?|artifacts/\d+)$') {
    throw 'Metadata path is not in the fixed read-only public build API allowlist.'
  }
  if (-not $env:GITHUB_TOKEN) { throw 'Built-in controller read token missing; unauthenticated rate-limit fallback is not permitted.' }
  $headers = @{
    Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28'
    'User-Agent'='bloomstep-private-controller'; Authorization="Bearer $env:GITHUB_TOKEN"
  }
  for ($attempt=1; $attempt -le 3; $attempt++) {
    try {
      $response=Invoke-WebRequest -Headers $headers -Uri ("https://api.github.com/repos/Sampath-K/bloomstep/" + $Path) -TimeoutSec 60 -MaximumRedirection 0
      return ($response.Content | ConvertFrom-Json)
    } catch {
      $status=0
      $failureResponse=$null
      if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
        $failureResponse=$_.Exception.Response
        $status=[int]$failureResponse.StatusCode
      }
      # 401/403/404 are permanent for this invocation, including rate exhaustion: report, never mask.
      if ($attempt -eq 3 -or $status -notin @(408,429,500,502,503,504)) {
        $reason=switch($status){
          401 {'Built-in read token rejected.'}
          403 {
            $responseHeaders=$failureResponse.Headers
            $rateExhausted=$responseHeaders.Contains('Retry-After') -or
              ($responseHeaders.Contains('X-RateLimit-Remaining') -and
               '0' -in @($responseHeaders.GetValues('X-RateLimit-Remaining')))
            if($rateExhausted){'GitHub rate limit exhausted; rerun after the reported server window.'}
            else{'GitHub access or policy denied; token/repository capability must be reviewed.'}
          }
          404 {'Build resource unavailable, expired or inaccessible; provenance cannot be verified.'}
          default {'Transport or transient retry budget exhausted.'}
        }
        throw "GitHub build metadata request failed (HTTP $status). $reason No provenance PASS."
      }
      $delay=[int][Math]::Pow(2,$attempt)
      $retryAfter=$failureResponse.Headers.RetryAfter
      if ($retryAfter) {
        if($retryAfter.Delta){$delay=[int][Math]::Ceiling($retryAfter.Delta.TotalSeconds)}
        elseif($retryAfter.Date){$delay=[int][Math]::Max(0,[Math]::Ceiling(($retryAfter.Date-[DateTimeOffset]::UtcNow).TotalSeconds))}
        if ($delay -gt 60 -or $delay -lt 0) { throw 'GitHub Retry-After exceeds the bounded wait; rerun later.' }
      }
      Start-Sleep -Seconds $delay
    } finally { $headers.Authorization=$null }
    $headers.Authorization="Bearer $env:GITHUB_TOKEN"
  }
}
# Authenticate only exact api.github.com read-only metadata requests. Never attach this header to raw/download hosts.
$run = Get-GitHubBuildMetadata "actions/runs/$($candidate.runId)"
if ($run.head_sha -cne $candidate.source -or $run.repository.full_name -cne $candidate.repository -or
    $run.head_repository.full_name -cne $candidate.repository -or $run.path -cne '.github/workflows/ci.yml' -or
    $run.event -notin @('push','pull_request','workflow_dispatch')) {
  throw 'Upstream workflow/source/repository identity differs from the reviewed build.'
}
$artifact = Get-GitHubBuildMetadata "actions/artifacts/$($candidate.artifactId)"
if ([string]$artifact.id -cne $candidate.artifactId -or $artifact.name -cne 'bloomstep-universal-installer' -or
    [string]$artifact.workflow_run.id -cne $candidate.runId -or $artifact.workflow_run.head_sha -cne $candidate.source) {
  throw 'Upstream artifact identity differs from the reviewed build.'
}
# The retained public pinned ZIP remains hash-authoritative even after Actions artifact expiry.
# The overall run may remain in progress because protected jobs are still queued.
$jobs = Get-GitHubBuildMetadata "actions/runs/$($candidate.runId)/jobs?per_page=100"
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
