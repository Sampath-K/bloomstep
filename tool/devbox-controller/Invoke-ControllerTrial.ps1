$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$homeDirectory = $PSScriptRoot
. "$homeDirectory\Bootstrap.Common.ps1"
$null=Assert-PackageInventory $homeDirectory
. "$homeDirectory\harness\Run-InstallerTrial.ps1" -LoadHelpersOnly
# The helper loader defines the manual package's paths; use the controller's isolated state instead.
$root = $homeDirectory
$state = Join-Path $root 'state'
$receiptPath = Join-Path $state 'autonomous-trial.json'
$ownerPath = Join-Path $state 'installation-owner.json'
$output = Join-Path $env:RUNNER_TEMP 'bloomstep-controller-receipts'
New-Item -ItemType Directory -Force -Path $state,$output | Out-Null
$report = [ordered]@{
  kind='autonomous-supplemental-installer-trial'
  outcome='BLOCKED'; protectedGateStatus='UNVERIFIED'; protectedGatesAccepted=$false
  releaseAuthorized=$false; machineRestored=$false; cleanupVerified=$false
  productMutationStarted=$false
  ownerJourneyAcceptance='NOT_OBSERVED'; accessibilityAcceptance='NOT_ESTABLISHED'
  nextAction='Inspect the failing guard; no security warnings or state ambiguity may be bypassed.'
}
$receipt = $report
$lock = $null
$setup = $null
$owned = [Collections.Generic.HashSet[int]]::new()
try {
  $lock = [IO.File]::Open((Join-Path $state 'autonomous.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  if ($env:GITHUB_REPOSITORY -cne 'Sampath-K/bloomstep-vm-controller' -or
      $env:PRIVATE_REPOSITORY -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/main' -or
      $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:CONTROLLER_SOURCE -notmatch '^[a-f0-9]{40}$') {
    throw 'Only the owner-audited private controller main dispatch is authorized.'
  }
  Assert-InteractiveStandardUser
  Assert-NoInstallerProcess
  $native = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  $arch = switch ($native) { 'AMD64' {'x64'} 'ARM64' {'arm64'} default {throw 'Unsupported native architecture.'} }
  if ($arch -cne $env:EXPECTED_NATIVE_ARCHITECTURE) { throw 'Native architecture mismatch; emulation is not accepted.' }
  $report.architecture = $arch
  $report.controllerSource = $env:CONTROLLER_SOURCE
  $report.runId = $env:GITHUB_RUN_ID
  if (-not $env:CONTROLLER_TOKEN) { throw 'Private controller read token unavailable.' }
  $headers = @{Authorization="Bearer $env:CONTROLLER_TOKEN";Accept='application/vnd.github+json';'User-Agent'='bloomstep-controller'}
  $repo = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/Sampath-K/bloomstep-vm-controller' -TimeoutSec 60 -MaximumRedirection 0
  if (-not $repo.private -or $repo.full_name -cne 'Sampath-K/bloomstep-vm-controller') { throw 'Private-controller boundary changed.' }
  $policyResponse = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/Sampath-K/bloomstep-vm-controller/contents/controller/approved-candidates.json?ref=$env:CONTROLLER_SOURCE" -TimeoutSec 60 -MaximumRedirection 0
  $policy = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($policyResponse.content)) | ConvertFrom-Json
  $headers.Clear()
  $env:CONTROLLER_TOKEN = $null
  $matches = @($policy.candidates.PSObject.Properties | Where-Object Name -CEQ $env:APPROVED_CANDIDATE)
  if ($policy.schema -ne 1 -or $matches.Count -ne 1) { throw 'Candidate is not in the reviewed private policy.' }
  $candidate = $matches[0].Value
  if ($candidate.repository -cne 'Sampath-K/bloomstep' -or $candidate.source -notmatch '^[a-f0-9]{40}$' -or
      $candidate.installerSha256 -notmatch '^[a-f0-9]{64}$' -or $candidate.packageSha256 -notmatch '^[a-f0-9]{64}$' -or
      $candidate.installerFile -cne 'Bloomstep-0.1.0-preview-windows-universal-setup.exe') {
    throw 'Candidate policy shape is not supported by the pinned local harness.'
  }
  $report.candidate = $env:APPROVED_CANDIDATE
  $report.source = $candidate.source
  $report.installerSha256 = $candidate.installerSha256
  $previousTrial=$null
  if(Test-Path -LiteralPath $receiptPath){
    $previousTrial=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if(-not $previousTrial.cleanupVerified){throw 'Earlier autonomous run did not verify cleanup. Preserve state; no automatic retry/adoption.'}
  }
  $inputDirectory = Join-Path $env:RUNNER_TEMP 'bloomstep-controller-input'
  $provenance = Get-Content -LiteralPath (Join-Path $inputDirectory 'candidate-provenance.json') -Raw | ConvertFrom-Json
  if ($provenance.source -cne $candidate.source -or $provenance.candidate -cne $env:APPROVED_CANDIDATE -or
      $provenance.runId -cne $candidate.runId -or $provenance.packageSha256 -cne $candidate.packageSha256 -or
      $provenance.installerSha256 -cne $candidate.installerSha256 -or $provenance.protectedGatesAccepted -ne $false) {
    throw 'Hosted authorization receipt does not match committed approval.'
  }
  $archive = Join-Path $inputDirectory 'candidate.zip'
  if ((Get-FileSha256 $archive) -cne $candidate.packageSha256) { throw 'Transferred candidate package hash mismatch.' }
  # Extract data only; none of the candidate package's PowerShell or other executables are imported.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $candidateDirectory = Join-Path $state ("candidate-" + $candidate.installerSha256)
  Assert-NoReparsePath $candidateDirectory
  New-Item -ItemType Directory -Path $candidateDirectory -Force | Out-Null
  $zip = [IO.Compression.ZipFile]::OpenRead($archive)
  try {
    foreach ($name in @($candidate.installerFile,'universal-manifest.json',"payload-manifest-$arch.json")) {
      $entries = @($zip.Entries | Where-Object FullName -CEQ "bloomstep-devbox-installer-trial/$name")
      if ($entries.Count -ne 1) { throw 'Candidate archive has duplicate/missing approved data file.' }
      $destination=Join-Path $candidateDirectory $name
      if(Test-Path -LiteralPath $destination){
        $entryStream=$entries[0].Open()
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$expected=[BitConverter]::ToString($hash.ComputeHash($entryStream)).Replace('-','').ToLowerInvariant()}
        finally{$entryStream.Dispose();$hash.Dispose()}
        if((Get-FileSha256 $destination) -cne $expected){throw 'Cached candidate data changed. No silent replacement.'}
      }else{[IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$destination,$false)}
    }
  } finally { $zip.Dispose() }
  $installer = Join-Path $candidateDirectory $candidate.installerFile
  if ((Get-FileSha256 $installer) -cne $candidate.installerSha256) { throw 'Exact installer digest mismatch.' }
  $universal = Get-Content -LiteralPath (Join-Path $candidateDirectory 'universal-manifest.json') -Raw | ConvertFrom-Json
  if ($universal.source -cne $candidate.source -or $universal.installerSha256 -cne $candidate.installerSha256 -or
      $universal.kind -cne 'bloomstep-offline-universal-v1') { throw 'Installer manifest source authority mismatch.' }
  $target = Join-Path $env:LOCALAPPDATA 'Programs\Bloomstep'
  Assert-NoReparsePath $target
  Assert-NoOtherProductRegistration $false
  $footprint = Get-ProductFootprint $target
  $priorOwnedCleanup=$null -ne $previousTrial -and $previousTrial.cleanupVerified
  $targetOccupied=(Test-Path -LiteralPath $target) -and @(
    Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop
  ).Count -gt 0
  if ($footprint.executableRemains -or $footprint.registrationRemains -or $footprint.processRemains -or
      $targetOccupied -or ((Test-Path -LiteralPath $target) -and -not $priorOwnedCleanup) -or
      ((Test-Path -LiteralPath $ownerPath) -and -not $priorOwnedCleanup)) {
    throw 'Unowned or unresolved prior product state; never adopt or overwrite.'
  }
  $report.userDataBefore = Get-ResidualData
  if ($report.userDataBefore.localAppDataPresent -or $report.userDataBefore.roamingAppDataPresent -or
      $report.userDataBefore.flutterDataPresent -or $report.userDataBefore.applicationSupportDataPresent -or
      $report.userDataBefore.productSettingsPresent) {
    if(-not $priorOwnedCleanup){throw 'Preexisting user data is preserved; clean-data assertions unavailable.'}
    $report.preservedPriorTrialData=$true
  }
  $report.cleanUserDataClaim=$false
  $baseline = Get-DefenderSnapshot
  Start-MpScan -ScanType CustomScan -ScanPath $installer -ErrorAction Stop
  $scanned = Get-DefenderSnapshot
  if (@($scanned.detectionFingerprints | Where-Object { $_ -notin $baseline.detectionFingerprints }).Count) {
    throw 'Defender scan changed detection state. No execution.'
  }
  if ((Get-FileSha256 $installer) -cne $candidate.installerSha256) { throw 'Candidate changed during scan.' }
  & "$root\harness\verify_onboarding_wizard.ps1" -Installer $installer -EvidenceDir $output -LoadHelpersOnly
  . "$root\harness\universal_integrity_contract.ps1"
  Add-Type -Path "$root\harness\process_token_probe.cs"
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $journey = New-StandardWizardJourney
  $report.productMutationStarted=$true
  $report.stage='InstallerStartRequested'
  Save-DevBoxTrialReceipt $receiptPath $report
  $setup = Start-Process -FilePath $installer -ArgumentList '/SP- /NORESTART' -PassThru
  [void]$setup.Handle
  [void]$owned.Add($setup.Id)
  $report.stage='InstallerStarted'
  Save-DevBoxTrialReceipt $receiptPath $report
  $deadline = [DateTime]::UtcNow.AddMinutes(3)
  $wizard = $null
  while ([DateTime]::UtcNow -lt $deadline) {
    $processes = Get-CimInstance Win32_Process -ErrorAction Stop
    for ($iteration=0; $iteration -lt 5; $iteration++) {
      foreach ($process in $processes) {
        if ($owned.Contains([int]$process.ParentProcessId)) { [void]$owned.Add([int]$process.ProcessId) }
      }
    }
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$pidOwner=0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window,[ref]$pidOwner)
      if (-not $owned.Contains([int]$pidOwner)) { continue }
      $windowProcess=Get-Process -Id $pidOwner -ErrorAction Stop
      if($windowProcess.Path -ceq (Join-Path $target 'bloomstep.exe')){
        if($journey.finishClicks -ne 1){throw 'App started before explicit test-driver Finish.'}
        continue
      }
      if ([OnboardingWizard]::ClassName($window) -eq 'TApplication' -and
          -not [OnboardingWizard]::Describe($window) -and -not [OnboardingWizard]::HasVisibleChildren($window)) { continue }
      if ([OnboardingWizard]::ClassName($window) -ne 'TWizardForm') { throw 'Unexpected owned dialog/warning: no automatic override.' }
      if ($null -eq $wizard) { $wizard=Get-Process -Id $pidOwner; [void]$wizard.Handle }
      [void](Invoke-StandardWizardStep $window $journey $true)
    }
    if ($journey.finishClicks -eq 1 -and $null -ne $wizard -and $wizard.HasExited -and $setup.HasExited) { break }
    Start-Sleep -Milliseconds 200
  }
  if ($null -eq $wizard -or -not $wizard.HasExited -or -not $setup.HasExited) { throw 'Installer deadline exceeded; no process killed. Stop for review.' }
  Assert-StandardWizardJourney $journey $true
  if ($wizard.ExitCode -ne 0 -or $setup.ExitCode -ne 0) { throw 'Native installer launcher/wizard failed.' }
  $report.installedFiles = Assert-InstalledPayload $target $arch $candidateDirectory $universal
  Assert-TrialRegistration $target
  $owner = @{
    installTarget=$target; installingSid=$sid; installerSha256=$candidate.installerSha256
    uninstallerSha256=Get-FileSha256 (Join-Path $target 'unins000.exe')
    uninstallDataSha256=Get-FileSha256 (Join-Path $target 'unins000.dat')
  }
  Save-DevBoxTrialReceipt $ownerPath $owner
  $apps = @(Get-Process -Name bloomstep -ErrorAction SilentlyContinue)
  if ($apps.Count -ne 1 -or $apps[0].Path -cne (Join-Path $target 'bloomstep.exe') -or
      [ProcessTokenProbe]::Sid($apps[0].Id) -cne $sid -or [ProcessTokenProbe]::Elevated($apps[0].Id)) {
    throw 'Expected one exact-target same-user non-elevated app.'
  }
  $app=$apps[0]; [void]$app.Handle
  Start-Sleep -Seconds 10
  $app.Refresh()
  if ($app.HasExited -or $app.MainWindowHandle -eq [IntPtr]::Zero) { throw 'App did not retain a visible window for ten seconds.' }
  $report.visibleSameUserAppObserved=$true
  $report.nativeWizard=$journey
  $report.stage='CleanupRequired'
  Save-DevBoxTrialReceipt $receiptPath $report
  if (-not $app.CloseMainWindow() -or -not $app.WaitForExit(15000)) {
    throw 'App did not exit via normal WM_CLOSE. No force kill or uninstall; preserve state for review.'
  }
  if (Get-Process -Name bloomstep -ErrorAction SilentlyContinue) { throw 'App process remains. No force close or uninstall.' }
  $uninstaller = Assert-OwnedUninstaller $owner $target $sid $candidate.installerSha256
  Assert-TrialRegistration $target
  $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/NORESTART' -PassThru
  [void]$uninstall.Handle
  $uninstallOwned=[Collections.Generic.HashSet[int]]::new()
  [void]$uninstallOwned.Add($uninstall.Id)
  # Automate only the owned native Yes confirmation; never arbitrary warnings or prompts.
  $deadline=[DateTime]::UtcNow.AddSeconds(120)
  while (-not $uninstall.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    $processes=Get-CimInstance Win32_Process -ErrorAction Stop
    for($iteration=0;$iteration -lt 5;$iteration++){
      foreach($process in $processes){if($uninstallOwned.Contains([int]$process.ParentProcessId)){[void]$uninstallOwned.Add([int]$process.ProcessId)}}
    }
    foreach ($window in [OnboardingWizard]::Windows()) {
      [uint32]$pidOwner=0
      [void][OnboardingWizard]::GetWindowThreadProcessId($window,[ref]$pidOwner)
      if (-not $uninstallOwned.Contains([int]$pidOwner)) { continue }
      $text=[OnboardingWizard]::Describe($window)
      if ($text -match 'Are you sure you want to completely remove Bloomstep') {
        $yes=[OnboardingWizard]::Find($window,'Yes')
        if ($yes -eq [IntPtr]::Zero -or -not [OnboardingWizard]::PostMessage($yes,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) { throw 'Owned uninstall confirmation could not be invoked.' }
      } elseif ($text -match 'successfully removed from your computer') {
        $ok=[OnboardingWizard]::Find($window,'OK')
        if ($ok -eq [IntPtr]::Zero -or -not [OnboardingWizard]::PostMessage($ok,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) { throw 'Owned uninstall completion could not be acknowledged.' }
      } elseif ($text -and $text -notmatch 'Uninstalling|Please wait') { throw 'Unexpected uninstaller dialog; no override.' }
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $uninstall.HasExited) { throw 'Uninstall exceeded the 120-second deadline; no kill/retry.' }
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do{
    $footprint=Get-ProductFootprint $target
    if(-not ($footprint.executableRemains -or $footprint.registrationRemains -or $footprint.processRemains)){break}
    Start-Sleep -Milliseconds 200
  }while([DateTime]::UtcNow -lt $deadline)
  Assert-UninstallResult $uninstall.ExitCode $footprint.executableRemains $footprint.registrationRemains $footprint.processRemains
  $final=Get-DefenderSnapshot
  if (@($final.detectionFingerprints | Where-Object { $_ -notin $baseline.detectionFingerprints }).Count) { throw 'New/changed Defender detection; acceptance withheld.' }
  $report.cleanupVerified=$true
  $report.userDataAfter=Get-ResidualData
  $report.outcome='SUPPLEMENTAL_AUTOMATED_JOURNEY_AND_PRODUCT_REMOVAL'
  $report.nextAction='No protected acceptance. Later reviewed trials may preserve this trial data; unknown residual product files block execution. No data deletion.'
} catch {
  $report.failure='Blocked or failed; inspect restricted Actions log. No bypass, rollback or protected acceptance inferred.'
  throw
} finally {
  $env:CONTROLLER_TOKEN=$null
  $report.completedAt=[DateTime]::UtcNow.ToString('o')
  Save-DevBoxTrialReceipt (Join-Path $output 'supplemental-result.json') $report
  if($null -ne $lock -and $report.productMutationStarted){
    Save-DevBoxTrialReceipt $receiptPath $report
  }
  if ($null -ne $lock) { $lock.Dispose() }
}
