import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const installer = read('packaging/bloomstep.iss');

test('installer teaches on existing native steps without extra pages or changing security defaults', () => {
  assert.equal((installer.match(/CreateCustomPage\(/g) ?? []).length, 1);
  assert.match(installer, /ReadyMemoNote[\s\S]*routine[\s\S]*tiny[\s\S]*celebrat/);
  assert.match(installer, /FinishedLabel=.*sign-in/i);
  assert.match(installer, /independent app inspired by the Tiny Habits method/);
  assert.match(installer, /https:\/\/tinyhabits.com\/book\//);
  assert.match(installer, /PrivilegesRequired=lowest/);
  assert.match(installer, /MeasurementCheckBox.Checked := False/);
  assert.match(installer, /if WizardSilent then Exit/);
  assert.match(installer, /postinstall skipifsilent unchecked/);
  assert.doesNotMatch(installer, /ShellExec|DownloadTemporaryFile|PrivilegesRequired=admin/);
});

test('capture fixture rejects installation before effects and cannot enter production compile commands', () => {
  assert.match(installer, /#ifdef OnboardingFixture\s+function PrepareToInstall[\s\S]*?Installation is prohibited[\s\S]*?#endif/);
  assert.doesNotMatch(read('.github/workflows/ci.yml'), /\/DOnboardingFixture/);
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
