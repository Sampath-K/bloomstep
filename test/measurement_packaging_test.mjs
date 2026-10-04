import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const installer = readFileSync(new URL('../packaging/bloomstep.iss', import.meta.url), 'utf8');
const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
test('Pascal code cannot be mistaken for an Inno section tag', () => {
  const code = installer.split('[Code]')[1];
  assert.ok(code);
  assert.equal(code.split(/\r?\n/).some(line => /^\s*\[/.test(line)), false,
    'A Pascal array beginning a line is parsed as an invalid section tag by ISCC.');
});
test('silent/default-off upgrades do not inherit prior measurement ownership', () => {
  assert.match(installer, /\[InstallDelete\][\s\S]*?Type: files; Name: "\{app\}\\measurement-owner\.txt"/);
  assert.match(installer, /MeasurementCheckBox\.Checked := False/);
  const callback = installer.split('procedure CurStepChanged')[1].split('procedure CurUninstallStepChanged')[0];
  assert.ok(callback.indexOf('if WizardSilent then Exit') < callback.indexOf("MeasurementEvent('installer_started'"));
  assert.ok(callback.indexOf('if not MeasurementCheckBox.Checked then Exit') < callback.indexOf("MeasurementEvent('installer_started'"));
  assert.match(workflow, /Upgrade inherited a prior installation measurement owner/);
  assert.match(workflow, /Silent upgrade manufactured a measurement receipt/);
});
test('real wizard proof is separate from compile-only fixture and precedes distribution', () => {
  assert.match(workflow, /Compile-only fixture; never installed or distributed/);
  assert.match(workflow, /verify_measurement_install\.ps1 -Installer \$installer/);
  assert.ok(workflow.indexOf('Verify optional measurement wizard') < workflow.indexOf('name: Publish preview'));
  const smoke = readFileSync(new URL('../tool/verify_measurement_install.ps1', import.meta.url), 'utf8');
  assert.match(smoke, /Installer observation consent was not default-off/);
  assert.match(smoke, /installer_started,install_completed,first_launch,signin_view/);
  assert.match(smoke, /Owned uninstall did not remove the installer receipt/);
  // Inno Setup 6 modern wizard actually exposes "&Next", without a chevron.
  assert.match(smoke, /@\('&Next','&Next >'/);
});
