function Get-BloomstepFederationCallbacks {
  param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Subdomain,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+\.onmicrosoft\.com$')][string]$Domain
  )
  if ($Domain -ne "$Subdomain.onmicrosoft.com") { throw 'Customer domain and subdomain do not match.' }
  @(
    "https://$TenantId.ciamlogin.com/$TenantId/federation/oauth2",
    "https://$Subdomain.ciamlogin.com/$TenantId/federation/oauth2",
    "https://$Subdomain.ciamlogin.com/$Domain/federation/oauth2"
  )
}

function Merge-BloomstepFederationCallbacks {
  param(
    [AllowEmptyCollection()][string[]]$Existing = @(),
    [Parameter(Mandatory)][string[]]$Required
  )
  $callbacks = [Collections.Generic.List[string]]::new()
  foreach ($callback in (@($Existing) + @($Required))) {
    if (-not $callbacks.Contains($callback)) { $callbacks.Add($callback) }
  }
  $callbacks.ToArray()
}
