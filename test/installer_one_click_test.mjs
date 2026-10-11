import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('Defender-blocked private candidate remains withdrawn, not a reputation warning', () => {
  const docs = read('docs/installer-onboarding.md');
  for (const phrase of ['WITHDRAWN: Defender-blocked private candidate', 'Behavior:Win32/DefenseEvasion.A!ml',
    'b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5',
    'Do not download, restore, distribute, or run', 'partial-install state is unknown',
    'not established as a false positive']) assert.ok(docs.includes(phrase), phrase);
});

test('obsolete autonomous variants are replaced by a standard native wizard', () => {
  const setup = read('packaging/bloomstep.iss');
  for (const page of ['Ready', 'Finished']) {
    assert.match(setup, new RegExp(`Disable${page}Page=no`));
  }
  for (const page of ['Welcome', 'Dir']) assert.match(setup, new RegExp(`Disable${page}Page=yes`));
  assert.match(setup, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.match(setup, /UsePreviousAppDir=yes/);
  assert.doesNotMatch(setup, /InstallFlow|ExecAsOriginalUser|BackButtonClick|NextButton\.OnClick|CreateCustomPage/);
  assert.doesNotMatch(read('packaging/install-progress.iss'),
    /SetTimer|KillTimer|CreateCallback|PeekMessage|DispatchMessage|OnClick|Sleep\(/);
});

test('launch is a default-checked toggleable native Finish choice with original-user guards', () => {
  const setup = read('packaging/bloomstep.iss');
  const run = setup.split('[Run]')[1]?.split(/\n\[/)[0];
  assert.ok(run);
  assert.match(run, /Filename: "\{app\}\\bloomstep.exe"/);
  assert.match(run, /Description: "Launch Bloomstep"/);
  for (const flag of ['postinstall', 'skipifsilent', 'runasoriginaluser']) {
    assert.match(run, new RegExp(`\\b${flag}\\b`));
  }
  assert.doesNotMatch(run, /\bunchecked\b/);
  assert.match(run, /Check: CanLaunchBloomstep/);
  const gate = /function CanLaunchBloomstep\(\): Boolean;([\s\S]*?)\nend;/.exec(setup)?.[1];
  assert.ok(gate);
  for (const guard of ['not WizardSilent', 'not IsAdmin', 'InteractiveDesktop', 'SUPPRESSMSGBOXES']) {
    assert.ok(gate.includes(guard), guard);
  }
  assert.doesNotMatch(setup, /PrivilegesRequiredOverridesAllowed|PrivilegesRequired=admin|ShellExec\(|DownloadTemporaryFile/);
});

test('proof drivers dispatch only on disposable CI and do not claim customer automatic behavior', () => {
  for (const file of ['verify_onboarding_wizard', 'verify_install_progress', 'verify_installer_journey', 'verify_universal_app_launch']) {
    const proof = read(`tool/${file}.ps1`);
    assert.match(proof, /GITHUB_ACTIONS/);
    assert.match(proof, /installerSha256/);
    assert.doesNotMatch(proof, /Register-ScheduledTask|New-ScheduledTask|Start-ScheduledTask|RunLevel Limited|Verb RunAs/);
    assert.doesNotMatch(proof, /automatic-launch|finishPageAbsent|zeroClick|welcomeAutoAdvance/);
  }
});
