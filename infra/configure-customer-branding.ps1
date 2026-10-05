param(
  [Parameter(Mandatory)][ValidatePattern('^[a-f0-9-]{36}$')][string]$TenantId,
  [Parameter(Mandatory)][string]$LogoPath,
  [string]$IconPath,
  [switch]$ConfirmCustomerBranding
)
$ErrorActionPreference = 'Stop'
if (-not $ConfirmCustomerBranding) { throw 'Confirm the selected customer tenant branding change explicitly.' }
if (-not (Test-Path -LiteralPath $LogoPath)) { throw 'Bloomstep wordmark asset is missing.' }
$logo = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LogoPath).Path)
if ($logo.Length -lt 24 -or [Convert]::ToHexString($logo[0..7]) -ne '89504E470D0A1A0A') { throw 'Wordmark must be a PNG.' }
function PngDimension([int]$Offset) {
  [byte[]]$bytes = $logo[$Offset..($Offset + 3)]
  [Array]::Reverse($bytes)
  [BitConverter]::ToUInt32($bytes, 0)
}
if ((PngDimension 16) -gt 245 -or (PngDimension 20) -gt 36) { throw 'Wordmark exceeds the supported sign-in banner size.' }
if (-not $IconPath) { $IconPath = Join-Path (Split-Path $LogoPath) 'bloomstep-favicon.png' }
if (-not (Test-Path -LiteralPath $IconPath)) { throw 'Bloomstep favicon asset is missing.' }
$logo = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $IconPath).Path)
if ($logo.Length -lt 24 -or [Convert]::ToHexString($logo[0..7]) -ne '89504E470D0A1A0A' -or
  (PngDimension 16) -ne 32 -or (PngDimension 20) -ne 32) { throw 'Favicon must be a 32-by-32 PNG.' }
$token = az account get-access-token --tenant $TenantId --resource https://graph.microsoft.com --query accessToken -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Existing customer Graph authorization unavailable; no login or permission grant initiated.' }
$headers = @{ Authorization = "Bearer $token"; 'Accept-Language' = 'en-US' }
function Graph([string]$Path, [string]$Method = 'GET', $Body = $null) {
  $arguments = @{ Uri = "https://graph.microsoft.com/v1.0/$Path"; Headers = $headers; Method = $Method }
  if ($null -ne $Body) {
    $arguments.ContentType = 'application/json'
    $arguments.Body = $Body | ConvertTo-Json -Depth 20 -Compress
  }
  Invoke-RestMethod @arguments
}
try {
  $organizations = @( (Graph 'organization').value )
  if ($organizations.Count -ne 1 -or $organizations[0].id -ne $TenantId) { throw 'Graph is not bound to the selected customer tenant.' }
  $path = "organization/$TenantId/branding"
  try { $current = Graph $path }
  catch {
    if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
    $null = Graph "$path/localizations" 'POST' @{ id = 'en-US'; signInPageText = 'Welcome to Bloomstep.' }
    $current = Graph $path
  }
  $desired = [ordered]@{
    SignIn_Title = 'Sign in to Bloomstep'
    SignIn_Description = 'Sign in to keep your Bloomstep garden private and safe across devices.'
    SignUp_Title = 'Create your Bloomstep account'
    SignUp_Description = 'One tiny step. A private Bloomstep garden that grows with you.'
    AttributeCollection_Title = 'Your Bloomstep account'
    SisuOtc_Title = 'Verify your Bloomstep sign-in'
  }
  $text = "Bloomstep - one tiny step, a garden that grows with you. Microsoft hosts this secure sign-in at ciamlogin.com. Your chosen provider handles its credentials; Bloomstep never collects your password."
  # The parent alias follows Accept-Language. Locale 0 is the actual default.
  $targets = @("$path/localizations/0", "$path/localizations/en-US")
  foreach ($target in $targets) {
    try { $record = Graph $target }
    catch {
      if ([int]$_.Exception.Response.StatusCode -ne 404 -or $target -ne "$path/localizations/en-US") { throw }
      $null = Graph "$path/localizations" 'POST' @{ id = 'en-US'; signInPageText = $text }
      $record = Graph $target
    }
    $values = [ordered]@{}
    foreach ($entry in @($record.contentCustomization.attributeCollection)) {
      if ($entry.key) { $values[$entry.key] = $entry.value }
    }
    foreach ($key in $desired.Keys) { $values[$key] = $desired[$key] }
    $entries = @($values.Keys | ForEach-Object { @{ key = $_; value = $values[$_] } })
    $content = @{ attributeCollection = $entries }
    if ($record.contentCustomization.registrationCampaign) {
      $content.registrationCampaign = @($record.contentCustomization.registrationCampaign)
    }
    $null = Graph $target 'PATCH' @{ signInPageText = $text; contentCustomization = $content }
    $readback = Graph $target
    if ($readback.signInPageText -ne $text) { throw 'Branding readback mismatch for sign-in text.' }
    foreach ($key in $desired.Keys) {
      if (-not @($readback.contentCustomization.attributeCollection | Where-Object { $_.key -ceq $key -and $_.value -ceq $desired[$key] }).Count) {
        throw "Branding readback mismatch for $key."
      }
    }
    $null = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/$target/bannerLogo" -Headers $headers -Method PUT -ContentType 'image/png' -InFile $LogoPath
    $null = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/$target/favicon" -Headers $headers -Method PUT -ContentType 'image/png' -InFile $IconPath
    $assets = Graph $target
    if (-not $assets.bannerLogoRelativeUrl -or -not $assets.faviconRelativeUrl) {
      throw 'Branding readback mismatch for wordmark or favicon.'
    }
  }
  Write-Output 'Bloomstep default/en-US sign-in text, wordmark and favicon applied with text readback. Verify the actual isolated hosted page; no issuer, callback, provider secret, contact or license changed.'
} finally {
  Remove-Variable token, headers
}
