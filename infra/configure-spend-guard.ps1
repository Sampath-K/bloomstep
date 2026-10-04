[CmdletBinding()]
param(
  [Parameter(Mandatory)][guid]$ResourceTenantId,
  [Parameter(Mandatory)][guid]$SubscriptionId,
  [Parameter(Mandatory)][string]$ResourceGroup,
  [Parameter(Mandatory)][string]$SwaName,
  [Parameter(Mandatory)][string]$CosmosName,
  [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$CustomerDirectoryName,
  [Parameter(Mandatory)][ValidateSet('Sampath-K/bloomstep')][string]$Repository,
  [Parameter(Mandatory)][ValidateSet('bloomstep-operations')][string]$Environment,
  [Parameter(Mandatory)][switch]$ConfirmPersonalResourceTenant
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $ConfirmPersonalResourceTenant){throw 'Explicit personal resource-directory confirmation required.'}
function Azure([string[]]$Arguments){
  $raw=& az @Arguments --only-show-errors -o json 2>$null
  if($LASTEXITCODE -ne 0){throw 'Azure operation failed; diagnostics/credentials omitted.'}
  if($raw){$raw|ConvertFrom-Json}
}
function Github([string]$Path){
  $raw=& gh api $Path 2>$null
  if($LASTEXITCODE -ne 0){throw 'GitHub binding verification failed.'}
  $raw|ConvertFrom-Json
}
$tenant=$ResourceTenantId.ToString()
$subscription=$SubscriptionId.ToString()
$account=Azure @('account','show','--subscription',$subscription)
if($account.id -ne $subscription -or $account.tenantId -ne $tenant -or $account.state -ne 'Enabled'){throw 'Personal subscription/resource tenant binding mismatch.'}
$swa=Azure @('staticwebapp','show','--subscription',$subscription,'--resource-group',$ResourceGroup,'--name',$SwaName)
if($swa.sku.name -ne 'Free'){throw 'Only the existing Free SWA is supported.'}
$cosmos=Azure @('cosmosdb','show','--subscription',$subscription,'--resource-group',$ResourceGroup,'--name',$CosmosName)
if(-not $cosmos.enableFreeTier -or @($cosmos.locations).Count -ne 1){throw 'Existing Cosmos must be one-region free-tier.'}
$directoryUrl="https://management.azure.com/subscriptions/$subscription/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.AzureActiveDirectory/ciamDirectories/$CustomerDirectoryName`?api-version=2023-05-17-preview"
$directory=Azure @('rest','--subscription',$subscription,'--method','GET','--url',$directoryUrl)
if($directory.name -ne $CustomerDirectoryName -or $directory.sku.name -ne 'Base' -or $directory.sku.tier -ne 'A0'){throw 'Only the explicitly selected existing Base/A0 customer directory is approved.'}
$subscriptionMetadata=Azure @('rest','--subscription',$subscription,'--method','GET','--url',"https://management.azure.com/subscriptions/$subscription`?api-version=2022-12-01")
if($subscriptionMetadata.subscriptionPolicies.quotaId -ne 'FreeTrial_2014-09-01' -or $subscriptionMetadata.subscriptionPolicies.spendingLimit -ne 'On'){throw 'Approved trial spending-limit policy must be ON before provisioning.'}
try{
  $throughput=Azure @('cosmosdb','sql','container','throughput','show','--subscription',$subscription,'--resource-group',$ResourceGroup,'--account-name',$CosmosName,'--database-name','bloomstep','--name','data')
}catch{
  $throughput=Azure @('cosmosdb','sql','database','throughput','show','--subscription',$subscription,'--resource-group',$ResourceGroup,'--account-name',$CosmosName,'--name','bloomstep')
}
if($throughput.resource.throughput -ne 400 -or ($throughput.resource.PSObject.Properties['autoscaleSettings'] -and $throughput.resource.autoscaleSettings)){throw 'Existing bloomstep/data throughput must be manual400 RU, not autoscale.'}
$origin="https://$($swa.defaultHostname)"
if((Github "repos/$Repository/actions/variables/API_ORIGIN").value.TrimEnd('/') -ne $origin){throw 'Repository API_ORIGIN must match selected SWA.'}
$repo=Github "repos/$Repository"
if($repo.full_name -ne $Repository -or -not $repo.id -or -not $repo.owner.id){throw 'Immutable repository identity missing.'}
$policy=Github "repos/$Repository/actions/oidc/customization/sub"
if(-not $policy.use_default){throw 'Custom OIDC subject policy requires owner review; refusing to change it.'}
$envConfig=Github "repos/$Repository/environments/$Environment"
if(-not $envConfig.deployment_branch_policy.custom_branch_policies){throw 'Existing operations environment must have explicit branch restrictions.'}
$branches=Github "repos/$Repository/environments/$Environment/deployment-branch-policies?per_page=100"
if($branches.total_count -ne 2 -or @($branches.branch_policies|Where-Object{$_.type -ne 'branch' -or $_.name -notin @('main','sampath-k-bloomstep-mvp-implementation')}).Count){throw 'Operations environment must allow exactly main and approved feature branch, never PRs/tags.'}
$subject="repo:$($repo.owner.login)@$($repo.owner.id)/$($repo.name)@$($repo.id):environment:$Environment"
$token=& az account get-access-token --tenant $tenant --resource https://graph.microsoft.com --query accessToken -o tsv --only-show-errors 2>$null
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Graph token command failed; no login diagnosis or secret fallback.'}
$headers=@{Authorization="Bearer $token"}
function Graph([string]$Path,[string]$Method='GET',$Body=$null){
  $args=@{Uri="https://graph.microsoft.com/v1.0/$Path";Headers=$headers;Method=$Method}
  if($null -ne $Body){$args.ContentType='application/json';$args.Body=$Body|ConvertTo-Json -Depth 25 -Compress}
  try{Invoke-RestMethod @args}catch{throw 'Resource-directory Graph operation failed; response omitted.'}
}
function GraphList([string]$Path){
  $result=Graph $Path
  if($result.PSObject.Properties['@odata.nextLink']){throw 'Directory result exceeds bounded preflight; review manually.'}
  @($result.value)
}
try{
  $issuer="https://login.microsoftonline.com/$tenant/v2.0"
  $discovery=Invoke-RestMethod "$issuer/.well-known/openid-configuration"
  if($discovery.issuer -ne $issuer -or -not $discovery.jwks_uri.StartsWith('https://login.microsoftonline.com/')){throw 'Resource issuer/key discovery mismatch.'}
  $name='Bloomstep spend guard (read-only operations)'
  $tag="Bloomstep-spend-guard:$Repository`:$subscription`:$ResourceGroup"
  $apps=@(GraphList "applications?`$filter=displayName eq '$name'")
  if($apps.Count -gt 1){throw 'Ambiguous guard applications.'}
  $roleId=if($apps.Count -and @($apps[0].appRoles).Count){$apps[0].appRoles[0].id}else{[guid]::NewGuid().ToString()}
  $role=@{id=$roleId;value='Bloomstep.SpendGuard';displayName='Bloomstep Spend Guard';description='Only one-way internal application pause';isEnabled=$true;allowedMemberTypes=@('Application')}
  $settings=@{signInAudience='AzureADMyOrg';api=@{requestedAccessTokenVersion=2};appRoles=@($role)}
  if($apps.Count){
    $app=$apps[0]
    if($app.tags -notcontains $tag -or $app.signInAudience -ne 'AzureADMyOrg' -or @($app.passwordCredentials).Count -or @($app.keyCredentials).Count -or @($app.requiredResourceAccess).Count){throw 'Existing guard binding/credentials/permissions mismatch.'}
    if(@($app.appRoles).Count -ne 1 -or $app.appRoles[0].value -ne 'Bloomstep.SpendGuard' -or @($app.appRoles[0].allowedMemberTypes).Count -ne 1 -or $app.appRoles[0].allowedMemberTypes[0] -ne 'Application'){throw 'Existing guard role mismatch.'}
    $null=Graph "applications/$($app.id)" 'PATCH' $settings
  }else{
    $settings.displayName=$name;$settings.tags=@('Bloomstep-managed-free',$tag)
    $app=Graph 'applications' 'POST' $settings
  }
  $null=Graph "applications/$($app.id)" 'PATCH' @{identifierUris=@("api://$($app.appId)")}
  $principals=@(GraphList "servicePrincipals?`$filter=appId eq '$($app.appId)'")
  if($principals.Count -gt 1){throw 'Duplicate guard service principals.'}
  $sp=if($principals.Count){$principals[0]}else{Graph 'servicePrincipals' 'POST' @{appId=$app.appId}}
  $assignments=@(GraphList "servicePrincipals/$($sp.id)/appRoleAssignments")
  if(@($assignments|Where-Object{$_.resourceId -ne $sp.id -or $_.appRoleId -ne $roleId}).Count){throw 'Unexpected guard application grants; review manually.'}
  if(-not $assignments.Count){$null=Graph "servicePrincipals/$($sp.id)/appRoleAssignments" 'POST' @{principalId=$sp.id;resourceId=$sp.id;appRoleId=$roleId}}
  $fics=@(GraphList "applications/$($app.id)/federatedIdentityCredentials")
  if(@($fics|Where-Object{$_.name -ne 'github-spend-guard' -or $_.issuer -ne 'https://token.actions.githubusercontent.com' -or $_.subject -ne $subject -or @($_.audiences).Count -ne 1 -or $_.audiences[0] -ne 'api://AzureADTokenExchange'}).Count){throw 'Unexpected federated trust; no legacy-subject migration performed.'}
  if(-not $fics.Count){$null=Graph "applications/$($app.id)/federatedIdentityCredentials" 'POST' @{name='github-spend-guard';issuer='https://token.actions.githubusercontent.com';subject=$subject;audiences=@('api://AzureADTokenExchange')}}
  $rgScope="/subscriptions/$subscription/resourceGroups/$ResourceGroup"
  $subScope="/subscriptions/$subscription"
  $reader='acdd72a7-3385-48ef-bd42-f606fba81ae7'
  $costReader='72fafb9e-0641-4937-9268-a91bfd8191a3'
  $existing=@(Azure @('role','assignment','list','--subscription',$subscription,'--assignee-object-id',$sp.id,'--all','--fill-principal-name','false','--fill-role-definition-name','false'))
  foreach($assignment in $existing){
    $roleGuid=($assignment.roleDefinitionId -split '/')[-1]
    if(-not (($assignment.scope -eq $rgScope -and $roleGuid -eq $reader) -or ($assignment.scope -eq $subScope -and $roleGuid -eq $costReader))){throw 'Guard has unexpected RBAC elevation; review manually.'}
  }
  foreach($grant in @(@{scope=$rgScope;role=$reader},@{scope=$subScope;role=$costReader})){
    if(-not @($existing|Where-Object{$_.scope -eq $grant.scope -and ($_.roleDefinitionId -split '/')[-1] -eq $grant.role}).Count){
      $null=Azure @('role','assignment','create','--subscription',$subscription,'--assignee-object-id',$sp.id,'--assignee-principal-type','ServicePrincipal','--role',$grant.role,'--scope',$grant.scope)
    }
  }
  $null=& az staticwebapp appsettings set --subscription $subscription --resource-group $ResourceGroup --name $SwaName --setting-names `
    "SPEND_GUARD_OIDC_ISSUER=$issuer" "SPEND_GUARD_OIDC_AUDIENCE=$($app.appId)" "SPEND_GUARD_OIDC_JWKS_URI=$($discovery.jwks_uri)" `
    --only-show-errors --output none 2>$null
  if($LASTEXITCODE -ne 0){throw 'Pinned guard settings write failed; response suppressed to avoid reading existing secrets.'}
  foreach($variable in @(
    @{name='GUARD_TENANT_ID';value=$tenant},@{name='GUARD_CLIENT_ID';value=$app.appId},
    @{name='GUARD_SUBSCRIPTION_ID';value=$subscription},@{name='GUARD_RESOURCE_GROUP';value=$ResourceGroup},
    @{name='GUARD_SWA_NAME';value=$SwaName},@{name='GUARD_COSMOS_NAME';value=$CosmosName}
    @{name='GUARD_CUSTOMER_DIRECTORY_NAME';value=$CustomerDirectoryName}
  )){
    $null=& gh variable set $variable.name --repo $Repository --env $Environment --body $variable.value 2>$null
    if($LASTEXITCODE -ne 0){throw 'Public guard environment variable write failed; rerun after review.'}
  }
  'Dedicated guard/FIC, explicit role, RG Reader/subscription Cost Management Reader and public config prepared. No customer M2M, data keys, upgrades or purchases.'
}finally{$token=$null;$headers=$null}
