$ErrorActionPreference='Stop'
$global:consoleApp=$null
$global:consoleSp=$null
$global:consoleGrants=@()
$global:consoleIncluded=@()
$global:consoleCreates=0
$global:rejectFlow=$false
function global:az {
  $global:LASTEXITCODE=0
  if($args[1] -eq 'get-access-token'){
    if($args -contains '--subscription'){throw 'Token exclusivity regression'}
    return 'offline-token'
  }
  if($args -notcontains '--subscription'){throw 'ARM subscription missing'}
  if($args[0] -eq 'account'){return '{"id":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222","state":"Enabled"}'}
  return '{"sku":{"name":"Free"},"defaultHostname":"mock.azurestaticapps.net"}'
}
function global:gh {
  $global:LASTEXITCODE=0
  if($args[0] -eq 'api'){return 'https://mock.azurestaticapps.net'}
}
function global:Invoke-RestMethod {
  param($Uri,$Headers,$Method='GET',$ContentType,$Body)
  if($Uri -match 'openid-configuration'){return @{issuer='https://customer.ciamlogin.com/33333333-3333-4333-8333-333333333333/v2.0';jwks_uri='https://customer.ciamlogin.com/keys'}}
  if($Headers.Authorization -ne 'Bearer offline-token'){throw 'Graph token missing'}
  $b=if($Body){$Body|ConvertFrom-Json}else{$null}
  if($Uri -match '/organization$'){return @{value=@(@{id='33333333-3333-4333-8333-333333333333'})}}
  if($Uri -match '/includeApplications'){
    if($global:rejectFlow){throw 'Offline unsupported association'}
    if($Method -eq 'POST'){$global:consoleIncluded=@($b);$global:consoleCreates++;return $b}
    return @{value=@($global:consoleIncluded)}
  }
  if($Uri -match '/authenticationEventsFlows/'){return @{id='flow'}}
  if($Uri -match '/oauth2PermissionGrants'){
    if($Method -eq 'POST'){
      if($b.scope -ne 'Garden.ReadWrite' -or $b.consentType -ne 'AllPrincipals'){throw 'Broad grant'}
      $global:consoleGrants=@($b);$global:consoleCreates++;return $b
    }
    return @{value=@($global:consoleGrants)}
  }
  if($Uri -match '/servicePrincipals'){
    if($Uri -match '44444444-4444-4444-8444-444444444444'){return @{value=@(@{id='api-sp'})}}
    if($Method -eq 'POST'){$global:consoleSp=@{id='console-sp';appId=$b.appId};$global:consoleCreates++;return $global:consoleSp}
    return @{value=@($global:consoleSp|Where-Object{$_})}
  }
  if($Uri -match '/applications'){
    if($Uri -match '44444444-4444-4444-8444-444444444444'){
      return @{value=@(@{api=@{oauth2PermissionScopes=@(@{value='Garden.ReadWrite';isEnabled=$true;id='scope-id'})}})}
    }
    if($Method -eq 'POST'){
      if($b.PSObject.Properties['passwordCredentials']){throw 'Secret creation'}
      $global:consoleApp=[pscustomobject]@{id='console-app';appId='55555555-5555-4555-8555-555555555555';tags=$b.tags;signInAudience=$b.signInAudience}
      $global:consoleCreates++;return $global:consoleApp
    }
    if($Method -eq 'PATCH'){
      if($b.spa.redirectUris[0] -ne 'https://mock.azurestaticapps.net/operator-callback.html' -or $b.isFallbackPublicClient){throw 'Wrong SPA binding'}
      return $null
    }
    return @{value=@($global:consoleApp|Where-Object{$_})}
  }
  throw 'Unexpected Graph path'
}
$parameters=@{
  CustomerTenantId='33333333-3333-4333-8333-333333333333'
  ResourceTenantId='22222222-2222-4222-8222-222222222222'
  SubscriptionId='11111111-1111-4111-8111-111111111111'
  ResourceGroup='mock';SwaName='mock';Repository='Sampath-K/bloomstep'
  ApiClientId='44444444-4444-4444-8444-444444444444'
  AuthenticationEventsFlowId='66666666-6666-4666-8666-666666666666'
  CustomerIssuer='https://customer.ciamlogin.com/33333333-3333-4333-8333-333333333333/v2.0'
  ConfirmPersonalSubscription=$true
}
try {
  $script=Join-Path $PSScriptRoot 'configure-console-identity.ps1'
  for($i=0;$i -lt 2;$i++){$null=& $script @parameters}
  if($global:consoleCreates -ne 4){throw 'SPA/SP/grant/association duplicates'}
  $global:rejectFlow=$true
  try {$null=& $script @parameters;throw 'Expected association failure'}
  catch {if($_.Exception.Message -notmatch 'association must succeed'){throw}}
  if($global:consoleCreates -ne 4){throw 'Mutation before association preflight'}
  'Offline console provisioning: idempotency, narrow consent, exact callback, exclusive token args and unsupported-flow fail-closed passed.'
} finally {
  Remove-Item Function:\az,Function:\gh,Function:\Invoke-RestMethod
  Remove-Variable consoleApp,consoleSp,consoleGrants,consoleIncluded,consoleCreates,rejectFlow -Scope Global
}
