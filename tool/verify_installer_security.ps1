param(
  [Parameter(Mandatory)][string]$CandidateDir,
  [Parameter(Mandatory)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$report = [ordered]@{
  kind = 'isolated-defender-static-capability-and-scan-not-behavior-acceptance'
  sourceRevision = '3cd29f0b635e5fdce2a2f9ade939024416216401'
  candidateSha256 = 'b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5'
  localBehaviorQuarantine = 'CONFIRMED; candidate remains withdrawn regardless of static scan'
  nonElevatedExecution = 'NOT ATTEMPTED; hosted-token capability recorded, not emulated'
  outcome = 'preflight-incomplete'
  startedAt = [DateTime]::UtcNow.ToString('o')
  detectionIds = @()
  payloadFiles = @()
}
try {
  if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
    throw 'Security scan is restricted to a disposable GitHub-hosted runner.'
  }
  $root = [IO.Path]::GetFullPath($CandidateDir)
  $temp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
  if (-not $root.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Security scan input must be under the disposable runner temporary directory.'
  }
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  $report.hostElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $report.interactiveSession = [Environment]::UserInteractive
  $requiredCommands = 'Get-MpComputerStatus', 'Start-MpScan', 'Get-MpThreatDetection'
  $report.commandsAvailable = @($requiredCommands | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue })
  if ($report.commandsAvailable.Count -ne $requiredCommands.Count) {
    throw 'Defender protection unavailable or inactive: required cmdlets absent.'
  }
  $status = Get-MpComputerStatus
  $report.protection = @{
    antivirus = $status.AntivirusEnabled
    realTime = $status.RealTimeProtectionEnabled
    behavior = $status.BehaviorMonitorEnabled
    service = $status.AMServiceEnabled
    mode = $status.AMRunningMode
    engineVersion = $status.AMEngineVersion
    productVersion = $status.AMProductVersion
    signatureVersion = $status.AntivirusSignatureVersion
    signatureUpdatedAt = $status.AntivirusSignatureLastUpdated
  }
  if (-not $status.AntivirusEnabled -or -not $status.RealTimeProtectionEnabled -or
      -not $status.BehaviorMonitorEnabled -or -not $status.AMServiceEnabled -or
      $status.AMRunningMode -ne 'Normal') {
    throw 'Defender protection unavailable or inactive: active antivirus, behavior and real-time protection required.'
  }
  $installerName = 'Bloomstep-0.1.0-preview-windows-universal-zeroclick-setup.exe'
  $installer = Join-Path $root "candidate\$installerName"
  $manifest = Get-Content (Join-Path $root 'candidate\universal-manifest.json') -Raw | ConvertFrom-Json
  if ($manifest.source -ne $report.sourceRevision -or $manifest.installFlow -ne 'zeroclick' -or
      $manifest.installerSha256 -ne $report.candidateSha256) {
    throw 'Exact withdrawn candidate source/flow/hash manifest mismatch.'
  }
  $report.actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLower()
  if ($report.actualSha256 -ne $report.candidateSha256) { throw 'Exact withdrawn EXE hash mismatch.' }
  $report.signatureStatus = (Get-AuthenticodeSignature -LiteralPath $installer).Status.ToString()
  foreach ($arch in 'x64','arm64') {
    $payload = Join-Path $root "payload-$arch"
    $files = @(Get-ChildItem -LiteralPath $payload -Recurse -File)
    if (-not ($files | Where-Object Name -eq 'bloomstep.exe')) { throw "Missing $arch app payload." }
    $report.payloadFiles += @($files | ForEach-Object {
      @{ architecture = $arch; file = [IO.Path]::GetRelativePath($payload, $_.FullName)
        bytes = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() }
    })
  }
  $baseline = @(Get-MpThreatDetection | ForEach-Object DetectionID)
  $report.scanStartedAt = [DateTime]::UtcNow.ToString('o')
  Start-MpScan -ScanType CustomScan -ScanPath $root
  $detections = @(Get-MpThreatDetection | Where-Object {
    $_.DetectionID -notin $baseline -or
    @($_.Resources | Where-Object { $_.IndexOf($root, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0
  })
  $report.detectionIds = @($detections | ForEach-Object {
    @{ detectionId = $_.DetectionID; threatId = $_.ThreatID
      detectedAt = $_.InitialDetectionTime; actionSuccess = $_.ActionSuccess }
  })
  if ($detections.Count -gt 0) { throw 'Defender detected threats; no execution or distribution permitted.' }
  $after = Get-MpComputerStatus
  if (-not $after.AntivirusEnabled -or -not $after.RealTimeProtectionEnabled -or
      -not $after.BehaviorMonitorEnabled -or $after.AMRunningMode -ne 'Normal') {
    throw 'Defender protection unavailable or inactive after scan.'
  }
  if (-not (Test-Path -LiteralPath $installer) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLower() -ne $report.candidateSha256) {
    throw 'Candidate absent or changed after scan; quarantine cannot be dismissed.'
  }
  $report.outcome = 'static-scan-completed-no-new-detection; local behavior block unresolved; distribution remains withdrawn'
} catch {
  $report.outcome = 'BLOCKED; security validation incomplete or detection present'
  $report.errorType = $_.Exception.GetType().FullName
  $report.error = $_.Exception.Message.Replace($CandidateDir, '[ISOLATED-CANDIDATE-DIR]')
  throw
} finally {
  $report.completedAt = [DateTime]::UtcNow.ToString('o')
  $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceDir 'defender-security-receipt.json') -Encoding utf8
}
