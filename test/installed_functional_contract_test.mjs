import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../tool/verify_installed_functional.ps1', import.meta.url), 'utf8');
const contract = JSON.parse(readFileSync(new URL('../release/functional-requirements.json', import.meta.url), 'utf8'));

test('current acceptance workflow calls the exact scoped identity interface without a pre-install', () => {
  const workflow = readFileSync(new URL('../.github/workflows/functional-acceptance.yml', import.meta.url), 'utf8');
  assert.match(workflow, /\$harness = 'tool\/verify_installed_functional.ps1'/);
  for (const argument of ['-Installer $env:INSTALLER', '-ExpectedSha256 $env:IN_SHA256',
    '-InstallDir $env:INSTALL_DIR', '-Mode $env:IN_MODE',
    '-Requirements release/functional-requirements.json',
    "-Identity (Join-Path $env:OUT 'identity.json')", '-Output $env:OUT']) {
    assert.ok(workflow.includes(argument), `Workflow interface missing ${argument}`);
  }
  assert.doesNotMatch(workflow, /Start-Process\s+\$env:INSTALLER|Select-Object -First 1/);
  assert.match(source, /ValidateSet\('candidate','baseline'\)/);
  assert.match(source, /identityRecord\.installerSha256 -cne \$ExpectedSha256/);
  assert.match(source, /identityRecord\.run -cne \$result.run/);
  assert.match(source, /CandidateCommit -cne \$contract.baselineCommit/);
  assert.match(source, /Only repository functional requirements permitted/);
  assert.match(source, /Identity must be output\/identity.json/);
});

test('installed harness binds exact bytes before executing on a fresh native Windows runner', () => {
  for (const input of ['Installer', 'ExpectedSha256', 'InstallDir', 'Requirements', 'Identity', 'Output']) {
    assert.ok(source.includes(`[Parameter(Mandatory=$true)][string]$${input}`));
  }
  assert.match(source, /RUNNER_ENVIRONMENT -ne 'github-hosted'/);
  assert.match(source, /actions\/runs\/\$\(\$env:GITHUB_RUN_ID\)/);
  assert.match(source, /artifact=@\{runId=\$RunId; artifactId=\$ArtifactId\}/);
  assert.match(source, /OSArchitecture\.ToString\(\) -ne 'X64'/);
  assert.match(source, /ToUInt16\(\$bytes,\$pe\+4\) -ne 0x8664/);
  assert.ok(source.indexOf('Installer SHA-256 mismatch') < source.indexOf('Start-Process -FilePath $InstallerPath'));
  assert.match(source, /Get-AuthenticodeSignature/);
  assert.match(source, /signature\.Status\.ToString\(\) -notin @\('Valid','NotSigned'\)/);
  assert.match(source, /\$result\['authenticode'\] = \$signature.Status.ToString\(\)/);
  assert.doesNotMatch(source, /signature\.Status -ne 'Valid'/);
  assert.match(source, /Installer changed since verification/);
  assert.doesNotMatch(source, /flutter build|tool\\preview|build\\windows|Invoke-WebRequest|curl |https?:\/\/(?!github\.com)/);
});

