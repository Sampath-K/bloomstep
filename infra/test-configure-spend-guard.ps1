$ErrorActionPreference='Stop'
$global:guardApp=$null;$global:guardSp=$null
$global:guardGrants=@();$global:guardFics=@();$global:guardRbac=@()
$global:guardMutations=0;$global:guardSettings=0;$global:wrongTenant=$false
$tenant='22222222-2222-4222-8222-222222222222'
$subscription='11111111-1111-4111-8111-111111111111'
function global:az {
  $global:LASTEXITCODE=0
  if($args[0] -eq 'account' -and $args[1] -eq 'get-access-token'){
    if($args -contains '--subscription' -or $args -notcontains '--tenant'){throw 'Graph token tenant exclusivity failed'}
    return 'offline-guard-token'
  }
  if($args -notcontains '--subscription'){throw 'Explicit ARM subscription missing'}
  if($args[0] -eq 'account'){
    $bound=if($global:wrongTenant){'33333333-3333-4333-8333-333333333333'}else{'22222222-2222-4222-8222-222222222222'}
    return (@{id='11111111-1111-4111-8111-111111111111';tenantId=$bound;state='Enabled'}|ConvertTo-Json)
  }
  if($args[0] -eq 'rest'){
    if(($args -join ' ') -match '/ciamDirectories/'){return '{"name":"bloomstepcustomers261004","sku":{"name":"Base","tier":"A0"}}'}
    return '{"subscriptionPolicies":{"quotaId":"FreeTrial_2014-09-01","spendingLimit":"On"}}'
  }
  if($args[0] -eq 'cosmosdb'){
    if($args -contains 'throughput'){return '{"resource":{"throughput":400}}'}
    return '{"enableFreeTier":true,"locations":[{}]}'
  }
  if($args[0] -eq 'staticwebapp'){
    if($args[1] -eq 'appsettings'){
      if($args -contains 'list' -or $args -contains 'show'){throw 'Secret settings read forbidden'}
      if($args -notcontains 'none' -or @($args|Where-Object{$_ -like 'SPEND_GUARD_OIDC_*=*'}).Count -ne 3){throw 'Only three pinned writes with suppressed output allowed'}
      $global:guardSettings++;return
    }
    return '{"sku":{"name":"Free"},"defaultHostname":"mock.azurestaticapps.net"}'
  }
  if($args[0] -eq 'role'){
    if($args[2] -eq 'list'){return (ConvertTo-Json -InputObject @($global:guardRbac) -Depth 10)}
    $role=$args[([array]::IndexOf($args,'--role')+1)]
    $scope=$args[([array]::IndexOf($args,'--scope')+1)]
    if($role -notin @('acdd72a7-3385-48ef-bd42-f606fba81ae7','72fafb9e-0641-4937-9268-a91bfd8191a3')){throw 'Unexpected elevated role'}
    $global:guardRbac+=@{scope=$scope;roleDefinitionId="/roles/$role"};$global:guardMutations++
    return '{}'
  }
  throw 'Unexpected Azure command'
}
function global:gh {
  $global:LASTEXITCODE=0
  if($args[0] -eq 'variable'){return}
  $path=$args[1]
  if($path -match 'API_ORIGIN'){return '{"value":"https://mock.azurestaticapps.net"}'}
  if($path -match 'customization'){return '{"use_default":true}'}
  if($path -match 'deployment-branch-policies'){return '{"total_count":2,"branch_policies":[{"name":"main","type":"branch"},{"name":"sampath-k-bloomstep-mvp-implementation","type":"branch"}]}'}
  if($path -match '/environments/'){return '{"deployment_branch_policy":{"custom_branch_policies":true}}'}
  return '{"full_name":"Sampath-K/bloomstep","id":1404357574,"name":"bloomstep","owner":{"login":"Sampath-K","id":72682617}}'
}
function global:Invoke-RestMethod {
  param($Uri,$Headers,$Method='GET',$ContentType,$Body)
  if($Uri -match 'openid-configuration'){return @{issuer='https://login.microsoftonline.com/22222222-2222-4222-8222-222222222222/v2.0';jwks_uri='https://login.microsoftonline.com/22222222-2222-4222-8222-222222222222/discovery/v2.0/keys'}}
  if($Headers.Authorization -ne 'Bearer offline-guard-token'){throw 'Offline Graph token missing'}
  $b=if($Body){$Body|ConvertFrom-Json}else{$null}
  if($Uri -match 'appRoleAssignments'){
    if($Method -eq 'POST'){$global:guardGrants+=@{resourceId=$b.resourceId;appRoleId=$b.appRoleId};$global:guardMutations++;return $b}
    return [pscustomobject]@{value=@($global:guardGrants)}
  }
  if($Uri -match 'federatedIdentityCredentials'){
    if($Method -eq 'POST'){
      if($b.subject -ne 'repo:Sampath-K@72682617/bloomstep@1404357574:environment:bloomstep-operations'){throw 'Immutable FIC subject mismatch'}
      $global:guardFics+= $b;$global:guardMutations++;return $b
    }
    return [pscustomobject]@{value=@($global:guardFics)}
  }
  if($Uri -match 'servicePrincipals'){
    if($Method -eq 'POST'){$global:guardSp=[pscustomobject]@{id='sp';appId=$b.appId};$global:guardMutations++;return $global:guardSp}
    return [pscustomobject]@{value=@($global:guardSp|Where-Object{$_})}
  }
  if($Uri -match 'applications'){
    if($Method -eq 'POST'){
      if($b.api.requestedAccessTokenVersion -ne 2 -or $b.appRoles[0].allowedMemberTypes[0] -ne 'Application' -or $b.appRoles[0].value -ne 'Bloomstep.SpendGuard'){throw 'Role/token contract mismatch'}
      $global:guardApp=[pscustomobject]@{id='app';appId='44444444-4444-4444-8444-444444444444';tags=$b.tags;signInAudience=$b.signInAudience;appRoles=$b.appRoles;passwordCredentials=@();keyCredentials=@();requiredResourceAccess=@()}
      $global:guardMutations++;return $global:guardApp
    }
    if($Method -eq 'PATCH'){return}
    return [pscustomobject]@{value=@($global:guardApp|Where-Object{$_})}
  }
  throw 'Unexpected Graph call'
}
try{
  $params=@{ResourceTenantId=$tenant;SubscriptionId=$subscription;ResourceGroup='mock';SwaName='mock';CosmosName='mockcosmos';CustomerDirectoryName='bloomstepcustomers261004';Repository='Sampath-K/bloomstep';Environment='bloomstep-operations';ConfirmPersonalResourceTenant=$true}
  $script=Join-Path $PSScriptRoot 'configure-spend-guard.ps1'
  for($i=0;$i -lt 2;$i++){$null=& $script @params}
  if($global:guardMutations -ne 6 -or $global:guardSettings -ne 2){throw 'Idempotency or pinned settings writes failed'}
  $global:wrongTenant=$true
  try{$null=& $script @params;throw 'Expected tenant mismatch'}catch{if($_.Exception.Message -notmatch 'tenant binding mismatch'){throw}}
  if($global:guardMutations -ne 6){throw 'Mutation before subscription validation'}
  'Offline guard provisioning: two idempotent passes, immutable subject, app-only self-role, least-reader scopes, no secret reads and wrong-tenant fail-closed passed.'
}finally{
  Remove-Item Function:\az,Function:\gh,Function:\Invoke-RestMethod
  Remove-Variable guardApp,guardSp,guardGrants,guardFics,guardRbac,guardMutations,guardSettings,wrongTenant -Scope Global
}
