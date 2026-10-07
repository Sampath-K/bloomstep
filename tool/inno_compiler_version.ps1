function Get-InnoEngineVersion {
  param([Parameter(Mandatory)][string[]]$OutputLines)
  $versions = @($OutputLines | ForEach-Object {
    if ($_ -match '^Compiler engine version: Inno Setup (?<Version>\d+\.\d+\.\d+(?:\.\d+)?)(?: \(u\))?\s*$') {
      [version]$Matches.Version
    }
  })
  if ($versions.Count -ne 1) {
    throw 'Exactly one authoritative Inno compiler engine version banner is required.'
  }
  if ($versions[0] -lt [version]'6.3.0') {
    throw "Universal native OS routing requires Inno Setup 6.3 or newer; observed $($versions[0])."
  }
  return $versions[0]
}
