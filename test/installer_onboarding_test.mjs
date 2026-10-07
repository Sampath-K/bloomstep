import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const installer = read('packaging/bloomstep.iss');

test('the first native wizard page is Welcome with original art and short independent-preview teaching', () => {
  assert.match(installer, /DisableWelcomePage=no/);
  assert.match(installer, /WelcomeLabel1=Welcome to Bloomstep/);
  const welcome = /^WelcomeLabel2=(.*)$/m.exec(installer)?.[1];
  assert.ok(welcome);
  assert.match(welcome, /^Anchor a routine\./);
  assert.match(welcome, /Make a tiny habit part of your day/);
  assert.match(welcome, /Anchor: after pouring my morning drink/);
  assert.match(welcome, /Anchor: after opening my laptop/);
  assert.match(welcome, /Free Windows download\. Limited preview\. Sign-in required\./);
  assert.match(welcome, /Next: plant a tiny recipe/);
  assert.doesNotMatch(welcome, /verified MVP|unsigned|affiliated|medical/);
  assert.ok(welcome.length < 550);
  assert.match(installer, /DisableDirPage=no/);
  assert.match(installer, /DisableProgramGroupPage=yes/);
  assert.match(installer, /CreateCustomPage\(wpSelectDir,/);
  const capture = read('tool/verify_onboarding_wizard.ps1');
  assert.match(capture, /First observed wizard page was not Welcome/);
  assert.match(capture, /Welcome', 'recipe', 'grow', 'destination', 'optional-observations', 'ready'/);
  assert.match(capture, /installerSha256/);
  assert.match(capture, /receiptAbsent/);
});

test('installer teaches on existing native steps without extra pages or changing security defaults', () => {
  assert.equal((installer.match(/CreateCustomPage\(/g) ?? []).length, 3);
  assert.match(installer, /ReadyMemoNote[\s\S]*routine[\s\S]*tiny[\s\S]*celebrat/);
  assert.match(installer, /FinishedLabel=.*sign-in/i);
  assert.match(installer, /independent app inspired by the Tiny Habits method/);
  assert.match(installer, /https:\/\/tinyhabits.com\/book\//);
  assert.match(installer, /PrivilegesRequired=lowest/);
  assert.match(installer, /MeasurementCheckBox.Checked := False/);
  assert.match(installer, /if WizardSilent then Exit/);
  assert.match(installer, /postinstall skipifsilent runasoriginaluser/);
  assert.doesNotMatch(installer, /ShellExec|DownloadTemporaryFile|PrivilegesRequired=admin/);
});

test('capture fixture rejects installation before effects and cannot enter production compile commands', () => {
  assert.match(installer, /#ifdef OnboardingFixture\s+function PrepareToInstall[\s\S]*?Installation is prohibited[\s\S]*?#endif/);
  const production = read('.github/workflows/ci.yml').split('name: Build unsigned preview installer')[1].split('name: Installer lifecycle smoke test')[0];
  assert.doesNotMatch(production, /\/DOnboardingFixture/);
});

test('wizard art is explicit, strict, real BMP and reproducible', () => {
  assert.match(installer, /WizardImageFile=assets\\wizard-garden.bmp/);
  assert.match(installer, /WizardSmallImageFile=assets\\wizard-seed.bmp/);
  assert.doesNotMatch(installer, /skipifsourcedoesntexist/);
  for (const [name, width, height] of [['garden', 164, 314], ['seed', 55, 55]]) {
    const bmp = readFileSync(new URL(`../packaging/assets/wizard-${name}.bmp`, import.meta.url));
    assert.equal(bmp.subarray(0, 2).toString(), 'BM');
    assert.equal(bmp.readInt32LE(18), width);
    assert.equal(bmp.readInt32LE(22), height);
    assert.equal(bmp.readUInt16LE(28), 24);
    assert.equal(bmp.readUInt32LE(2), bmp.length);
  }
  const result = spawnSync(process.execPath,
    [fileURLToPath(new URL('../tool/generate_installer_art.mjs', import.meta.url)), '--check'],
    { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(read('.github/workflows/ci.yml'), /test\/installer_onboarding_test.mjs/);
});
