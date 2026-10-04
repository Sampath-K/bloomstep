$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'configure-aggregate-worker.ps1'
$errors = $null
$tokens = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
$global:workerProbeCalls = @()
function global:az {
  $global:workerProbeCalls += ,@($args)
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'account' -and $args[1] -eq 'show') {
    return '{"id":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222","state":"Enabled"}'
  }
  if ($args[0] -eq 'account' -and $args[1] -eq 'get-access-token') {
    if ($args -contains '--tenant' -and $args -contains '--subscription') {
      throw 'Azure CLI exclusive-argument regression: tenant and subscription supplied together.'
    }
    if ($args -notcontains '--tenant' -or $args -contains '--subscription') { throw 'Graph token must use only explicit tenant.' }
    $global:LASTEXITCODE = 1
    return ''
  }
  if ($args -notcontains '--subscription') { throw 'ARM operation missing explicit subscription.' }
  return '{"sku":{"name":"Free"},"defaultHostname":"mock.azurestaticapps.net"}'
}
function global:gh {
  $global:LASTEXITCODE = 0
  if ($args[1] -match 'API_ORIGIN') { return '{"value":"https://mock.azurestaticapps.net"}' }
  if ($args[1] -match 'oidc/customization') { return '{"use_default":true}' }
  if ($args[1] -eq 'repos/Sampath-K/bloomstep') {
    return '{"full_name":"Sampath-K/bloomstep","name":"bloomstep","id":456,"owner":{"login":"Sampath-K","id":123}}'
  }
  return '{}'
}
try {
  try {
    & $source -ResourceTenantId '22222222-2222-4222-8222-222222222222' `
      -SubscriptionId '11111111-1111-4111-8111-111111111111' `
      -ResourceGroup 'bloomstep-free' -SwaName 'bloomstep-free' `
      -Repository 'Sampath-K/bloomstep' -Environment 'bloomstep-operations' `
      -FeatureBranch 'sampath-k-bloomstep-mvp-implementation' -ConfirmPersonalResourceTenant
    throw 'Expected simulated token acquisition failure.'
  } catch {
    if ($_.Exception.Message -notmatch '^Graph token acquisition failed') { throw }
    if ($_.Exception.Message -match 'cached.*login.*required') { throw 'Token failure incorrectly diagnosed as missing login.' }
  }
  $tokenCalls = @($global:workerProbeCalls | Where-Object { $_[0] -eq 'account' -and $_[1] -eq 'get-access-token' })
  if ($tokenCalls.Count -ne 1) { throw 'Expected one exclusive-argument Graph token request.' }
  Write-Output 'Offline regression passed: tenant-only Graph token, explicit-subscription ARM checks, neutral token-failure diagnosis.'
} finally {
  Remove-Item Function:\az, Function:\gh
  Remove-Variable workerProbeCalls -Scope Global
}
