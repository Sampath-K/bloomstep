function Test-InnoApplicationProxy(
  [string]$Class, [object]$Description, [object]$HasVisibleChildren,
  [uint32]$ProcessId, [uint32[]]$WizardOwners
) {
  return $Class -ceq 'TApplication' -and
    $Description -is [string] -and $Description.Length -eq 0 -and
    $HasVisibleChildren -is [bool] -and -not $HasVisibleChildren -and
    $ProcessId -gt 0 -and $WizardOwners -contains $ProcessId
}
