import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
test('one native Ready Install commitment leads to progress and Finish', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /DisableWelcomePage=yes/);
  assert.match(setup, /DisableReadyPage=no/);
  assert.match(setup, /DisableFinishedPage=no/);
  assert.match(setup, /DisableDirPage=yes/);
  assert.match(setup, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(setup, /UsePreviousAppDir=yes/);
  assert.doesNotMatch(setup, /msgButtonInstall|NextButton\.Caption/);
  assert.match(read('tool/verify_onboarding_wizard.ps1'), /expectedOrder = @\('ready'\)/);
  assert.doesNotMatch(setup, /CreateCustomPage\(|MeasurementCheckBox|MeasurementEvent|WriteMeasurement|SaveStringToFile/);
  assert.match(setup, /^\[Run\]/m);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.match(setup, /runasoriginaluser/);
});
test('static welcome artwork does not own timers or advance native pages', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /#include "install-progress\.iss"/);
  const progress = read('packaging/install-progress.iss');
  assert.doesNotMatch(progress, /SetTimer|KillTimer|CreateCallback|PeekMessage|DispatchMessage|OnClick|Sleep\(/);
  assert.match(progress, /WizardSilent/);
  assert.doesNotMatch(setup + progress, /WebView|DownloadTemporaryFile|SPI_SET|education-/);
  for (const name of ['welcome-steps.bmp', 'welcome-garden.bmp']) assert.ok(progress.includes(name));
});
test('installer never creates or adopts receipt consent; legacy owner-matched uninstall and app compatibility remain', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.doesNotMatch(setup, /SaveStringToFile|CoCreateGuid|GetSystemTime|install_completed|MeasurementStarted/);
  assert.match(setup, /\[InstallDelete\][\s\S]*measurement-owner\.txt/);
  assert.match(setup, /CurUninstallStepChanged[\s\S]*Length\(Owner\) = 36/);
  assert.match(setup, /Pos\('"events":\[\{"id":"' \+ Owner/);
  assert.match(setup, /DeleteFile\(Filename\)/);
  assert.match(setup, /installer-receipt\.json/);
});
test('actual proof captures standard native pages; static art is never motion evidence', () => {
  const proof = read('tool/verify_install_progress.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /installerSha256/);
  assert.match(proof, /GetDpiForWindow/);
  assert.match(proof, /elapsedMilliseconds/);
  assert.match(proof, /actual-\$stage/);
  assert.match(proof, /expectedArtworkSha256/);
  assert.match(proof, /Invoke-StandardWizardStep/);
  assert.match(proof, /Assert-StandardWizardJourney/);
  assert.match(proof, /Not motion evidence/);
});
test('owned capture success/timeout/cleanup write exact stage and process exit state without an installer',
  { skip: process.platform !== 'win32' }, () => {
    const directory = mkdtempSync(fileURLToPath(new URL('../.bloomstep-benign-capture-wait-', import.meta.url)));
    const library = fileURLToPath(new URL('../tool/installer_owned_capture.ps1', import.meta.url));
    const quote = value => `'${value.replaceAll("'", "''")}'`;
    const script = `
      $ErrorActionPreference = 'Stop'
      $EvidenceDir = ${quote(directory)}
      $shell = (Get-Process -Id $PID).Path
      . ${quote(library)} -Installer $shell -EvidenceDir $EvidenceDir
      $fast = Start-CaptureProcess $shell '-NoProfile -Command "exit 0"' 'benign-success'
      Wait-CaptureTree 'benign-success' 15
      if ($fast.ExitCode -ne 0) { throw 'Benign success did not exit0.' }
      $sleep = Start-CaptureProcess $shell '-NoProfile -Command "Start-Sleep -Seconds 20"' 'benign-timeout'
      $rejected = $false
      try { Wait-CaptureTree 'benign-timeout' 1 }
      catch { $rejected = $_.Exception.Message.Contains('exceeded') }
      finally { Stop-CaptureTree }
      if (-not $rejected) { throw 'Timeout did not fail.' }
      $receipt = Get-Content (Join-Path $EvidenceDir 'owned-stage-receipt.json') -Raw | ConvertFrom-Json
      if ($receipt.stage -ne 'finally-owned-exit-state' -or
          @($receipt.stages.stage) -notcontains 'benign-timeout-timeout' -or
          @($receipt.processes | Where-Object { -not $_.exited }).Count -ne 0) {
        throw 'Timeout/cleanup did not persist owned stage/exit state.'
      }
      if (@($receipt.processes | Where-Object { $_.pid -eq $sleep.Id }).Count -ne 1) {
        throw 'Timed-out exact owned PID missing.'
      }
    `;
    try {
      const result = spawnSync('pwsh', ['-NoProfile', '-Command', script],
        { encoding: 'utf8', timeout: 45000, windowsHide: true });
      assert.equal(result.status, 0, result.stderr || result.stdout || String(result.error));
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

test('exact captured VCL application proxies are not dialogs; genuine unknown dialogs still fail closed',
  { skip: process.platform !== 'win32' }, () => {
    const contract = fileURLToPath(new URL('../tool/installer_window_contract.ps1', import.meta.url));
    const quote = value => `'${value.replaceAll("'", "''")}'`;
    const script = `
      $ErrorActionPreference = 'Stop'
      . ${quote(contract)}
      # Exact source37621602047 sanitized precommit observations on both hosts.
      foreach ($owner in @(6504, 5156)) {
        if (-not (Test-InnoApplicationProxy 'TApplication' '' $false $owner @($owner))) {
          throw 'Actual empty VCL proxy was misclassified as a dialog.'
        }
      }
      foreach ($class in @('#32770', 'TSetupMessageForm', 'UnknownDialog')) {
        if (Test-InnoApplicationProxy $class '' $false 6504 @(6504)) {
          throw 'Unknown/real dialog was ignored.'
        }
      }
      if ((Test-InnoApplicationProxy 'TApplication' 'A policy block' $false 6504 @(6504)) -or
          (Test-InnoApplicationProxy 'TApplication' '' $true 6504 @(6504)) -or
          (Test-InnoApplicationProxy 'TApplication' '' $false 9999 @(6504)) -or
          (Test-InnoApplicationProxy 'TApplication' $null $false 6504 @(6504)) -or
          (Test-InnoApplicationProxy 'TApplication' '' $null 6504 @(6504)) -or
          (Test-InnoApplicationProxy 'TApplication' '' $false 6504 @())) {
        throw 'Unknown/interactive/unowned window was classified as a trusted proxy.'
      }
    `;
    const result = spawnSync('pwsh', ['-NoProfile', '-Command', script],
      { encoding: 'utf8', timeout: 15000, windowsHide: true });
    assert.equal(result.status, 0, result.stderr || result.stdout || String(result.error));
    const proof = read('tool/verify_install_progress.ps1');
    assert.match(proof, /trustedApplicationProxies/);
    assert.match(proof, /unexpected owned dialog/);
    assert.match(read('tool/installer_owned_capture.ps1'), /GetWindowTitle/);
  });