test('paths and preexisting state are fail closed, install has no arbitrary executable parameter', () => {
  assert.match(source, /StartsWith\(\$runnerTemp \+ '\\'/);
  assert.match(source, /Assert-NoReparse \$OutputDirectory/);
  assert.match(source, /Existing output evidence refused/);
  assert.match(source, /Existing app process/);
  assert.match(source, /Existing user app state\/install registration/);
  assert.match(source, /Existing installDir refused/);
  assert.match(source, /InstallDir must be separately scoped under RUNNER_TEMP and match identity/);
  for (const flag of ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/DIR=']) {
    assert.ok(source.includes(flag));
  }
  assert.match(source, /Join-Path \$script:appDir 'bloomstep.exe'/);
  assert.match(source, /Start-Process -FilePath \$script:exe -WorkingDirectory \$script:appDir/);
  assert.doesNotMatch(source, /\[string\]\$(Executable|AppPath)|Remove-Item|Set-MpPreference|Add-MpPreference|Unblock-File|-Verb RunAs/);
});

test('interactive UIA and real clipboard chord require owned process, foreground and exact field focus', () => {
  for (const check of ['OpenInputDesktop', 'GetUserObjectInformation', 'UserInteractive',
    "ApartmentState -ne 'STA'", 'GetWindowThreadProcessId', 'GetGUIThreadInfo',
    'GetForegroundWindow', 'Current.ProcessId -eq $script:app.Id',
    'Automation]::Compare($focus,$field)', 'OpenClipboard', 'SetClipboardData(13',
    'GetClipboardData(13)', 'SendInput(4', 'value.Current.Value -cne $text']) {
    assert.ok(source.includes(check), `Missing ${check}`);
  }
  assert.match(source, /Ambiguous owned UIA control/);
  assert.match(source, /Held modifier; no input/);
  assert.match(source, /no setter\/message fallback/);
  const paste = source.split("Probe 'FR-PASTE'")[1].split("Probe 'FR-PLANT'")[0];
  assert.ok(paste.indexOf('Automation]::Compare') < paste.indexOf(']::Paste('));
  assert.doesNotMatch(paste, /SetValue|Send feedback'|Retry sending/);
  assert.doesNotMatch(source, /AttachThreadInput|AllowSetForegroundWindow|SwitchDesktop|SetThreadDesktop|keybd_event|mouse_event/);
});

test('Defender, explicit time bounds, owned cleanup and finally receipts cannot turn failures into acceptance', () => {
  assert.match(source, /Get-MpComputerStatus/);
  assert.match(source, /Get-MpThreatDetection/);
  assert.match(source, /Defender detection.*hard failure/);
  assert.match(source, /Defender final check/);
  for (const wait of ['WaitForExit(60000)', 'WaitForExit(30000)', 'AddSeconds(20)', 'AddSeconds(8)', 'AddSeconds(5)']) {
    assert.ok(source.includes(wait));
  }
  assert.match(source, /Overall observation budget/);
  assert.match(source, /Stop-Process -Id \$Process.Id/);
  assert.match(source, /Cleanup path ownership mismatch/);
  assert.match(source, /finally \{/);
  assert.match(source, /Join-Path \$OutputDirectory 'results.json'/);
  assert.match(source, /\[IO.File\]::WriteAllText/);
  assert.match(source, /\[Text.UTF8Encoding\]::new\(\$false\)/);
  assert.match(source, /Join-Path \$OutputDirectory \$log/);
  assert.match(source, /exit 1\s*$/);
});

test('receipt shape enumerates every requirement honestly without fake baseline or theme proof', () => {
  assert.match(source, /schema='budlark-functional-evidence-v1'/);
  assert.match(source, /\$contract.requirements \| ForEach-Object/);
  assert.match(source, /screenshots=@\{\}; baselineResult='UNVERIFIED'/);
  assert.match(source, /'FAIL' \} else \{ 'UNVERIFIED'/);
  assert.match(source, /customerAcceptance=\$false/);
  assert.ok(source.includes(contract.baselineCommit));
  assert.doesNotMatch(source, /baselineResult='FAIL'|result\.result = 'PASS'|screenshots\.light\s*=|screenshots\.dark\s*=/);
  assert.match(source, /PrintWindow\(window,dc,2\)/);
  assert.match(source, /Blank capture; screenshot UNVERIFIED/);
  assert.doesNotMatch(source, /CopyFromScreen/);
  for (const label of ['Plant a habit', 'pour my morning drink', 'Choose a tiny action',
    'Choose a celebration', 'Plant this seed', 'Your seed is planted', 'Did it',
    'Undo today', 'After I...', 'I will...', 'Then I celebrate by...',
    'Help us grow', 'Your feedback', 'Settings and privacy']) {
    assert.ok(source.includes(`'${label}'`), `Missing real app label ${label}`);
  }
});
