param(
  [Parameter(Mandatory)][ValidatePattern('^[a-f0-9-]{36}$')][string]$TenantId
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'identity-callbacks.ps1')
$token = az account get-access-token --tenant $TenantId --resource https://graph.microsoft.com --query accessToken -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Sign into the approved customer tenant first.' }
$headers = @{ Authorization = "Bearer $token" }
function Graph([string]$Path, [string]$Method = 'GET', $Body = $null) {
  $arguments = @{ Uri = "https://graph.microsoft.com/v1.0/$Path"; Headers = $headers; Method = $Method }
  if ($null -ne $Body) {
    $arguments.ContentType = 'application/json'
    $arguments.Body = $Body | ConvertTo-Json -Depth 20 -Compress
  }
  Invoke-RestMethod @arguments
}
function ManagedApp([string]$Name, $Definition) {
  $all = Graph 'applications'
  $matching = @($all.value | Where-Object displayName -eq $Name)
  if ($matching.Count -gt 1) { throw "Multiple registrations named $Name; resolve manually." }
  if ($matching.Count -eq 1) {
    if ($matching[0].tags -notcontains 'Budlark-managed-free') { throw "Existing $Name is not managed by this project." }
    return $matching[0]
  }
  Graph 'applications' 'POST' $Definition
}
function Principal([string]$AppId) {
  $all = Graph 'servicePrincipals'
  $matching = @($all.value | Where-Object appId -eq $AppId)
  if ($matching.Count) { return $matching[0] }
  Graph 'servicePrincipals' 'POST' @{ appId = $AppId }
}
$scopeId = [guid]::NewGuid().ToString()
$adminRoleId = [guid]::NewGuid().ToString()
$api = ManagedApp 'Budlark API' @{
  displayName = 'Budlark API'; signInAudience = 'AzureADMyOrg'; tags = @('Budlark-managed-free')
  api = @{
    requestedAccessTokenVersion = 2
    oauth2PermissionScopes = @(@{
      id = $scopeId; value = 'Garden.ReadWrite'; type = 'Admin'; isEnabled = $true
      adminConsentDisplayName = 'Read and write your private Budlark garden'
      adminConsentDescription = 'Sync the signed-in account garden, private feedback and optional event counts.'
      userConsentDisplayName = 'Sync your private garden'
      userConsentDescription = 'Read and write only your signed-in Budlark account data.'
    })
  }
  appRoles = @(@{
    id = $adminRoleId; value = 'Budlark.Admin'; displayName = 'Budlark product team'
    description = 'Read private feedback, reply and view aggregates. Assigned explicitly, never inferred.'
    isEnabled = $true; allowedMemberTypes = @('User', 'Application')
  })
}
$scopeId = $api.api.oauth2PermissionScopes[0].id
$null = Graph "applications/$($api.id)" 'PATCH' @{ identifierUris = @("api://$($api.appId)") }
$apiPrincipal = Principal $api.appId
$desktop = ManagedApp 'Budlark Windows' @{
  displayName = 'Budlark Windows'; signInAudience = 'AzureADMyOrg'; tags = @('Budlark-managed-free')
  isFallbackPublicClient = $true
  publicClient = @{ redirectUris = @('http://127.0.0.1:43821/callback') }
  requiredResourceAccess = @(@{
    resourceAppId = $api.appId
    resourceAccess = @(@{ id = $scopeId; type = 'Scope' })
  })
}
$desktopPrincipal = Principal $desktop.appId
$grants = Graph 'oauth2PermissionGrants'
$existing = @($grants.value | Where-Object { $_.clientId -eq $desktopPrincipal.id -and $_.resourceId -eq $apiPrincipal.id -and $_.consentType -eq 'AllPrincipals' })
if (-not $existing.Count) {
  $null = Graph 'oauth2PermissionGrants' 'POST' @{
    clientId = $desktopPrincipal.id; resourceId = $apiPrincipal.id
    consentType = 'AllPrincipals'; scope = 'Garden.ReadWrite'
  }
}
$organizations = Graph 'organization'
$domain = @($organizations.value[0].verifiedDomains | Where-Object isInitial)[0].name
if (-not $domain.EndsWith('.onmicrosoft.com')) { throw 'Customer initial domain could not be verified.' }
$subdomain = $domain.Substring(0, $domain.Length - '.onmicrosoft.com'.Length)
$callbacks = @(Get-BudlarkFederationCallbacks -TenantId $TenantId -Subdomain $subdomain -Domain $domain)
$microsoft = ManagedApp 'Budlark consumer federation' @{
  displayName = 'Budlark consumer federation'
  signInAudience = 'AzureADandPersonalMicrosoftAccount'
  tags = @('Budlark-managed-free')
  api = @{ requestedAccessTokenVersion = 2 }
  web = @{ redirectUris = $callbacks }
  requiredResourceAccess = @()
}
$microsoft = Graph "applications/$($microsoft.id)"
$mergedCallbacks = @(Merge-BudlarkFederationCallbacks -Existing @($microsoft.web.redirectUris) -Required $callbacks)
if (@(Compare-Object @($microsoft.web.redirectUris) $mergedCallbacks -CaseSensitive).Count) {
  $null = Graph "applications/$($microsoft.id)" 'PATCH' @{ web = @{ redirectUris = $mergedCallbacks } }
}
$microsoft = Graph "applications/$($microsoft.id)"
if (@(Compare-Object $mergedCallbacks @($microsoft.web.redirectUris) -CaseSensitive).Count) {
  throw 'Federation callback readback mismatch; do not attempt customer sign-in.'
}
@{
  apiClientId = $api.appId
  desktopClientId = $desktop.appId
  apiScope = "api://$($api.appId)/Garden.ReadWrite"
  redirectUri = 'http://127.0.0.1:43821/callback'
  userFlow = 'Requires customer tenant user-flow setup and app association.'
  microsoftFederationClientId = $microsoft.appId
  microsoftFederationObjectId = $microsoft.id
  microsoftFederationCallbacks = @($microsoft.web.redirectUris)
  microsoftFederationSecret = 'Not created or exported; create and paste directly in Entra provider settings.'
} | ConvertTo-Json
Remove-Variable token,headers
