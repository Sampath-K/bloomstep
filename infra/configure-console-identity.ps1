[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$CustomerTenantId,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$SubscriptionId,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$ResourceTenantId,
  [Parameter(Mandatory)][string]$ResourceGroup,
  [Parameter(Mandatory)][string]$SwaName,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$ApiClientId,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$AuthenticationEventsFlowId,
  [Parameter(Mandatory)][string]$CustomerIssuer,
  [Parameter(Mandatory)][ValidateSet('Sampath-K/bloomstep')][string]$Repository,
  [Parameter(Mandatory)][switch]$ConfirmPersonalSubscription
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ConfirmPersonalSubscription) { throw 'Explicit personal-subscription confirmation is required.' }
if ($CustomerTenantId -eq $ResourceTenantId) { throw 'Customer and resource directories must remain separate.' }
function AzureJson([string[]]$Arguments) {
  $raw = & az @Arguments --only-show-errors -o json 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'Azure validation failed; no credentials printed.' }
  $raw | ConvertFrom-Json
}
$subscription = AzureJson @('account','show','--subscription',$SubscriptionId)
if ($subscription.tenantId -ne $ResourceTenantId -or $subscription.id -ne $SubscriptionId -or $subscription.state -ne 'Enabled') {
  throw 'Explicit subscription/resource-tenant binding is invalid.'
}
$swa = AzureJson @('staticwebapp','show','--subscription',$SubscriptionId,'--resource-group',$ResourceGroup,'--name',$SwaName)
if ($swa.sku.name -ne 'Free') { throw 'Only the existing Free SWA is supported.' }
$origin = "https://$($swa.defaultHostname)"
$publicOrigin = & gh api "repos/$Repository/actions/variables/API_ORIGIN" --jq '.value' 2>$null
if($LASTEXITCODE -ne 0 -or $publicOrigin.TrimEnd('/') -ne $origin){throw 'Existing repository API_ORIGIN must match the selected Free SWA.'}
$issuerUri = [uri]$CustomerIssuer
if ($issuerUri.Scheme -ne 'https' -or -not $issuerUri.Host.EndsWith('.ciamlogin.com') -or
    $issuerUri.AbsolutePath.TrimEnd('/') -ne "/$CustomerTenantId/v2.0" -or $issuerUri.Query -or $issuerUri.Fragment -or $issuerUri.UserInfo) {
  throw 'Exact customer broker HTTPS issuer is required.'
}
$discovery = Invoke-RestMethod "$($CustomerIssuer.TrimEnd('/'))/.well-known/openid-configuration"
if ($discovery.issuer.TrimEnd('/') -ne $CustomerIssuer.TrimEnd('/') -or -not $discovery.jwks_uri.StartsWith('https://')) { throw 'Customer discovery issuer/keys mismatch.' }
$token = & az account get-access-token --tenant $CustomerTenantId --resource https://graph.microsoft.com --query accessToken -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Customer Graph token acquisition failed; no automatic login diagnosis or secret fallback.' }
$headers = @{ Authorization = "Bearer $token" }
function Graph([string]$Path,[string]$Method='GET',$Body=$null) {
  $arguments = @{Uri="https://graph.microsoft.com/v1.0/$Path";Headers=$headers;Method=$Method}
  if($null -ne $Body){$arguments.ContentType='application/json';$arguments.Body=$Body|ConvertTo-Json -Depth 20 -Compress}
  try { Invoke-RestMethod @arguments } catch { throw "Customer Graph $Method failed (response omitted). App-flow association must succeed; no manual-token fallback." }
}
function GraphList([string]$Path) {
  do {
    $page=Graph $Path
    foreach($entry in $page.value){$entry}
    $next=$page.PSObject.Properties['@odata.nextLink']
    $Path=if($next){([uri]$next.Value).AbsoluteUri.Replace('https://graph.microsoft.com/v1.0/','')}else{''}
  } while($Path)
}
try {
  $organization=Graph 'organization'
  if (@($organization.value | Where-Object id -eq $CustomerTenantId).Count -ne 1) { throw 'Graph token is not bound to the selected customer directory.' }
  $apis=@(GraphList "applications?`$filter=appId eq '$ApiClientId'")
  if($apis.Count -ne 1){throw 'Existing customer API registration must be unambiguous.'}
  $scope=@($apis[0].api.oauth2PermissionScopes | Where-Object { $_.value -eq 'Garden.ReadWrite' -and $_.isEnabled })
  if($scope.Count -ne 1){throw 'Existing enabled Garden.ReadWrite scope required.'}
  $apiPrincipals=@(GraphList "servicePrincipals?`$filter=appId eq '$ApiClientId'")
  if($apiPrincipals.Count -ne 1){throw 'Existing customer API service principal required.'}
  $flow=Graph "identity/authenticationEventsFlows/$AuthenticationEventsFlowId"
  $null=$flow
  # Preflight documented association endpoint before creating any app.
  $flowPath="identity/authenticationEventsFlows/$AuthenticationEventsFlowId/conditions/applications/includeApplications"
  $included=@(GraphList $flowPath)
  $name='Bloomstep operator console (public SPA)'
  $tag="Bloomstep-console:$Repository`:$SubscriptionId`:$SwaName"
  $apps=@(GraphList "applications?`$filter=displayName eq '$name'")
  if($apps.Count -gt 1){throw 'Duplicate operator SPA registrations.'}
  if($apps.Count){
    $app=$apps[0]
    if($app.tags -notcontains $tag -or $app.signInAudience -ne 'AzureADMyOrg'){throw 'Existing SPA binding/tag mismatch.'}
    foreach($field in @('passwordCredentials','keyCredentials')){
      $credentials=$app.PSObject.Properties[$field]
      if($credentials -and @($credentials.Value).Count){throw 'SPA must not have secrets/key credentials.'}
    }
  } else {
    $app=Graph 'applications' 'POST' @{
      displayName=$name;signInAudience='AzureADMyOrg';tags=@('Bloomstep-managed-free',$tag)
      spa=@{redirectUris=@("$origin/operator-callback.html")}
    }
  }
  $null=Graph "applications/$($app.id)" 'PATCH' @{
    spa=@{redirectUris=@("$origin/operator-callback.html")}
    web=@{redirectUris=@()}
    publicClient=@{redirectUris=@()}
    isFallbackPublicClient=$false
    requiredResourceAccess=@(@{resourceAppId=$ApiClientId;resourceAccess=@(@{id=$scope[0].id;type='Scope'})})
  }
  $principals=@(GraphList "servicePrincipals?`$filter=appId eq '$($app.appId)'")
  if($principals.Count -gt 1){throw 'Duplicate console service principals.'}
  $principal=if($principals.Count){$principals[0]}else{Graph 'servicePrincipals' 'POST' @{appId=$app.appId}}
  $grants=@(GraphList "oauth2PermissionGrants?`$filter=clientId eq '$($principal.id)'")
  if(@($grants|Where-Object{$_.resourceId -ne $apiPrincipals[0].id -or $_.scope -ne 'Garden.ReadWrite' -or $_.consentType -ne 'AllPrincipals'}).Count){
    throw 'Existing SPA consent exceeds/differs from narrow API consent; review manually.'
  }
  if(-not $grants.Count){
    $null=Graph 'oauth2PermissionGrants' 'POST' @{clientId=$principal.id;resourceId=$apiPrincipals[0].id;consentType='AllPrincipals';scope='Garden.ReadWrite'}
  }
  if(-not @($included|Where-Object appId -eq $app.appId).Count){
    $null=Graph $flowPath 'POST' @{'@odata.type'='#microsoft.graph.authenticationConditionApplication';appId=$app.appId}
  }
  $verification=@(GraphList $flowPath)
  if(-not @($verification|Where-Object appId -eq $app.appId).Count){throw 'SPA user-flow association was not verified; do not deploy a fake/manual-token console.'}
  # Only public identifiers, never broker credentials, go to deployment variables.
  foreach($variable in @(
    @{name='CONSOLE_CLIENT_ID';value=$app.appId},
    @{name='OIDC_ISSUER';value=$CustomerIssuer},
    @{name='OIDC_API_SCOPE';value="api://$ApiClientId/Garden.ReadWrite"}
  )){
    $null=& gh variable set $variable.name --repo $Repository --body $variable.value 2>$null
    if($LASTEXITCODE -ne 0){throw 'Public GitHub variable write failed; review existing app/association and rerun.'}
  }
  Write-Output 'Public console SPA, exact callback, narrow API consent and user-flow association prepared. Customer Admin role assignment and real popup/API validation remain required.'
} finally {$token=$null;$headers=$null}
