import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const installer = read('packaging/bloomstep.iss');

test('three original educational beats precede options without tracking or a forced exercise', () => {
  assert.match(installer, /WelcomeLabel2=Your garden starts with one seed\./);
  assert.match(installer, /RecipePage := CreateCustomPage\(wpWelcome, 'A tiny recipe'/);
  assert.match(installer, /GrowPage := CreateCustomPage\(RecipePage.ID, 'Watch it become a garden'/);
  assert.match(installer, /DisableDirPage=no/);
  assert.match(installer, /DisableProgramGroupPage=yes/);
  assert.match(installer, /UsePreviousAppDir=yes/);
  assert.match(installer, /Not today.*preserves.*growth/);
  assert.match(installer, /Tiny action: take one slow breath/);
  assert.match(installer, /Tiny action: write my one next step/);
  assert.match(installer, /Celebration: relax my shoulders and smile/);
  assert.match(installer, /Celebration: say "I have a starting point"/);
  assert.match(installer, /Source: "assets\\education-seed.bmp"; Flags: dontcopy/);
  assert.match(installer, /Source: "assets\\education-growth.bmp"; Flags: dontcopy/);
  assert.match(installer, /function ShouldSkipPage[\s\S]*WizardSilent[\s\S]*RecipePage.ID[\s\S]*GrowPage.ID/);
  assert.doesNotMatch(installer, /education_step_view|stepview|education_link_click/);
});

test('Finish launch is default checked, user-toggleable, successful interactive non-elevated only', () => {
  const entry = installer.split('[Run]')[1].split('[UninstallDelete]')[0];
  assert.match(entry, /Description: "Launch Bloomstep and plant your first habit"/);
  assert.match(entry, /postinstall skipifsilent runasoriginaluser/);
  assert.match(entry, /Check: CanLaunchBloomstep; AfterInstall: MarkBloomstepLaunched/);
  assert.doesNotMatch(entry, /unchecked|runascurrentuser|runhidden/);
  const gate = /function CanLaunchBloomstep\(\): Boolean;([\s\S]*?)end;/.exec(installer)?.[1];
  assert.ok(gate);
  for (const guard of ['InstallationSucceeded', 'not WizardSilent', 'not IsAdmin', 'not LaunchAttempted', 'InteractiveDesktop']) {
    assert.ok(gate.includes(guard), guard);
  }
  assert.match(installer, /if CurStep = ssPostInstall then InstallationSucceeded := True;/);
  assert.match(installer, /procedure MarkBloomstepLaunched\(\);[\s\S]*?LaunchAttempted := True;/);
  assert.match(installer, /procedure CurPageChanged[\s\S]*wpFinished[\s\S]*elevated|procedure CurPageChanged[\s\S]*wpFinished[\s\S]*administrator/);
  const proof = read('tool/verify_installer_journey.ps1');
  for (const scenario of ['checked-launch', 'unchecked-launch', 'silent', 'unattended', 'cancel', 'failure', 'elevated']) {
    assert.ok(proof.includes(scenario), scenario);
  }
  assert.match(proof, /Launch count/);
  assert.match(proof, /Installing user/);
  assert.match(proof, /100, 150, 200/);
  assert.match(proof, /compiledFixture\.installerSha256[\s\S]*Get-FileHash/);
  assert.match(proof, /exact hash-authorized compiled inert journey fixture/);
});

test('limited-task failures preserve sanitized diagnostics without weakening launch assertions', () => {
  const proof = read('tool/verify_installer_journey.ps1');
  assert.match(proof, /function Write-JourneyWorkerDiagnostic/);
  assert.match(proof, /trap\s*\{[\s\S]*Write-JourneyWorkerDiagnostic[\s\S]*throw/);
  assert.match(proof, /trap\s*\{[\s\S]*\$originalFailure = \$_[\s\S]*throw \$originalFailure/);
  for (const field of ['taskState', 'lastTaskResult', 'workerDiagnosticPresent', 'outcomePresent',
    'sessionId', 'userInteractive', 'tokenElevated', 'errorType', 'errorLine']) {
    assert.ok(proof.includes(field), field);
  }
  assert.match(proof, /Write-JourneyWorkerDiagnostic -Stage 'starting'/);
  assert.match(proof, /Write-JourneyWorkerDiagnostic -Stage 'helpers-loaded'/);
  assert.match(proof, /"\$Mode-task-diagnostic\.json"/);
  assert.match(proof, /"\$Mode-worker-diagnostic\.json"/);
  assert.match(proof, /classification = 'UNKNOWN/);
  assert.match(proof, /if \(-not \(Test-Path \$result\)\) \{[\s\S]*throw/);
  assert.doesNotMatch(proof, /errorMessage\s*=|userName\s*=|workerSid\s*=/);
  assert.match(proof, /if \(\$launches.Count -ne \$expected\) \{ throw/);
  assert.match(proof, /if \(\$launches\[0\]\.sid -ne \$sid -or \$launches\[0\]\.elevated\) \{ throw/);
});

test('exact owner trials preserve visible failed launch evidence and required native gates', () => {
  const workflow = read('.github/workflows/ci.yml');
  const evidence = workflow.split('  installer-launch-evidence:')[1]?.split('  test-and-build-windows:')[0];
  assert.ok(evidence);
  assert.match(evidence, /launch-after-install: UNVERIFIED \(preview gap, owner manual trial pending\)/);
  assert.match(evidence, /if: always\(\)/);
  assert.doesNotMatch(evidence, /continue-on-error/);
  const ordinary = workflow.split('  test-and-build-windows:')[1].split('  release:')[0];
  assert.doesNotMatch(ordinary, /verify_installer_journey\.ps1/);
  const release = workflow.split('  release:')[1];
  assert.match(release, /needs: \[api, test-and-build-windows, installer-launch-evidence, universal-native-proof, universal-app-launch-evidence\]/);
  assert.match(release, /needs\.universal-native-proof\.result == 'success'/);
  assert.match(release, /needs\.universal-app-launch-evidence\.result == 'success'/);
  assert.match(release, /needs\.api\.result == 'success'/);
  assert.match(release, /needs\.test-and-build-windows\.result == 'success'/);
  assert.match(release, /needs\.installer-launch-evidence\.result == 'success' \|\| github\.ref_name == 'v0\.1\.0-preview\.10'/);
  assert.match(release, /github\.ref_name == 'v0\.1\.0-preview\.12'/);
  assert.match(release, /genuine launch-after-Finish: UNVERIFIED/);
  assert.match(release, /release-proof/);
  assert.match(release, /owner trial only/);
  assert.match(release, /launch-after-install: not yet verified, pending owner manual trial/);
  assert.match(release, /public site remains on preview\.9/);
});
