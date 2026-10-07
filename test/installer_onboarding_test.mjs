import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const installer = read('packaging/bloomstep.iss');

test('the first native wizard page is destination with one explicit Install commitment', () => {
  assert.match(installer, /DisableWelcomePage=yes/);
  assert.match(installer, /DisableReadyPage=yes/);
  assert.match(installer, /DisableDirPage=no/);
  assert.match(installer, /DisableProgramGroupPage=yes/);
  assert.doesNotMatch(installer, /CreateCustomPage\(/);
  const capture = read('tool/verify_onboarding_wizard.ps1');
  assert.match(capture, /First observed wizard page was not destination/);
  assert.match(capture, /expectedOrder = @\('destination'\)/);
  assert.match(capture, /installerSha256/);
  assert.match(capture, /receiptAbsent/);
  assert.match(capture, /compiledFixture\.installationProhibited/);
  assert.match(capture, /compiledFixture\.installerSha256[\s\S]*Get-FileHash/);
  assert.match(capture, /Only the exact hash-authorized compile-only onboarding fixture/);
});

test('installer teaches only during real progress without extra pages or changing security defaults', () => {
  assert.equal((installer.match(/CreateCustomPage\(/g) ?? []).length, 0);
  assert.match(read('packaging/install-progress.iss'), /routine[\s\S]*tiny[\s\S]*Celebrate/);
  assert.match(installer, /FinishedLabel=.*sign[ -]in/i);
  assert.match(installer, /PrivilegesRequired=lowest/);
  assert.doesNotMatch(installer, /MeasurementCheckBox|SaveStringToFile/);
  assert.match(read('packaging/install-progress.iss'), /if WizardSilent then Exit/);
  assert.match(installer, /postinstall skipifsilent runasoriginaluser/);
  assert.doesNotMatch(installer, /ShellExec|DownloadTemporaryFile|PrivilegesRequired=admin/);
});

test('capture fixture rejects installation before effects and cannot enter production compile commands', () => {
  assert.match(installer, /#ifdef OnboardingFixture\s+function PrepareToInstall[\s\S]*?Installation is prohibited[\s\S]*?#endif/);
  const production = read('.github/workflows/ci.yml').split('name: Build unsigned preview installer')[1].split('name: Installer lifecycle smoke test')[0];
  assert.doesNotMatch(production, /\/DOnboardingFixture/);
  const capture = read('.github/workflows/ci.yml').split('name: Capture compile-only native destination')[1]
    .split('name: Preserve bounded compile-only capture fixture authority')[0];
  assert.ok(capture.indexOf('New-Item -ItemType Directory -Path $output, $evidence -Force') >= 0);
  assert.ok(capture.indexOf('New-Item -ItemType Directory') < capture.indexOf('/DOnboardingPreprocessOutput='),
    'Inno preprocessing writes before the compiler creates its output directory.');
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

test('full-panel illustrations export actual supported PlantArt and are not screenshot evidence', () => {
  const exporter = read('tool/installer_art_export_test.dart');
  assert.match(exporter, /PlantArt/);
  assert.match(exporter, /GrowthStage.values/);
  assert.match(exporter, /debugShowCheckedModeBanner: false/);
  assert.doesNotMatch(exporter, /evergreen|GrowthStage\.tree/);
  const manifest = JSON.parse(read('packaging/assets/education-art-provenance.json'));
  assert.equal(manifest.kind, 'authored-illustrations-not-installer-screenshots');
  assert.equal(manifest.sourceNormalization, 'UTF-8 text with LF line endings');
  for (const source of manifest.sources) {
    const text = read(source.path).replace(/\r\n/g, '\n');
    assert.equal(createHash('sha256').update(text).digest('hex'), source.sha256);
  }
  for (const name of ['education-seed', 'education-recipe', 'education-growth', 'education-hero']) {
    const bmp = readFileSync(new URL(`../packaging/assets/${name}.bmp`, import.meta.url));
    assert.equal(bmp.readInt32LE(18), 1000);
    assert.equal(bmp.readInt32LE(22), name === 'education-hero' ? 260 : 420);
    assert.match(installer, new RegExp(`assets\\\\${name}\\.bmp`));
  }
});
