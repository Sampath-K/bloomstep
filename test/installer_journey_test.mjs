import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const installer = read('packaging/bloomstep.iss');

test('three original educational beats precede options without tracking or a forced exercise', () => {
  assert.match(installer, /WelcomeLabel2=Anchor a routine\./);
  assert.match(installer, /RecipePage := CreateCustomPage\(wpWelcome, 'Plant a tiny recipe'/);
  assert.match(installer, /GrowPage := CreateCustomPage\(RecipePage.ID, 'Celebrate and grow'/);
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
