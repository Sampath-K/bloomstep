[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$ResourceTenantId,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$SubscriptionId,
  [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SwaName,
  [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ResourceGroup,
  [Parameter(Mandatory)][ValidateSet('Sampath-K/bloomstep')][string]$Repository,
  [Parameter(Mandatory)][ValidateSet('bloomstep-operations')][string]$Environment,
  [Parameter(Mandatory)][ValidateSet('sampath-k-bloomstep-mvp-implementation')][string]$FeatureBranch,
  [Parameter(Mandatory)][switch]$ConfirmPersonalResourceTenant
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ConfirmPersonalResourceTenant) { throw 'Explicit personal resource-directory confirmation required.' }
$ResourceTenantId = ([guid]$ResourceTenantId).ToString()
$SubscriptionId = ([guid]$SubscriptionId).ToString()

function AzureJson([string[]]$Arguments) {
  $output = & az @Arguments --only-show-errors -o json 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'Azure operation failed; inspect account/permissions without printing credentials.' }
  $output | ConvertFrom-Json
}
function Github([string]$Path, [string]$Method = 'GET', $Body = $null, [switch]$AllowMissing) {
  $arguments = @('api', $Path, '--method', $Method, '-H', 'Accept: application/vnd.github+json')
  if ($null -ne $Body) {
    $output = ($Body | ConvertTo-Json -Depth 20 -Compress) | & gh @arguments --input - 2>$null
  } else {
    $output = & gh @arguments 2>&1
  }
  if ($LASTEXITCODE -ne 0) {
    if ($AllowMissing -and ($output | Out-String) -match 'HTTP 404') { return $null }
    throw "GitHub operation failed for $Path; verify repository administration permissions."
  }
  if ($output) { $output | ConvertFrom-Json }
}

# Validate explicit subscription binding before any Graph operation or mutation.
$subscription = AzureJson @('account', 'show', '--subscription', $SubscriptionId)
if ($subscription.id -ne $SubscriptionId -or $subscription.tenantId -ne $ResourceTenantId -or $subscription.state -ne 'Enabled') {
  throw 'Subscription is not enabled in the explicitly approved resource tenant.'
}
$swa = AzureJson @('staticwebapp', 'show', '--subscription', $SubscriptionId, '--resource-group', $ResourceGroup, '--name', $SwaName)
if ($swa.sku.name -ne 'Free' -or -not $swa.defaultHostname) { throw 'Existing SWA must be Free; no resources or upgrades will be created.' }
$apiOrigin = "https://$($swa.defaultHostname)"
$configuredOrigin = Github "repos/$Repository/actions/variables/API_ORIGIN"
if ($configuredOrigin.value.TrimEnd('/') -ne $apiOrigin) { throw 'Existing repository API_ORIGIN must match the selected SWA. Set it separately before provisioning.' }
foreach ($branch in @('main', $FeatureBranch)) {
  $null = Github "repos/$Repository/branches/$([uri]::EscapeDataString($branch))"
}
$subjectPolicy = Github "repos/$Repository/actions/oidc/customization/sub"
if (-not $subjectPolicy.use_default) { throw 'Repository custom OIDC subjects are enabled; this FIC requires the default environment subject.' }

# Azure CLI makes --tenant and --subscription mutually exclusive for token acquisition.
$token = & az account get-access-token --tenant $ResourceTenantId --resource https://graph.microsoft.com --query accessToken -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Graph token acquisition failed. Review Azure CLI diagnostics/account permissions separately without printing tokens; no login requirement is inferred. No interactive login or customer M2M request is performed.' }
$graphHeaders = @{ Authorization = "Bearer $token" }
function Graph([string]$Path, [string]$Method = 'GET', $Body = $null) {
  $uri = if ($Path.StartsWith('https://graph.microsoft.com/v1.0/')) { $Path } else { "https://graph.microsoft.com/v1.0/$Path" }
  $arguments = @{ Uri = $uri; Headers = $graphHeaders; Method = $Method; ErrorAction = 'Stop' }
  if ($null -ne $Body) { $arguments.ContentType = 'application/json'; $arguments.Body = $Body | ConvertTo-Json -Depth 30 -Compress }
  try { Invoke-RestMethod @arguments } catch { throw "Graph $Method failed. Verify resource-directory app administration permissions; response/token omitted." }
}
function GraphList([string]$Path) {
  do {
    $page = Graph $Path
    foreach ($entry in $page.value) { $entry }
    $next = $page.PSObject.Properties['@odata.nextLink']
    $Path = if ($next) { [string]$next.Value } else { '' }
  } while ($Path)
}

try {
  $discovery = Invoke-RestMethod "https://login.microsoftonline.com/$ResourceTenantId/v2.0/.well-known/openid-configuration"
  $expectedIssuer = "https://login.microsoftonline.com/$ResourceTenantId/v2.0"
  if ($discovery.issuer -ne $expectedIssuer -or -not $discovery.jwks_uri.StartsWith('https://login.microsoftonline.com/')) {
    throw 'Resource-tenant discovery is not the expected public-cloud v2 issuer/JWKS.'
  }
  # Environment branch policies reject tags and PR refs before GitHub issues the FIC subject.
  $existingEnvironment = Github "repos/$Repository/environments/$Environment" 'GET' $null -AllowMissing
  $environmentBody = @{
    deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
  }
  if ($existingEnvironment) {
    foreach ($rule in $existingEnvironment.protection_rules) {
      if ($rule.type -eq 'wait_timer') { $environmentBody.wait_timer = $rule.wait_timer }
      elseif ($rule.type -eq 'required_reviewers') {
        $environmentBody.reviewers = @($rule.reviewers | ForEach-Object { @{ type = $_.type; id = $_.reviewer.id } })
        $environmentBody.prevent_self_review = $rule.prevent_self_review
      } elseif ($rule.type -ne 'branch_policy') {
        throw 'Custom environment protection rules require manual review; refusing to overwrite them.'
      }
    }
    $bypass = $existingEnvironment.PSObject.Properties['can_admins_bypass']
    if ($bypass) { $environmentBody.can_admins_bypass = $bypass.Value }
  }
  $null = Github "repos/$Repository/environments/$Environment" 'PUT' $environmentBody
  $policies = Github "repos/$Repository/environments/$Environment/deployment-branch-policies?per_page=100"
  if ($policies.total_count -gt 100) { throw 'Too many existing environment branch policies; review manually.' }
  foreach ($policy in $policies.branch_policies) {
    if ($policy.name -notin @('main', $FeatureBranch) -or $policy.type -ne 'branch') {
      throw 'Unexpected existing environment branch/tag policy; remove it explicitly before continuing.'
    }
  }
  foreach ($branch in @('main', $FeatureBranch)) {
    if (-not @($policies.branch_policies | Where-Object { $_.name -eq $branch -and $_.type -eq 'branch' }).Count) {
      $null = Github "repos/$Repository/environments/$Environment/deployment-branch-policies" 'POST' @{ name = $branch; type = 'branch' }
    }
  }
  $name = 'Bloomstep aggregate worker (personal resource directory)'
  $tag = "Bloomstep-aggregate:$Repository`:$Environment`:$SubscriptionId`:$SwaName"
  $matches = @(GraphList "applications?`$filter=displayName eq '$name'" )
  if ($matches.Count -gt 1) { throw 'Duplicate aggregate worker registrations; resolve manually.' }
  if ($matches.Count -eq 1) {
    $worker = $matches[0]
    if ($worker.tags -notcontains $tag -or $worker.signInAudience -ne 'AzureADMyOrg') { throw 'Existing app is not owned by this exact resource/repository binding.' }
  } else {
    $worker = Graph 'applications' 'POST' @{
      displayName = $name; signInAudience = 'AzureADMyOrg'
      tags = @('Bloomstep-managed-free', 'Bloomstep-aggregate-worker', $tag)
      api = @{ requestedAccessTokenVersion = 2 }
      appRoles = @()
    }
  }
  foreach ($field in @('passwordCredentials', 'keyCredentials')) {
    $credentials = $worker.PSObject.Properties[$field]
    if ($credentials -and @($credentials.Value).Count) { throw 'Worker app has password/key credentials; this job requires FIC only. Review manually.' }
  }
  $roles = @($worker.appRoles)
  if (@($roles | Where-Object value -ne 'Bloomstep.AggregateWriter').Count) { throw 'Unexpected worker application roles; review manually.' }
  $role = @($roles | Where-Object value -eq 'Bloomstep.AggregateWriter')
  if ($role.Count -gt 1) { throw 'Duplicate aggregate role definitions.' }
  $roleId = if ($role.Count) { $role[0].id } else { [guid]::NewGuid().ToString() }
  $null = Graph "applications/$($worker.id)" 'PATCH' @{
    identifierUris = @("api://$($worker.appId)")
    api = @{ requestedAccessTokenVersion = 2 }
    appRoles = @(@{
      id = $roleId; value = 'Bloomstep.AggregateWriter'; displayName = 'Bloomstep aggregate writer'
      description = 'Write bounded internal daily aggregates only; no customer garden or feedback access.'
      allowedMemberTypes = @('Application'); isEnabled = $true
    })
  }
  $principals = @(GraphList "servicePrincipals?`$filter=appId eq '$($worker.appId)'")
  if ($principals.Count -gt 1) { throw 'Duplicate worker service principals.' }
  $principal = if ($principals.Count) { $principals[0] } else {
    Graph 'servicePrincipals' 'POST' @{ appId = $worker.appId; tags = @('Bloomstep-aggregate-worker', $tag) }
  }
  $assignments = @(GraphList "servicePrincipals/$($principal.id)/appRoleAssignments")
  if (@($assignments | Where-Object { $_.resourceId -ne $principal.id -or $_.appRoleId -ne $roleId }).Count) {
    throw 'Unexpected existing worker application permissions; review manually.'
  }
  if (-not @($assignments | Where-Object { $_.resourceId -eq $principal.id -and $_.appRoleId -eq $roleId }).Count) {
    $null = Graph "servicePrincipals/$($principal.id)/appRoleAssignments" 'POST' @{
      principalId = $principal.id; resourceId = $principal.id; appRoleId = $roleId
    }
  }
  $subject = "repo:$Repository`:environment:$Environment"
  $federated = @(GraphList "applications/$($worker.id)/federatedIdentityCredentials")
  if (@($federated | Where-Object name -ne 'bloomstep-operations-github').Count) { throw 'Unexpected worker federated credentials; review manually.' }
  $ficBody = @{
    name = 'bloomstep-operations-github'; description = 'Approved main/feature environment jobs only.'
    issuer = 'https://token.actions.githubusercontent.com'; subject = $subject; audiences = @('api://AzureADTokenExchange')
  }
  if ($federated.Count) {
    $fic = $federated[0]
    if ($fic.issuer -ne $ficBody.issuer -or $fic.subject -ne $subject -or @($fic.audiences).Count -ne 1 -or $fic.audiences[0] -ne 'api://AzureADTokenExchange') {
      throw 'Existing FIC trust differs; review rather than silently widening it.'
    }
  } else { $null = Graph "applications/$($worker.id)/federatedIdentityCredentials" 'POST' $ficBody }

  # Preserve every other SWA setting. These values and GitHub variables are public IDs.
  $settings = @(
    "AGGREGATE_OIDC_ISSUER=$($discovery.issuer)",
    "AGGREGATE_OIDC_AUDIENCE=$($worker.appId)",
    "AGGREGATE_OIDC_JWKS_URI=$($discovery.jwks_uri)"
  )
  $null = AzureJson (@('staticwebapp', 'appsettings', 'set', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $SwaName, '--setting-names') + $settings)
  $variables = Github "repos/$Repository/environments/$Environment/variables?per_page=100"
  foreach ($entry in @(@{ name = 'WORKER_TENANT_ID'; value = $ResourceTenantId }, @{ name = 'WORKER_CLIENT_ID'; value = $worker.appId })) {
    $existing = @($variables.variables | Where-Object name -eq $entry.name)
    if ($existing.Count) {
      $null = Github "repos/$Repository/environments/$Environment/variables/$($entry.name)" 'PATCH' $entry
    } else { $null = Github "repos/$Repository/environments/$Environment/variables" 'POST' $entry }
  }
  Write-Output 'Worker app, explicit role, FIC, branch-restricted environment and nonsecret settings prepared. Live token/API verification remains required; cron starts only after default-branch merge.'
} finally {
  $token = $null
  $graphHeaders = $null
}
