function Get-EmbeddedChecksumErrors([string[]]$Lines) {
  $expected = '^\s*(?:\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{3})?\s+)?(?:Error:\s*)?(?:The source file is corrupted\.?|Verification of the source file failed: The hash of the file is incorrect\.?)\s*$'
  @($Lines | Where-Object { $_ -match $expected } | ForEach-Object {
    if ($_ -match 'Verification of the source file failed:') {
      'Verification of the source file failed: The hash of the file is incorrect'
    } else { 'The source file is corrupted' }
  } | Select-Object -Unique)
}

function Assert-WelcomeCancelExit([int]$ExitCode) {
  if ($ExitCode -ne 2) { throw "Owned Welcome wizard did not return Inno's pre-install Cancel exit code 2: $ExitCode" }
}

function Test-BloomstepInnoProductName([string]$ProductName,
    [ValidateSet('Bloomstep','Bloomstep isolated journey proof')][string]$ExpectedName = 'Bloomstep') {
  if ($null -eq $ProductName) { return $false }
  return ($ProductName.TrimEnd([char]32) -ceq $ExpectedName)
}

function Assert-GenuineLaunchOutcome([string]$Mode, [int]$WizardExitCode, [int]$LauncherExitCode,
    [int]$LaunchCount, [bool]$SameAppAlive, [bool]$VisibleOwnedWindow) {
  if ($Mode -notin @('automatic-launch','silent-no-launch') -or $WizardExitCode -ne 0 -or $LauncherExitCode -ne 0) {
    throw 'Genuine automatic/silent proof requires successful actual wizard and launcher exit0.'
  }
  if ($Mode -eq 'automatic-launch') {
    if ($LaunchCount -ne 1 -or -not $SameAppAlive -or -not $VisibleOwnedWindow) {
      throw 'Genuine automatically launched app must survive the observation window with one exact-target process and visible owned window.'
    }
  } elseif ($LaunchCount -ne 0 -or $SameAppAlive -or $VisibleOwnedWindow) {
    throw 'Genuine silent install must produce no app process or window.'
  }
}
