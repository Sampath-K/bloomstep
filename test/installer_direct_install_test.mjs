import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
test('welcome auto-advances to destination, the sole preinstall decision, and Install commits with native Browse/error/cancel', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /#if InstallFlow == "zeroclick"[\s\S]*DisableWelcomePage=yes[\s\S]*#else[\s\S]*DisableWelcomePage=no/);
  assert.match(setup, /DisableReadyPage=yes/);
  assert.match(setup, /DisableFinishedPage=yes/);
  assert.match(setup, /DisableDirPage=no/);
  assert.match(setup, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(setup, /UsePreviousAppDir=yes/);
  assert.match(setup, /CurPageID = wpSelectDir[\s\S]*msgButtonInstall/);
  assert.match(setup, /^SelectDirBrowseLabel=.*Install.*Browse/m);
  assert.match(read('tool/verify_onboarding_wizard.ps1'), /defaultDirectoryMatches = \$true/);
  assert.doesNotMatch(setup, /CreateCustomPage\(|MeasurementCheckBox|MeasurementEvent|WriteMeasurement|SaveStringToFile/);
  assert.doesNotMatch(setup, /FinishedHeadingLabel|postinstall|^\[Run\]/m);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.match(setup, /ExecAsOriginalUser/);
});
test('one visual uses supported native timer and read-only reduced-motion preference; zero-click waits only by pumping', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /#include "install-progress\.iss"/);
  const progress = read('packaging/install-progress.iss');
  assert.match(progress, /SetTimer@user32\.dll/);
  assert.match(progress, /KillTimer@user32\.dll/);
  assert.match(progress, /CreateCallback\(@VisualTimerTick\)/);
  // The current online help describes newer setup engines. CI uses Inno6.7.1.
  assert.match(progress, /Callback: LongWord\): UINT_PTR/);
  assert.doesNotMatch(progress, /NativeInt/);
  assert.match(progress, /SystemParametersInfoW@user32\.dll/);
  assert.match(progress, /\$1042/);
  assert.match(progress, /WizardSilent/);
  assert.match(progress, /StopInstallMotion/);
  assert.match(progress, /MotionAllowed := False/);
  assert.match(progress, /DeinitializeSetup/);
  const withoutHold = progress.replace(/procedure HoldZeroClickVisual[\s\S]*?\nend;/, '');
  assert.doesNotMatch(setup + withoutHold, /Sleep\(/);
  assert.doesNotMatch(setup + progress, /WebView|DownloadTemporaryFile|SPI_SET|education-/);
  for (const name of ['welcome-steps.bmp', 'welcome-garden.bmp']) assert.ok(progress.includes(name));
});test('installer never creates or adopts receipt consent; legacy owner-matched uninstall and app compatibility remain', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.doesNotMatch(setup, /SaveStringToFile|CoCreateGuid|GetSystemTime|install_completed|MeasurementStarted/);
  assert.match(setup, /\[InstallDelete\][\s\S]*measurement-owner\.txt/);
  assert.match(setup, /CurUninstallStepChanged[\s\S]*Length\(Owner\) = 36/);
  assert.match(setup, /Pos\('"events":\[\{"id":"' \+ Owner/);
  assert.match(setup, /DeleteFile\(Filename\)/);
  assert.match(setup, /installer-receipt\.json/);
});
test('actual proof measures welcome, Install, absent Finish and timer stop; static art is never motion evidence', () => {
  const proof = read('tool/verify_install_progress.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /installerSha256/);
  assert.match(proof, /GetDpiForWindow/);
  assert.match(proof, /elapsedMilliseconds/);
  assert.match(proof, /actual-welcome/);
  assert.match(proof, /actual-installing/);
  assert.match(proof, /expectedArtworkSha256/);
  assert.match(proof, /A Finish page must not exist/);
  assert.match(proof, /timerStopped = -not \$body\.Contains\('Bloomstep visual timer disposal failed'\)/);
  assert.match(proof, /Not motion evidence/);
  assert.match(read('packaging/install-progress.iss'), /visual identity=anchor-action-celebrate-garden/);
});
test('owned capture success/timeout/cleanup write exact stage and process exit state without an installer',
  { skip: process.platform !== 'win32' }, () => {
    const directory = mkdtempSync(join(tmpdir(), 'bloomstep-benign-capture-wait-'));
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
