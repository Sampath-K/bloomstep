param(
  [Parameter(Mandatory=$true)][string]$Iscc,
  [Parameter(Mandatory=$true)][string]$EvidenceDir
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -ne 'true' -or
    $env:BUDLARK_DISPOSABLE_VM -ne 'true') {
  throw 'Upgrade simulation requires explicitly authorized disposable Windows CI, never customer state.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EvidenceDir = [IO.Path]::GetFullPath($EvidenceDir)
if (-not $EvidenceDir.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $EvidenceDir)) {
  throw 'Use a new evidence directory beneath this checkout.'
}
$fixtureId = '{A6690692-4D92-475A-9EAC-1AD867AB0635}_is1'
$key = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\$fixtureId"
$productKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}_is1'
$oldName = 'Prior product upgrade fixture'
$oldDir = Join-Path $env:LOCALAPPDATA "Programs\$oldName"
$newDir = Join-Path $env:LOCALAPPDATA 'Programs\Budlark'
$programs = [Environment]::GetFolderPath('Programs')
$desktop = [Environment]::GetFolderPath('Desktop')
$oldGroup = Join-Path $programs $oldName
$newGroup = Join-Path $programs 'Budlark'
$oldDesktop = Join-Path $desktop "$oldName.lnk"
$unrelatedDesktop = Join-Path $desktop 'Unrelated upgrade fixture.lnk'
foreach ($path in @($key, $productKey, $oldDir, $newDir, $oldGroup, $newGroup, $oldDesktop, $unrelatedDesktop)) {
  if (Test-Path -LiteralPath $path) { throw 'Upgrade simulation refuses pre-existing product or fixture state.' }
}
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$payload = New-Item -ItemType Directory -Path (Join-Path $EvidenceDir 'payload')
$compiled = New-Item -ItemType Directory -Path (Join-Path $EvidenceDir 'compiled')
# A trusted benign native binary is copied only as a payload; no fixture app is launched.
$benign = Join-Path $env:WINDIR 'System32\whoami.exe'
Copy-Item -LiteralPath $benign -Destination (Join-Path $payload.FullName 'budlark.exe')
$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
if ($arch -notin @('arm64','x64')) { throw 'Only supported native Windows architectures may run this proof.' }
& $Iscc "/DAppArch=$arch" "/DSourceDir=$($payload.FullName)" "/O$($compiled.FullName)" `
  (Join-Path $repo 'packaging\upgrade-fixture.iss')
if ($LASTEXITCODE -ne 0) { throw 'Prior fixture compilation failed.' }
& $Iscc "/DAppArch=$arch" '/DUpgradeRenamedExecutableFixture' "/DSourceDir=$($payload.FullName)" `
  "/O$($compiled.FullName)" (Join-Path $repo 'packaging\upgrade-fixture.iss')
