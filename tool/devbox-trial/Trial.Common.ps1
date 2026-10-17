Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DevBoxTrialReceipt([string]$Source, [string]$Architecture, [string]$InstallerSha256) {
  [ordered]@{
    schema = 2
    kind = 'bloomstep-devbox-installer-trial'
    evidenceClass = 'supplemental-manual-owner-trial'
    createdAt = [DateTime]::UtcNow.ToString('o')
    source = $Source
    architecture = $Architecture
    installerSha256 = $InstallerSha256
    stage = 'Created'
    outcome = 'NOT_STARTED'
    protectedGateStatus = 'UNVERIFIED'
    protectedGatesAccepted = $false
    releaseAuthorized = $false
    runnerRegistrationAuthorized = $false
    installerExecutionStarted = $false
    preflightPassed = $false
    recoveryMode = 'owned-product-uninstall; not machine rollback'
    machineRollbackAvailable = $false
    cleanupVerified = $false
    nextAction = 'Preflight and explicit execution confirmation are required. Only the owned product can be uninstalled; user data is preserved.'
  }
}

function Test-DevBoxTrialLaunchAllowed(
  [string]$Stage,
  [bool]$PreflightPassed,
  [bool]$ExecutionConfirmed
) {
  return ($Stage -eq 'Ready' -and $PreflightPassed -and $ExecutionConfirmed)
}

function Assert-NoReparsePath([string]$Path) {
  $current = [IO.Path]::GetFullPath($Path)
  while ($current) {
    if (Test-Path -LiteralPath $current) {
      if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Reparse-point install/uninstaller path is ambiguous; no product operation authorized.'
      }
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ($parent -eq $current) { break }
    $current = $parent
  }
}

function Assert-OwnedUninstaller($Owner, [string]$ExpectedTarget, [string]$Sid, [string]$CandidateHash) {
  $target = [IO.Path]::GetFullPath($ExpectedTarget).TrimEnd('\','/')
  if ([IO.Path]::GetFullPath($Owner.installTarget).TrimEnd('\','/') -cne $target -or
      $Owner.installingSid -cne $Sid -or $Owner.installerSha256 -cne $CandidateHash) {
    throw 'Installation ownership/path/user/candidate mismatch; no uninstall authorized.'
  }
  Assert-NoReparsePath $target
  foreach ($file in @(
    @{name='unins000.exe'; hash=$Owner.uninstallerSha256},
    @{name='unins000.dat'; hash=$Owner.uninstallDataSha256}
  )) {
    $path = Join-Path $target $file.name
    Assert-NoReparsePath $path
    if ($file.hash -notmatch '^[a-f0-9]{64}$' -or
        -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.hash) {
      throw 'Owned uninstaller or its installation log changed/missing; no uninstall authorized.'
    }
  }
  return (Join-Path $target 'unins000.exe')
}

function Assert-UninstallResult([int]$ExitCode, [bool]$ExecutableRemains, [bool]$RegistrationRemains, [bool]$ProcessRemains) {
  if ($ExitCode -ne 0 -or $ExecutableRemains -or $RegistrationRemains -or $ProcessRemains) {
    throw 'Uninstall failed, requires restart, or left executable/registration/process state. Nothing is deleted or retried automatically.'
  }
}

function Get-DevBoxTrialOutcome(
  [int]$InstallerExitCode,
  [bool]$PayloadVerified,
  [bool]$WizardConfirmed,
  [bool]$AppConfirmed
) {
  if ($InstallerExitCode -ne 0) { return 'INSTALLER_FAILED' }
  if (-not $PayloadVerified) { return 'INSTALLED_PAYLOAD_FAILED' }
  if (-not $WizardConfirmed -or -not $AppConfirmed) { return 'INCOMPLETE_OWNER_OBSERVATION' }
  return 'SUPPLEMENTAL_OWNER_TRIAL_COMPLETE'
}

function Save-DevBoxTrialReceipt([string]$Path, $Receipt) {
  $temporary = "$Path.tmp"
  $Receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Assert-VerifiedPortableCache([string]$Archive, [string]$Destination, [string]$ExpectedArchiveSha256) {
  if (-not (Test-Path -LiteralPath $Archive -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant() -ne $ExpectedArchiveSha256) {
    throw 'Cached portable-tool archive is missing or changed; preserve it and stop.'
  }
  if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    throw 'Cached portable-tool extraction is missing; preserve it and stop.'
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  $expectedPaths = @()
  try {
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') {
        throw 'Cached portable-tool archive contains an unsafe path.'
      }
      if (-not $entry.Name) { continue }
      $relative = $entry.FullName.Replace('\','/')
      $path = Join-Path $Destination $entry.FullName
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Cached portable-tool extraction is incomplete; preserve it and stop.'
      }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $expectedHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
      finally { $stream.Dispose(); $sha.Dispose() }
      if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw 'Cached portable-tool file changed; preserve it and stop.'
      }
      $expectedPaths += $relative
    }
  } finally { $zip.Dispose() }
  $rootPath = $Destination.TrimEnd('\','/')
  $actualPaths = @(Get-ChildItem -LiteralPath $rootPath -File -Recurse | ForEach-Object {
    $_.FullName.Substring($rootPath.Length + 1).Replace('\','/')
  } | Sort-Object -Unique)
  if (($actualPaths -join '|') -ne (@($expectedPaths | Sort-Object -Unique) -join '|')) {
    throw 'Cached portable-tool extraction has unexpected or missing files; preserve it and stop.'
  }
  return $true
}

function Assert-InstalledPayload([string]$Target, [string]$Architecture, [string]$PackageRoot, $UniversalManifest) {
  $manifestPath = Join-Path $PackageRoot "payload-manifest-$Architecture.json"
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
  if ($manifest.arch -ne $Architecture -or $manifest.source -ne $UniversalManifest.source -or
      $UniversalManifest.payloadManifests.$Architecture -ne $manifestHash) {
    throw 'Installed payload architecture/source manifest mismatch.'
  }
  foreach ($file in $manifest.files) {
    if ($file.path -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))' -or
        $file.sha256 -notmatch '^[a-f0-9]{64}$' -or
        -not (Test-Path -LiteralPath (Join-Path $Target $file.path) -PathType Leaf)) {
      throw "Installed payload file missing or unsafe: $($file.path)"
    }
    $path = Join-Path $Target $file.path
    if ((Get-Item -LiteralPath $path).Length -ne $file.bytes -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $file.sha256) {
      throw "Installed payload file hash/size mismatch: $($file.path)"
    }
  }
  return $manifest.files.Count
}
