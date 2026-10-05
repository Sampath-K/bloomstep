import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
test('native input fixture is bounded to the CI-only ARM64 synthetic profile', () => {
  const harness = read('tool/verify_synthetic_input.ps1');
  assert.match(harness, /GITHUB_ACTIONS/);
  assert.match(harness, /build\\windows\\arm64\\runner\\Profile\\bloomstep\.exe/);
  assert.match(harness, /ISOLATED SYNTHETIC PREVIEW/);
  assert.match(harness, /Existing synthetic database; refusing overwrite/);
  assert.match(harness, /peMachine.*0xaa64/);
  assert.doesNotMatch(harness, /SendInput|keybd_event|mouse_event|AttachThreadInput|AllowSetForegroundWindow|SwitchDesktop|SetThreadDesktop/);
});
test('native actions require exact ownership, real foreground and semantic focus', () => {
  const harness = read('tool/verify_synthetic_input.ps1');
  assert.match(harness, /GetWindowThreadProcessId/);
  assert.match(harness, /GetForegroundWindow/);
  assert.match(harness, /Semantic focus not established; no characters sent/);
  assert.match(harness, /exact_readback=true/);
  assert.match(harness, /Ambiguous synthetic control/);
  assert.match(harness, /Synthetic field bounds unsafe/);
  assert.match(harness, /finally/);
  assert.match(harness, /Stop-Process -Id \$app\.Id/);
  assert.match(harness, /Synthetic database cleanup failed/);
  assert.match(harness, /Host lacks synthetic interactive foreground/);
});
test('save, cancel, scoped practice, undo, delete and restart evidence stay synthetic', () => {
  const harness = read('tool/verify_synthetic_input.ps1');
  for (const label of ['Plant another', 'Plant this seed', 'Cancel', 'Did it', 'Undo today', 'Delete this recipe', 'Delete recipe']) {
    assert.ok(harness.includes(`'${label}'`), `Missing actual fixture action: ${label}`);
  }
  assert.match(harness, /Bloomstep acceptance test CI/);
  assert.match(harness, /savedPersisted/);
  assert.match(harness, /cancelAbsentAfterRestart/);
  assert.match(harness, /deletedAbsentAfterRestart/);
  assert.match(harness, /customerAcceptance.*false/);
  assert.doesNotMatch(harness, /Sign in securely|Export my data|Delete my account|Bloomstep\.Admin/);
});
test('CI explicitly invokes the current profile after build, without version churn', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.ok(workflow.indexOf('verify_synthetic_input.ps1') > workflow.indexOf('--profile --target tool/preview.dart'));
  assert.match(workflow, /verify_native_input:[\s\S]*?default: false/);
  assert.match(workflow, /name: Verify synthetic native input[\s\S]*?timeout-minutes: 3[\s\S]*?inputs\.verify_native_input[\s\S]*?verify_synthetic_input\.ps1/);
  assert.match(workflow, /synthetic_native_contract_test\.mjs/);
  assert.match(workflow, /bloomstep-synthetic-input-arm64-NOT-CUSTOMER-ACCEPTANCE/);
});
