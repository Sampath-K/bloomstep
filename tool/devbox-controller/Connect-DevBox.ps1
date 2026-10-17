param([switch]$Resume)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$packageRoot=$PSScriptRoot
$resumeRequested=[bool]$Resume
. "$packageRoot\Bootstrap.Common.ps1"
$package=Assert-PackageInventory $packageRoot
. "$packageRoot\harness\Run-InstallerTrial.ps1" -LoadHelpersOnly
$root=$packageRoot
$destination=Join-Path $env:LOCALAPPDATA 'BloomstepController'
$state=Join-Path $destination 'state'
$headers=$null
$secret=$null
$lock=$null
$receipt=[ordered]@{
  kind='private-devbox-controller-connection'; source=$package.source
  outcome='BLOCKED'; runnerRegistrationStarted=$false; connectionVerified=$false
  protectedGatesAccepted=$false; trustBoundary='all private controller writers/admins/authorized apps'
  nextAction='Read explicit guard failure; do not bypass policy or protection.'
}

function Invoke-ControllerApi([string]$Path,[string]$Method='GET',$Body=$null) {
  if ($Path -notmatch '^(/collaborators\?per_page=100|/actions/permissions(/selected-actions|/workflow)?|/actions/runners(/registration-token)?|/actions/variables(/DEVBOX_CONNECTION_AUDITED)?|/actions/workflows/validate\.yml|/actions/workflows/validate\.yml/dispatches|/commits/main|/contents/(\.github/workflows/validate\.yml|controller/Verify-Candidate\.ps1)\?ref=[a-f0-9]{40})?$') {
    throw 'Controller API path is not allowlisted.'
  }
  $arguments=@{Uri=("https://api.github.com/repos/Sampath-K/bloomstep-vm-controller"+$Path); Headers=$headers; Method=$Method; TimeoutSec=60; MaximumRedirection=0; UseBasicParsing=$true}
  if ($null -ne $Body) { $arguments.Body=($Body|ConvertTo-Json -Depth 5); $arguments.ContentType='application/json' }
  try {
    $response=Invoke-WebRequest @arguments
    if ($response.Content) { return ($response.Content|ConvertFrom-Json) }
  } catch { throw "Private controller API $Method $Path failed. Verify local token permissions/private policy; never paste credentials into chat." }
}

function Assert-RunnerArchiveFiles([string]$Archive,[string]$Directory) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try{
    foreach($entry in $zip.Entries){
      if($entry.FullName -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))'){throw 'Unsafe pinned runner archive path.'}
      if(-not $entry.Name){continue}
      $path=Join-Path $Directory $entry.FullName
      Assert-NoReparsePath $path
      if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Pinned runner file missing; no registration/listener start.'}
      $stream=$entry.Open();$hash=[Security.Cryptography.SHA256]::Create()
      try{$expected=[BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}
      finally{$stream.Dispose();$hash.Dispose()}
      if((Get-FileSha256 $path) -cne $expected){throw 'Pinned runner file modified. No silent replacement or listener start.'}
    }
  }finally{$zip.Dispose()}
}

