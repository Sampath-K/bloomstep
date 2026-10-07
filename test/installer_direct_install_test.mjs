import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
test('destination is the sole preinstall decision and Install commits, with native Browse/error/cancel behavior', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /DisableWelcomePage=yes/);
  assert.match(setup, /DisableReadyPage=yes/);
  assert.match(setup, /DisableDirPage=no/);
  assert.match(setup, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(setup, /UsePreviousAppDir=yes/);
  assert.match(setup, /CurPageID = wpSelectDir[\s\S]*msgButtonInstall/);
  assert.match(setup, /^SelectDirBrowseLabel=.*Install.*Browse/m);
  assert.match(read('tool/verify_onboarding_wizard.ps1'), /defaultDirectoryMatches = \$true/);
  assert.doesNotMatch(setup, /CreateCustomPage\(|MeasurementCheckBox|MeasurementEvent|WriteMeasurement|SaveStringToFile/);
  assert.match(setup, /FinishedHeadingLabel=Bloomstep is ready/);
  assert.match(setup, /Open Bloomstep to create your first tiny habit/);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.match(setup, /postinstall skipifsilent runasoriginaluser/);
});
test('three existing scenes use supported native timer and read-only Windows reduced-motion preference without dwell', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /#include "install-progress\.iss"/);
  const progress = read('packaging/install-progress.iss');
  assert.match(progress, /SetTimer@user32\.dll/);
  assert.match(progress, /KillTimer@user32\.dll/);
  assert.match(progress, /CreateCallback\(@ProgressTimerTick\)/);
  // The current online help describes newer setup engines. CI uses Inno6.7.1.
  assert.match(progress, /Callback: LongWord\): UINT_PTR/);
  assert.doesNotMatch(progress, /NativeInt/);
  assert.match(progress, /SystemParametersInfoW@user32\.dll/);
  assert.match(progress, /\$1042/);
  assert.match(progress, /Elapsed div 600/);
  assert.match(progress, /if Scene > 2 then Scene := 2/);
  assert.match(progress, /WizardSilent/);
  assert.match(progress, /ssPostInstall|StopInstallMotion/);
  assert.match(progress, /MotionAllowed := False/);
  assert.match(progress, /DeinitializeSetup/);
  assert.doesNotMatch(setup + progress, /Sleep\(|while.*Scene|WebView|DownloadTemporaryFile|SPI_SET/);
  for (const name of ['education-seed.bmp', 'education-recipe.bmp', 'education-growth.bmp']) {
    assert.ok(progress.includes(name));
  }
});
test('short installs advance three panels without dwell or repeated flashing; fast completion remains immediate', () => {
  const progress = read('packaging/install-progress.iss');
  const interval = Number(progress.match(/Scene := Elapsed div (\d+);/)?.[1]);
  assert.equal(interval, 600);
  assert.match(progress, /if Scene > 2 then Scene := 2/);
  const sceneAt = elapsed => Math.min(Math.floor(elapsed / interval), 2);
  assert.deepEqual([0, 599, 600, 1199, 1200, 1500, 2100, 60000].map(sceneAt),
    [0, 0, 1, 1, 2, 2, 2, 2]);
  assert.doesNotMatch(progress, /Scene :=.*mod 3|Sleep\(|while.*Scene/);
  assert.match(progress, /not SystemParametersInfo[\s\S]*ShowProgressScene\(0\)/);
  assert.match(read('tool/installer_scene_contract.ps1'), /expectedIntervalMilliseconds = 600/);
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
test('actual proof measures transitions/finish/no dwell, never treats equivalent static source as motion evidence', () => {
  const proof = read('tool/verify_install_progress.ps1');
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /installerSha256/);
  assert.match(proof, /GetDpiForWindow/);
  assert.match(proof, /elapsedMilliseconds/);
  assert.match(proof, /actual-finish/);
  assert.match(proof, /actual-progress/);
  assert.match(proof, /sceneFrames/);
  assert.match(proof, /finishObserved/);
  assert.match(proof, /timerStopped/);
  assert.match(proof, /timerStopped = -not \$body\.Contains\('Bloomstep progress timer disposal failed'\)/);
});

test('real progress receipts identify distinct artwork/captions/times and explicitly absent transitions',
  { skip: process.platform !== 'win32' }, () => {
    const contract = fileURLToPath(new URL('../tool/installer_scene_contract.ps1', import.meta.url));
    const quote = value => `'${value.replaceAll("'", "''")}'`;
    const script = `
      $ErrorActionPreference = 'Stop'
      . ${quote(contract)}
      $catalog = @(Get-InstallSceneCatalog)
      if ($catalog.Count -ne 3 -or @($catalog.id | Sort-Object -Unique).Count -ne 3 -or
          @($catalog.artwork | Sort-Object -Unique).Count -ne 3 -or
          @($catalog.caption | Sort-Object -Unique).Count -ne 3) {
        throw 'Scenes must identify three distinct panels, not moving highlights.'
      }
      # Exact run37627423101 short-install observation; later scenes are absent.
      $short = Get-InstallSceneCoverage @(
        @{ scene = 0; elapsedMilliseconds = 257 },
        @{ scene = 0; elapsedMilliseconds = 1273 }
      )
      if ($short.allThreeScenesObserved -or $short.orderedTransitionsObserved -or
          @($short.absentSceneIds).Count -ne 2 -or $short.transitions.Count -ne 1) {
        throw 'Short actual installation must not be called complete scene evidence.'
      }
      $complete = Get-InstallSceneCoverage @(
        @{ scene = 0; elapsedMilliseconds = 200 },
        @{ scene = 1; elapsedMilliseconds = 3210 },
        @{ scene = 2; elapsedMilliseconds = 6280 }
      )
      if (-not $complete.allThreeScenesObserved -or -not $complete.orderedTransitionsObserved -or
          $complete.transitions[1].firstObservedMilliseconds -ne 3210) {
        throw 'Observed scene transitions must retain actual capture timestamps.'
      }
      $wrongOrder = Get-InstallSceneCoverage @(
        @{ scene = 0; elapsedMilliseconds = 200 },
        @{ scene = 2; elapsedMilliseconds = 6280 },
        @{ scene = 1; elapsedMilliseconds = 9300 }
      )
      if ($wrongOrder.orderedTransitionsObserved) { throw 'Wrong order accepted.' }
      foreach ($invalid in @(
        @{ scene = 3; elapsedMilliseconds = 10 },
        @{ scene = 0; elapsedMilliseconds = -1 },
        @{ scene = '0'; elapsedMilliseconds = 10 },
        @{ scene = 0 }
      )) {
        $rejected = $false
        try { Get-InstallSceneCoverage @($invalid) | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Malformed capture accepted.' }
      }
      $empty = Get-InstallSceneCoverage @()
      if ($empty.allThreeScenesObserved -or $empty.absentSceneIds.Count -ne 3) {
        throw 'Empty capture accepted.'
      }
    `;
    const result = spawnSync('pwsh', ['-NoProfile', '-Command', script],
      { encoding: 'utf8', timeout: 15000, windowsHide: true });
    assert.equal(result.status, 0, result.stderr || result.stdout || String(result.error));
    const proof = read('tool/verify_install_progress.ps1');
    assert.match(proof, /sceneId/);
    assert.match(proof, /expectedArtworkSha256/);
    assert.match(proof, /sceneCoverage = Get-InstallSceneCoverage/);
    assert.match(read('packaging/install-progress.iss'), /scene identity=[\s\S]*elapsedMilliseconds=/);
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
