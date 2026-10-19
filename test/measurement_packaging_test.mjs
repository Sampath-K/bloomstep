import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const installer = readFileSync(new URL('../packaging/budlark.iss', import.meta.url), 'utf8');
const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
test('Pascal code cannot be mistaken for an Inno section tag', () => {
  const code = installer.split('[Code]')[1];
  assert.ok(code);
  assert.equal(code.split(/\r?\n/).some(line => /^\s*\[/.test(line)), false,
    'A Pascal array beginning a line is parsed as an invalid section tag by ISCC.');
  assert.equal(code.split(/\r?\n/).some(line => /^\s*#\d/.test(line)), false,
    'A Pascal character code beginning a line is parsed as an ISPP directive.');
});
test('silent/default-off upgrades do not inherit prior measurement ownership', () => {
  assert.match(installer, /\[InstallDelete\][\s\S]*?Type: files; Name: "\{app\}\\measurement-owner\.txt"/);
  assert.doesNotMatch(installer, /MeasurementCheckBox|SaveStringToFile|MeasurementEvent/);
  assert.match(workflow, /Record owner manual installer verification as pending/);
  assert.match(workflow, /CI did not install or launch it/);
});
test('compile-only fixture and retained privacy proof do not imply manual installer acceptance', () => {
  assert.match(workflow, /Compile-only fixture; never installed or distributed/);
  assert.doesNotMatch(workflow, /verify_measurement_install\.ps1 -Installer \$installer/);
  assert.doesNotMatch(workflow, /runs-on:\s*\[self-hosted/);
  const release = readFileSync(new URL('../tool/release_bundle.mjs', import.meta.url), 'utf8');
  assert.match(release, /ownerManualVerification:[\s\S]*status: 'PENDING'/);
  assert.match(release, /requiredBeforeCustomerLaunch: true/);
  assert.match(release, /recordedResult: null/);
  const smoke = readFileSync(new URL('../tool/verify_measurement_install.ps1', import.meta.url), 'utf8');
  assert.match(smoke, /Installer observations must not exist/);
  assert.match(smoke, /Legacy unmatched receipt changed/);
  assert.match(smoke, /Owned uninstall did not remove the installer receipt/);
  assert.match(smoke, /Legacy pending receipt/);
});