if ($LASTEXITCODE -ne 0) { throw 'Renamed executable in prior location fixture compilation failed.' }
& $Iscc "/DAppArch=$arch" '/DAppVersion=0.0.0-upgrade-proof' '/DOnboardingJourneyFixture' `
  "/DSourceDir=$($payload.FullName)" "/O$($compiled.FullName)" (Join-Path $repo 'packaging\budlark.iss')
if ($LASTEXITCODE -ne 0) { throw 'Actual migration fixture compilation failed.' }
$prior = Join-Path $compiled.FullName 'prior-product-upgrade-fixture.exe'
$renamedPrior = Join-Path $compiled.FullName 'renamed-product-upgrade-fixture.exe'
$candidate = Join-Path $compiled.FullName "Budlark-0.0.0-upgrade-proof-windows-$arch-setup.exe"
$report = [ordered]@{
  kind = 'synthetic-prior-identity-upgrade-not-real-owner-data-or-app-acceptance'
  sourceCommit = (git rev-parse HEAD)
  migrationSha256 = (Get-FileHash (Join-Path $repo 'packaging\upgrade-migration.iss')).Hash.ToLower()
  setupSha256 = (Get-FileHash (Join-Path $repo 'packaging\budlark.iss')).Hash.ToLower()
  priorFixtureSha256 = (Get-FileHash $prior).Hash.ToLower()
  renamedPriorFixtureSha256 = (Get-FileHash $renamedPrior).Hash.ToLower()
  installerSha256 = (Get-FileHash $candidate).Hash.ToLower()
  outcome = 'UNVERIFIED'; cleanupVerified = $false
}
. "$PSScriptRoot\universal_integrity_contract.ps1"
$priorProtectionDir = New-Item -ItemType Directory -Path (Join-Path $EvidenceDir 'prior-protection')
$priorProtection = Start-ProtectedInstallerProof $prior (Get-FileHash $prior).Hash.ToLower() $priorProtectionDir.FullName
$renamedProtectionDir = New-Item -ItemType Directory -Path (Join-Path $EvidenceDir 'renamed-prior-protection')
$renamedProtection = Start-ProtectedInstallerProof $renamedPrior $report.renamedPriorFixtureSha256 $renamedProtectionDir.FullName
$protection = Start-ProtectedInstallerProof $candidate $report.installerSha256 $EvidenceDir
. "$PSScriptRoot\installer_owned_capture.ps1" -Installer $candidate -EvidenceDir $EvidenceDir
$shell = New-Object -ComObject WScript.Shell
$oldUninstaller = Join-Path $oldDir 'unins000.exe'
$newUninstaller = Join-Path $newDir 'unins000.exe'
$oldExe = Join-Path $oldDir "$oldName.exe"
$dataHashes = @{}
function Invoke-UpgradeFixture([string]$File, [string]$Stage, [string]$Extra = '', [bool]$ExpectFailure = $false) {
  $log = Join-Path $EvidenceDir "$Stage.log"
  $process = Start-CaptureProcess $File "/VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART /LOG=`"$log`" $Extra" $Stage
  Wait-CaptureTree $Stage 120
  if (($process.ExitCode -eq 0) -eq $ExpectFailure) {
    throw "Unexpected fixture process exit at $Stage."
  }
  Assert-InstallerProtectionUnchanged $priorProtection
  Assert-InstallerProtectionUnchanged $renamedProtection
  Assert-InstallerProtectionUnchanged $protection
}
function Assert-SyntheticDataPreserved {
  foreach ($path in $dataHashes.Keys) {
    if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $dataHashes[$path]) {
      throw 'Synthetic owner data or unrelated file changed.'
    }
  }
}
function Assert-NewShortcuts {
  foreach ($entry in @(@('Budlark.lnk', (Join-Path $newDir 'budlark.exe')),
      @('Uninstall Budlark.lnk', $newUninstaller))) {
    $path = Join-Path $newGroup $entry[0]
    if (-not (Test-Path -LiteralPath $path) -or $shell.CreateShortcut($path).TargetPath -ine $entry[1]) {
      throw 'New shortcut is absent or targets the wrong location.'
    }
  }
}
try {
  Invoke-UpgradeFixture $prior 'prior-install'
  $ownerData = Join-Path $oldDir 'owner-record.json'
  $unknownFile = Join-Path $oldDir 'unknown-user-file.txt'
  $externalData = Join-Path $EvidenceDir 'synthetic-owner-data.json'
  foreach ($path in @($ownerData, $unknownFile, $externalData)) {
    'Synthetic owner fixture; no account, credential, or real garden data.' | Set-Content -LiteralPath $path
    $dataHashes[$path] = (Get-FileHash -LiteralPath $path).Hash
  }
  $link = $shell.CreateShortcut($unrelatedDesktop)
  $link.TargetPath = $benign
  $link.Save()
  $dataHashes[$unrelatedDesktop] = (Get-FileHash -LiteralPath $unrelatedDesktop).Hash
  Invoke-UpgradeFixture $candidate 'forced-before-install-failure' '/FORCEFIXTUREFAILURE' $true
  if (-not (Test-Path -LiteralPath $oldExe) -or -not (Test-Path -LiteralPath $oldDesktop) -or
      -not (Test-Path -LiteralPath (Join-Path $oldGroup 'Uninstall prior product upgrade fixture.lnk'))) {
    throw 'Failed setup mutated the prior installation.'
  }
  Assert-SyntheticDataPreserved
  # Reproduce a renamed release that already reused the original directory/group.
  Invoke-UpgradeFixture $renamedPrior 'renamed-executable-in-prior-location'
  if (-not (Test-Path -LiteralPath $oldExe) -or
      -not (Test-Path -LiteralPath (Join-Path $oldDir 'budlark.exe'))) {
    throw 'Intermediate renamed-in-prior-location fixture did not retain both executables.'
  }
  Invoke-UpgradeFixture $candidate 'renamed-upgrade'
  if ((Test-Path -LiteralPath $oldExe) -or (Test-Path -LiteralPath $oldDesktop) -or
      (Test-Path -LiteralPath (Join-Path $oldDir 'budlark.exe')) -or
      (Test-Path -LiteralPath $oldGroup) -or -not (Test-Path -LiteralPath (Join-Path $newDir 'budlark.exe'))) {
    throw 'Prior executable, shortcuts, or empty group were not retired at the new default location.'
  }
  $registration = Get-ItemProperty -LiteralPath $key
  if ($registration.InstallLocation.TrimEnd('\') -ine $newDir -or
      $registration.'Inno Setup: Icon Group' -ine 'Budlark') {
    throw 'New uninstall registration retained the prior directory or group.'
  }
  Assert-NewShortcuts
  Assert-SyntheticDataPreserved
  $report.defaultDirectoryAndGroupMigrated = $true
  $report.renamedExecutableInPriorLocationAlsoRetired = $true
  $report.failedSetupPreservedPriorInstallation = $true
  Invoke-UpgradeFixture $candidate 'same-product-reinstall'
  Assert-NewShortcuts
  Assert-SyntheticDataPreserved
  $report.sameProductReinstallPreservedNewLinks = $true
  # Repeat with a user-created link in the prior group: keep it and the nonempty group.
  Invoke-UpgradeFixture $prior 'prior-reinstall'
  $unrelatedGroupLink = Join-Path $oldGroup 'User-created link.lnk'
  $link = $shell.CreateShortcut($unrelatedGroupLink)
  $link.TargetPath = $benign
  $link.Save()
  $dataHashes[$unrelatedGroupLink] = (Get-FileHash -LiteralPath $unrelatedGroupLink).Hash
  Invoke-UpgradeFixture $candidate 'upgrade-preserving-unrelated-links'
  if ((Test-Path -LiteralPath $oldExe) -or (Test-Path -LiteralPath $oldDesktop) -or
      (Test-Path -LiteralPath (Join-Path $oldGroup "$oldName.lnk")) -or
      (Test-Path -LiteralPath (Join-Path $oldGroup 'Uninstall prior product upgrade fixture.lnk'))) {
    throw 'Identity-matched prior product links were retained.'
  }
  Assert-NewShortcuts
  Assert-SyntheticDataPreserved
  Invoke-UpgradeFixture $newUninstaller 'new-uninstall'
  Assert-SyntheticDataPreserved
  if ((Test-Path -LiteralPath (Join-Path $newDir 'budlark.exe')) -or (Test-Path -LiteralPath $key)) {
    throw 'New fixture uninstall failed.'
  }
  $report.unrelatedLinksAndSyntheticDataPreservedThroughUninstall = $true
  $report.outcome = 'PASS synthetic compiled installer upgrade only; real prior release and app data compatibility unverified'
} catch {
  $report.outcome = 'FAIL synthetic upgrade incomplete'
  $report.failureType = $_.Exception.GetType().FullName
  $report.failureLine = $_.InvocationInfo.ScriptLineNumber
  throw
} finally {
  try {
    Stop-CaptureTree
    if (Test-Path -LiteralPath $newUninstaller) { Invoke-UpgradeFixture $newUninstaller 'cleanup-new-uninstall' }
    if (Test-Path -LiteralPath $oldUninstaller) { Invoke-UpgradeFixture $oldUninstaller 'cleanup-prior-uninstall' }
    # All paths were absent at preflight and are exclusively synthetic fixture-owned.
    foreach ($path in @($oldDir, $newDir, $oldGroup, $newGroup, $oldDesktop, $unrelatedDesktop)) {
      if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
    if (Test-Path -LiteralPath $key) { throw 'Isolated fixture uninstall identity remains after cleanup.' }
    $report.cleanupVerified = $true
  } catch {
    $report.outcome = 'FAIL synthetic upgrade cleanup incomplete'
    throw
  } finally {
    Stop-CaptureTree
    try {
      Assert-InstallerProtectionUnchanged $priorProtection
      Assert-InstallerProtectionUnchanged $renamedProtection
      Assert-InstallerProtectionUnchanged $protection
    } catch {
      $report.outcome = 'FAIL protection changed during upgrade proof'
      throw
    } finally {
      $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $EvidenceDir 'upgrade-proof.json') -Encoding utf8
    }
  }
}
