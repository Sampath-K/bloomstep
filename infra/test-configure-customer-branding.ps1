$ErrorActionPreference = 'Stop'
class OfflineBrandingHttpException : System.Exception {
  [object]$Response
  OfflineBrandingHttpException([int]$StatusCode) : base('Synthetic branding HTTP failure.') {
    $this.Response = @{ StatusCode = $StatusCode }
  }
}
$global:brandingTenant = '11111111-2222-4333-8444-555555555555'
$global:brandingRecord = $null
$global:brandingCreated = 0
$global:brandingWrites = 0
$global:brandingReadbackFailure = $false
$global:brandingTargets = @()
function global:az {
  $global:LASTEXITCODE = 0
  if ($args -contains '--subscription') { throw 'Graph token must target tenant only.' }
  return 'synthetic-token'
}
function global:Invoke-RestMethod {
  param($Uri, $Headers, $Method = 'GET', $ContentType, $Body, $InFile)
  if ($Uri -match '/organization$') { return @{ value = @(@{ id = $global:brandingTenant }) } }
  if ($Uri -match '/branding/localizations$' -and $Method -eq 'POST') {
    $definition = $Body | ConvertFrom-Json
    if (-not $definition.signInPageText) { throw 'Actual Graph requires at least one branding property on creation.' }
    $global:brandingCreated++
    $global:brandingRecord = @{ id = 'en-US'; signInPageText = ''; contentCustomization = @{ attributeCollection = @(@{ key = 'Preserved_Key'; value = 'Preserved value' }) } }
    return $global:brandingRecord
  }
  if ($Uri -match '/(?:bannerLogo|favicon)$' -and $Method -eq 'PUT') {
    $global:brandingWrites++
    if ($Uri -match '/bannerLogo$') { $global:brandingRecord.bannerLogoRelativeUrl = 'synthetic-wordmark' }
    else { $global:brandingRecord.faviconRelativeUrl = 'synthetic-icon' }
    return $null
  }
  if ($Uri -match '/branding(?:/localizations/(?:en-US|0))?$') {
    if ($null -eq $global:brandingRecord) {
      throw [OfflineBrandingHttpException]::new(404)
    }
    if ($Method -eq 'PATCH') {
      if ($Uri -match '/branding$') { throw 'Observed service requires the default branding locale endpoint, not the parent alias.' }
      $global:brandingTargets += $Uri
      $global:brandingWrites++
      if (-not $global:brandingReadbackFailure) {
        $record = $Body | ConvertFrom-Json
        $global:brandingRecord.signInPageText = $record.signInPageText
        $global:brandingRecord.contentCustomization = $record.contentCustomization
      }
    }
    return $global:brandingRecord
  }
  throw "Unexpected branding request: $Method $Uri"
}
try {
  $script = Join-Path $PSScriptRoot 'configure-customer-branding.ps1'
  $logo = Join-Path $PSScriptRoot '..\site\assets\bloomstep-wordmark.png'
  $parameters = @{ TenantId = $global:brandingTenant; LogoPath = $logo; ConfirmCustomerBranding = $true }
  $null = & $script @parameters
  $null = & $script @parameters
  if ($global:brandingCreated -ne 1) { throw 'Branding default was recreated.' }
  if (-not @($global:brandingTargets | Where-Object { $_ -match '/localizations/0$' }).Count -or
    -not @($global:brandingTargets | Where-Object { $_ -match '/localizations/en-US$' }).Count) { throw 'Default fallback and English must both be branded.' }
  $values = @($global:brandingRecord.contentCustomization.attributeCollection)
  if (-not @($values | Where-Object { $_.key -eq 'Preserved_Key' -and $_.value -eq 'Preserved value' }).Count) { throw 'Existing content lost.' }
  if (-not @($values | Where-Object { $_.key -eq 'SignIn_Title' -and $_.value -eq 'Sign in to Bloomstep' }).Count) { throw 'Sign-in title not branded.' }
  $before = $global:brandingWrites
  $global:brandingTenant = '66666666-7777-4888-8999-000000000000'
  try { $null = & $script @parameters; throw 'Wrong tenant accepted.' }
  catch { if ($_.Exception.Message -notmatch 'selected customer tenant') { throw } }
  if ($global:brandingWrites -ne $before) { throw 'Mutation before tenant verification.' }
  $global:brandingTenant = $parameters.TenantId
  $global:brandingReadbackFailure = $true
  $global:brandingRecord.signInPageText = 'Unchanged'
  try { $null = & $script @parameters; throw 'Bad readback accepted.' }
  catch { if ($_.Exception.Message -notmatch 'Branding readback mismatch') { throw } }
  'Offline branding: creation, preservation, exact product text, tenant boundary and failed readback passed.'
} finally {
  Remove-Item Function:\az, Function:\Invoke-RestMethod
  Remove-Variable brandingTenant, brandingRecord, brandingCreated, brandingWrites, brandingReadbackFailure, brandingTargets -Scope Global
}