try {
  if ($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8) { throw 'Use built-in 64-bit Windows PowerShell on the dedicated Dev Box.' }
  Assert-InteractiveStandardUser
  Assert-NoPreviousBootstrapRunning
  $null=Get-DefenderSnapshot
  Assert-NoReparsePath $destination
  Assert-NoReparsePath $state
  New-Item -ItemType Directory -Path $state -Force | Out-Null
  $lock=[IO.File]::Open((Join-Path $state 'connection.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  Write-Host 'This authorizes persistent execution as this standard user from the PRIVATE controller only.'
  Write-Host 'ALL controller writers/admins/apps can execute as you; a single workflow, labels or ephemeral mode cannot isolate them.'
  Write-Host 'Only trusted owner/apps may have write access. Corporate IT approval must permit this. No service, autologon, lock bypass or inbound access.'
  Write-Host 'Stop the listener to stop accepting work; remove its registration in the private repository Settings to revoke credentials.'
  Write-Host "Budlock supplemental trials retain the legacy Bloomstep candidate: approved runs may install into $env:LOCALAPPDATA\Programs\Bloomstep and remove ONLY their verified owned program, shortcuts, protocol/startup registration using its native uninstaller."
  Write-Host 'Existing user data is preserved; preexisting/unowned product state blocks execution. Uninstall is NOT VM rollback. No force kills or broad cleanup.'
  if (-not (Confirm-Operator 'Confirm dedicated VM/IT authorization and completed owner audit of ALL controller writers and installed/authorized apps, plus standing reviewed installer execution and owned uninstall.' 'PERSISTENT PRIVATE CONTROLLER')) {
    throw 'Required one-time persistent-access/trust audit confirmation declined.'
  }
  Write-Host 'Authenticate LOCALLY with a fine-grained short-lived token limited to this private controller: Administration read/write (runner registration/audit), Actions read/write (dispatch), Contents read, Variables read/write (activation). Never paste a token into chat.'
  $secret=Read-Host 'Private controller setup token (masked; memory only, not saved)' -AsSecureString
  $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
  try {
    $headers=@{Authorization=('Bearer '+[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer));Accept='application/vnd.github+json';'User-Agent'='bloomstep-owner-setup'}
  } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  $repo=Invoke-ControllerApi ''
  if (-not $repo.private -or $repo.full_name -cne 'Sampath-K/bloomstep-vm-controller' -or $repo.owner.login -cne 'Sampath-K') { throw 'Private repo identity verification failed.' }
  $collaborators=@(Invoke-ControllerApi '/collaborators?per_page=100')
  if ($collaborators.Count -ne 1 -or $collaborators[0].login -cne 'Sampath-K' -or -not $collaborators[0].permissions.admin) {
    throw 'Effective human collaborator set is not owner-only; stop for owner review.'
  }
  $permissions=Invoke-ControllerApi '/actions/permissions'
  $workflowPermissions=Invoke-ControllerApi '/actions/permissions/workflow'
  if (-not $permissions.enabled -or $permissions.allowed_actions -cne 'selected' -or
      $workflowPermissions.default_workflow_permissions -cne 'read' -or $workflowPermissions.can_approve_pull_request_reviews) {
    throw 'Owner must configure selected pinned Actions, read-only workflow token, and no PR approval permission before setup. No setting is changed by this script.'
  }
  $actions=Invoke-ControllerApi '/actions/permissions/selected-actions'
  $expectedActions=@(
    'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683',
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02',
    'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
  )
  if ($actions.github_owned_allowed -or $actions.verified_allowed -or
      (@($actions.patterns_allowed|Sort-Object) -join '|') -cne (($expectedActions|Sort-Object) -join '|')) {
    throw 'Controller Actions allowlist differs from the exact reviewed action commits. Owner setup required; no automatic policy change.'
  }
  $workflow=Invoke-ControllerApi '/actions/workflows/validate.yml'
  if ($workflow.path -cne '.github/workflows/validate.yml' -or $workflow.state -cne 'active') { throw 'Reviewed controller workflow is not active.' }
  $main=Invoke-ControllerApi '/commits/main'
  if($main.sha -notmatch '^[a-f0-9]{40}$'){throw 'Controller main commit identity missing.'}
  foreach($binding in @(
    @{remote='.github/workflows/validate.yml';local='validate.yml'},
    @{remote='controller/Verify-Candidate.ps1';local='Verify-Candidate.ps1'}
  )){
    $response=Invoke-ControllerApi ("/contents/"+$binding.remote+"?ref="+$main.sha)
    $bytes=[Convert]::FromBase64String($response.content)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$actual=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
    finally{$hash.Dispose()}
    if($actual -cne (Get-FileSha256 (Join-Path $packageRoot $binding.local))){throw 'Published workflow/verifier differs from this reviewed connection bundle. Owner publication required; no registration.'}
  }
  $receipt.reviewedControllerSource=$main.sha
  $native=if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE}
  $arch=switch($native){'AMD64'{'x64'}'ARM64'{'arm64'}default{throw 'Only native x64/ARM64 supported.'}}
  $receipt.architecture=$arch
  $dependencies=Get-Content -LiteralPath "$packageRoot\connection-dependencies.json" -Raw|ConvertFrom-Json
  foreach($name in @('pwsh','runner')) {
    $asset=$dependencies.assets.("$name-$arch")
    $archive=Get-PinnedDownload $asset (Join-Path $destination 'downloads')
    $tools=Join-Path $destination "$name-$arch"
    if ($name -eq 'runner' -and (Test-Path -LiteralPath (Join-Path $tools '.runner'))) {
      # Runner has mutable credential/config files: verify executable against its pinned archive, never overwrite it.
      if ((Get-FileSha256 $archive) -cne $asset.sha256) {throw 'Runner archive authority changed.'}
      Assert-RunnerArchiveFiles $archive $tools
    } else {
      if(Test-Path -LiteralPath $tools){
        $null=Assert-VerifiedPortableCache $archive $tools $asset.sha256
      }else{
        Expand-VerifiedPortable $archive $tools
        $null=Assert-VerifiedPortableCache $archive $tools $asset.sha256
      }
    }
  }
  foreach($file in $package.files) {
    $from=Join-Path $packageRoot $file.path
    $to=Join-Path $destination $file.path
    Assert-NoReparsePath $to
    New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force|Out-Null
    if (Test-Path -LiteralPath $to) {
      if ((Get-FileSha256 $to) -cne $file.sha256) {throw 'Installed controller source differs; no silent update of persistent code.'}
    } else {Copy-Item -LiteralPath $from -Destination $to}
  }
  Assert-NoReparsePath (Join-Path $destination 'package-manifest.json')
  Copy-Item -LiteralPath (Join-Path $packageRoot 'package-manifest.json') -Destination (Join-Path $destination 'package-manifest.json') -Force
  $runnerDirectory=Join-Path $destination "runner-$arch"
  if(Test-Path -LiteralPath (Join-Path $runnerDirectory '.service')){throw 'A service registration is present. Interactive standard-user mode only; no automatic service changes.'}
  $runners=Invoke-ControllerApi '/actions/runners'
  $configPath=Join-Path $runnerDirectory '.runner'
  if (Test-Path -LiteralPath $configPath) {
    if (-not $resumeRequested) {throw 'Existing runner requires the same Connect-DevBox.ps1 -Resume; no replacement registration.'}
    $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
    $serverMatches=@($runners.runners|Where-Object {$_.id -eq $config.agentId -and $_.name -ceq $config.agentName})
    if ($runners.total_count -ne 1 -or $serverMatches.Count -ne 1 -or
        $config.gitHubUrl -cne 'https://github.com/Sampath-K/bloomstep-vm-controller' -or
        $serverMatches[0].status -cne 'offline' -or $serverMatches[0].busy) {
      throw 'Existing registration/repository differs or another listener is active. Never start a concurrent listener.'
    }
  } else {
    if ($runners.total_count -ne 0) {throw 'Unexpected controller runner already registered; do not replace/adopt.'}
    $registration=Invoke-ControllerApi '/actions/runners/registration-token' 'POST'
    $env:ACTIONS_RUNNER_INPUT_TOKEN=$registration.token
    $receipt.runnerRegistrationStarted=$true
    $runnerName="bloomstep-private-$arch"
    Push-Location $runnerDirectory
    try {
      & .\config.cmd --unattended --url https://github.com/Sampath-K/bloomstep-vm-controller --name $runnerName --labels "bloomstep-private-controller,$arch" --work _work --disableupdate
      if($LASTEXITCODE -ne 0){throw 'Runner registration failed. No listener started.'}
    } finally {Pop-Location; $env:ACTIONS_RUNNER_INPUT_TOKEN=$null; $registration=$null}
  }
  $variables=Invoke-ControllerApi '/actions/variables'
  if ($variables.total_count -gt 100) {throw 'Variable inventory exceeds bounded setup audit.'}
  $activation=@($variables.variables|Where-Object name -CEQ 'DEVBOX_CONNECTION_AUDITED')
  if($activation.Count -eq 0){$null=Invoke-ControllerApi '/actions/variables' 'POST' @{name='DEVBOX_CONNECTION_AUDITED';value='true'}}
  elseif($activation.Count -eq 1){$null=Invoke-ControllerApi '/actions/variables/DEVBOX_CONNECTION_AUDITED' 'PATCH' @{name='DEVBOX_CONNECTION_AUDITED';value='true'}}
  else{throw 'Ambiguous activation state.'}
  $null=Invoke-ControllerApi '/actions/workflows/validate.yml/dispatches' 'POST' @{ref='main';inputs=@{candidate='bd5ad93-owner-trial';architecture=$arch}}
  $headers.Clear();$secret.Dispose();$secret=$null
  $receipt.outcome='LISTENER_STARTING_NOT_CONNECTION_PROOF'
  $receipt.nextAction='Leave this standard-user interactive listener open. Cloud must read a successful real test result before claiming connectivity. Lock/logoff/reboot can stop UI testing. No autostart configured.'
  Save-DevBoxTrialReceipt (Join-Path $state 'connection-receipt.json') $receipt
  $env:PATH=(Join-Path $destination "pwsh-$arch")+[IO.Path]::PathSeparator+$env:PATH
  Push-Location $runnerDirectory
  try {& .\run.cmd; if($LASTEXITCODE -ne 0){throw 'Listener stopped with an error. Use the same entry point -Resume after inspection.'}}
  finally {Pop-Location}
} catch {
  Write-Error $_
  exit 1
} finally {
  if($null -ne $headers){$headers.Clear()}
  if($null -ne $secret){$secret.Dispose()}
  $env:ACTIONS_RUNNER_INPUT_TOKEN=$null
  if(Test-Path -LiteralPath $state){Save-DevBoxTrialReceipt (Join-Path $state 'connection-receipt.json') $receipt}
  if($null -ne $lock){$lock.Dispose()}
}
