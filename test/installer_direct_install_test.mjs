import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
test('destination is the sole preinstall decision and Install commits, with native Browse/error/cancel behavior', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /DisableWelcomePage=yes/);
  assert.match(setup, /DisableReadyPage=yes/);
  assert.match(setup, /DisableDirPage=no/);
  assert.match(setup, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(setup, /UsePreviousAppDir=yes/);
  assert.match(setup, /CurPageID = wpSelectDir[\s\S]*msgButtonInstall/);
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
  assert.match(progress, /SystemParametersInfoW@user32\.dll/);
  assert.match(progress, /\$1042/);
  assert.match(progress, /Elapsed div 3000/);
  assert.match(progress, /WizardSilent/);
  assert.match(progress, /ssPostInstall|StopInstallMotion/);
  assert.match(progress, /MotionAllowed := False/);
  assert.match(progress, /DeinitializeSetup/);
  assert.doesNotMatch(setup + progress, /Sleep\(|while.*Scene|WebView|DownloadTemporaryFile|SPI_SET/);
  for (const name of ['education-seed.bmp', 'education-recipe.bmp', 'education-growth.bmp']) {
    assert.ok(progress.includes(name));
  }
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
});
