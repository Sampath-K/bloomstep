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
