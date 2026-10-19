import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
test('integration keyboard parameters bind in Windows PowerShell without C# type aliases', () => {
  const keyboard = read('integration_test/support/windows_keyboard.dart').replaceAll('\r\n', '\n');
  const parameters = keyboard.match(/function Key\(([^)]+)\)/)[1].replaceAll('\\$', '$');
  const owner = keyboard.match(/  (\[[^\]]+\])\\\$owner = 0/)[1];
  assert.equal(parameters, '[uint16]$vk, [uint32]$flags');
  assert.equal(owner, '[uint32]');
  assert.match(keyboard, /if \(control\) 'Key 162 0'/);
  assert.match(keyboard, /if \(shift\) 'Key 160 0'/);
  const nativeTypes = keyboard.split("Add-Type @'\n")[1].split("\n'@")[0];
  const input = keyboard.split('  \\$input =')[1].split('  if ([OwnedInput]::SendInput')[0];
  assert.ok(input, 'Construct the native INPUT payload before sending it.');
  if (process.platform === 'win32') {
    execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      `Add-Type @'
${nativeTypes}
'@
      function Key(${parameters}) {
        ${owner}$owner = 0
        if ($vk -lt 1 -or $flags -ne 2 -or $owner -ne 0) { throw 'Incorrect typed input' }
        $input =${input.replaceAll('\\$', '$')}
        $expectedFlags = if ($vk -in @(36, 46, 35, 37, 39)) { 3 } else { 2 }
        if ($input.type -ne 1 -or $input.keyboard.vk -ne $vk -or $input.keyboard.flags -ne $expectedFlags -or $input.keyboard.scan -eq 0) {
          throw "Native INPUT mismatch: vk=$vk scan=$scan flags=$($input.keyboard.flags) expected=$expectedFlags"
        }
      }; foreach ($vk in @(65, 36, 46, 35, 37, 39, 162, 160)) { Key $vk 2 }`],
    { stdio: 'pipe', timeout: 20000 });
  }
});
test('compiled rendered evidence waits for dialog transitions before capturing pixels', () => {
  const capture = read('integration_test/budlark_windows_e2e_test.dart')
    .split('Future<void> _captureBuilderFrame(')[1].split('Future<void> _naturalnessReflection(')[0];
  assert.match(capture, /await tester\.pumpAndSettle\(\s*const Duration\(milliseconds: 100\),\s*EnginePhase\.sendSemanticsUpdate,\s*const Duration\(seconds: 10\),?\s*\);/);
  assert.ok(capture.indexOf('pumpAndSettle') < capture.indexOf('boundary.toImage'));
});
test('native input fixture is bounded to the CI-only ARM64 synthetic profile', () => {
  const harness = read('tool/verify_synthetic_input.ps1');
  assert.match(harness, /GITHUB_ACTIONS/);
  assert.match(harness, /build\\windows\\arm64\\runner\\Profile\\budlark\.exe/);
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
  const start = harness.split('function Start-Synthetic')[1].split('function Wait-Label')[0];
  assert.ok(start.indexOf('SetForegroundWindow') < start.indexOf('AutomationElement'),
    'Verify the actual foreground before diagnosing missing rendered accessibility.');
});
test('save, cancel, scoped practice, undo, delete and restart evidence stay synthetic', () => {
  const harness = read('tool/verify_synthetic_input.ps1');
  for (const label of ['Plant another', 'Plant this seed', 'Cancel', 'Did it', 'Undo today', 'Delete this recipe', 'Delete recipe']) {
    assert.ok(harness.includes(`'${label}'`), `Missing actual fixture action: ${label}`);
  }
  assert.match(harness, /Budlark acceptance test CI/);
  assert.match(harness, /savedPersisted/);
  assert.match(harness, /cancelAbsentAfterRestart/);
  assert.match(harness, /deletedAbsentAfterRestart/);
  assert.match(harness, /sqlite3_open_v2/);
  assert.match(harness, /readOnlyLocalState/);
  assert.match(harness, /originalSeedCheckinsPreserved/);
  assert.match(harness, /customerAcceptance.*false/);
  assert.doesNotMatch(harness, /Sign in securely|Export my data|Delete my account|Budlark\.Admin/);
});
test('CI explicitly invokes the current profile after build, without version churn', () => {
  const workflow = read('.github/workflows/ci.yml');
  assert.ok(workflow.indexOf('verify_synthetic_input.ps1') > workflow.indexOf('--profile --target tool/preview.dart'));
  assert.match(workflow, /verify_native_input:[\s\S]*?default: false/);
  assert.match(workflow, /name: Verify synthetic native input[\s\S]*?timeout-minutes: 3[\s\S]*?inputs\.verify_native_input[\s\S]*?verify_synthetic_input\.ps1/);
  assert.match(workflow, /synthetic_native_contract_test\.mjs/);
  assert.match(workflow, /budlark-synthetic-input-arm64-NOT-CUSTOMER-ACCEPTANCE/);
});
