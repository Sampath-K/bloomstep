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
  assert.equal(code.split(/\r?\n/).some(line => /^\s*#\d/.test(line)), false,
    'A Pascal character code beginning a line is parsed as an ISPP directive.');
});
test('silent/default-off upgrades do not inherit prior measurement ownership', () => {
  assert.match(installer, /\[InstallDelete\][\s\S]*?Type: files; Name: "\{app\}\\measurement-owner\.txt"/);
  assert.doesNotMatch(installer, /MeasurementCheckBox|SaveStringToFile|MeasurementEvent/);
  assert.match(workflow, /Upgrade inherited a prior installation measurement owner/);
  assert.match(workflow, /Silent upgrade manufactured a measurement receipt/);
});
test('real wizard proof is separate from compile-only fixture and precedes distribution', () => {
  assert.match(workflow, /Compile-only fixture; never installed or distributed/);
  assert.match(workflow, /verify_measurement_install\.ps1 -Installer \$installer/);
  assert.ok(workflow.indexOf('Verify disabled installer observations') < workflow.indexOf('name: Publish preview'));
  const smoke = readFileSync(new URL('../tool/verify_measurement_install.ps1', import.meta.url), 'utf8');
  assert.match(smoke, /Installer observations must not exist/);
  assert.match(smoke, /Legacy unmatched receipt changed/);
  assert.match(smoke, /Owned uninstall did not remove the installer receipt/);
  assert.match(smoke, /Legacy pending receipt/);
});
