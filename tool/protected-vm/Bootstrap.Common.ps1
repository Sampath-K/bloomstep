Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-TransientDownloadFailure([int]$Status, [string]$Transport) {
  if ($Status -ne 0) { return $Status -in @(408, 429, 500, 502, 503, 504) }
  return $Transport -in @('Timeout', 'ConnectFailure', 'ConnectionClosed', 'ReceiveFailure', 'SendFailure')
}

function Invoke-BoundedDownloadAttempt {
  param([scriptblock]$Operation, [scriptblock]$Retryable,
    [scriptblock]$Sleep = { param($seconds) Start-Sleep -Seconds $seconds })
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { return (& $Operation) } catch {
      if ($attempt -eq 3 -or -not (& $Retryable $_)) { throw }
      & $Sleep ([int][Math]::Pow(2, $attempt))
    }
  }
}

function Get-InnoExitDisposition([int]$Code) {
  if ($Code -eq 0) { return 'Installed' }
  if ($Code -eq 3010) { return 'RestartRequired' }
  throw 'Dependency installer failed. Preserve receipt and inspect Windows setup locally; do not bypass protection.'
}

function New-BootstrapReceipt([string]$Stage, [string]$Source, [string]$Arch) {
  return [ordered]@{
    kind = 'bloomstep-vm-bootstrap-v1'; time = [DateTime]::UtcNow.ToString('o')
    stage = $Stage; source = $Source; nativeArchitecture = $Arch
    complete = $false; registrationAuthorized = $false; installerAcceptanceVerified = $false
    nextAction = 'Rerun the same Bootstrap.ps1 -Resume after resolving the reported prerequisite.'
  }
}

function Confirm-Bootstrap([string]$Message, [string]$Answer) {
  if ((Read-Host "$Message Type $Answer") -cne $Answer) {
    throw 'Operator declined required action; nothing further is authorized.'
  }
}

function Assert-PackageInventory([string]$Root) {
  $manifest = Get-Content -LiteralPath (Join-Path $Root 'package-manifest.json') -Raw | ConvertFrom-Json
  if ($manifest.source -notmatch '^[a-f0-9]{40}$') { throw 'Package source identity missing.' }
  foreach ($file in $manifest.files) {
    if ($file.path -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') { throw 'Unsafe package inventory path.' }
    $path = Join-Path $Root $file.path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
      throw 'Package inventory mismatch. Download the pinned ZIP again; do not bypass.'
    }
  }
  return $manifest
}

function Get-PinnedDownload($Asset, [string]$Directory) {
  New-Item -ItemType Directory -Force -Path $Directory | Out-Null
  $uri = [uri]$Asset.url
  if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('github.com', 'nodejs.org') -or
      $Asset.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid pinned download authority.' }
  $target = Join-Path $Directory ($Asset.sha256 + '-' + [IO.Path]::GetFileName($uri.AbsolutePath))
  if (Test-Path -LiteralPath $target) {
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Asset.sha256) {
      throw 'Cached download hash mismatch. Stop and investigate; no retry or security override.'
    }
    return $target
  }
  $partial = $target + '.partial'
  $operation = {
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $partial -TimeoutSec 180 -ErrorAction Stop | Out-Null
  }.GetNewClosure()
  $retryable = {
    param($failure)
    $status = 0; $transport = ''
    $exception = $failure.Exception
    if ($exception -is [Net.WebException]) {
      $transport = $exception.Status.ToString()
      if ($exception.Response) { $status = [int]$exception.Response.StatusCode }
    } elseif ($exception.PSObject.Properties['Response'] -and $exception.Response) {
      $status = [int]$exception.Response.StatusCode
    }
    return Test-TransientDownloadFailure $status $transport
  }
  try {
    Invoke-BoundedDownloadAttempt $operation $retryable
    if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Asset.sha256) {
      throw 'Official download SHA256 mismatch. Do not execute, retry or override protection.'
    }
    Move-Item -LiteralPath $partial -Destination $target
  } finally {
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
  }
  return $target
}

function Expand-VerifiedPortable([string]$Archive, [string]$Destination) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $complete = Test-Path -LiteralPath $Destination
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') { throw 'Unsafe archive path.' }
      if (-not $entry.Name) { continue }
      $path = Join-Path $Destination $entry.FullName
      if (-not (Test-Path -LiteralPath $path)) { $complete = $false; continue }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $expected = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
      finally { $stream.Dispose(); $sha.Dispose() }
      if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
        throw 'Portable tool changed after extraction. Restore the clean checkpoint; no silent replacement.'
      }
    }
  } finally { $zip.Dispose() }
  if (-not $complete) {
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
  }
}
