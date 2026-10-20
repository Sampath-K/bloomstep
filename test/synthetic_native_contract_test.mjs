import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
const keyboardScript = keyboard => keyboard.match(/final script =\s*'''\n([\s\S]*?)\n''';/)[1]
  .replace(/\$\{(?:control|shift).*?\}/g, '$false').replaceAll('\\$', '$');

test('hosted ARM64 feedback mode is explicit and leaves x64 native input intact', () => {
  const keyboard = read('integration_test/support/windows_keyboard.dart');
  const acceptance = read('integration_test/budlark_windows_e2e_test.dart');
  const workflow = read('.github/workflows/ci.yml');
  assert.match(keyboard, /BUDLARK_HOSTED_ARM64_FOREGROUND_RESTRICTED/);
  assert.match(keyboard, /Abi\.current\(\) != Abi\.windowsArm64/);
  assert.match(keyboard, /HOSTED ARM64 FOREGROUND RESTRICTION/);
  assert.match(keyboard, /sendKeyDownEvent\(LogicalKeyboardKey\.controlLeft\)/);
  assert.match(keyboard, /sendKeyUpEvent\(LogicalKeyboardKey\.controlLeft\)/);
  assert.match(acceptance, /hostedArm64Feedback \? 'Hosted ARM64 Flutter-key' : 'Win32'/);
  assert.match(acceptance, /if \(hostedArm64Feedback\) \{[\s\S]*hostedArm64FeedbackKeys[\s\S]*\} else \{[\s\S]*windowsKeys/);
  assert.match(workflow, /if \('\$\{\{ matrix\.runner \}\}' -eq 'windows-11-arm'\)/);
  assert.match(workflow, /BUDLARK_HOSTED_ARM64_FOREGROUND_RESTRICTED=false/);
  assert.match(workflow, /BUDLARK_HOSTED_ARM64_FOREGROUND_RESTRICTED=true/);
  assert.match(workflow, /foreground lock timeout=2147483647/);
});

test('owned keyboard activation stays bounded and checks exact foreground before every key', () => {
  const keyboard = read('integration_test/support/windows_keyboard.dart').replaceAll('\r\n', '\n');
  assert.match(keyboard, /'AllowSetForegroundWindow'/);
  assert.match(keyboard, /permit\(helper\.pid\)/);
  assert.match(keyboard, /MainWindowHandle/);
  assert.match(keyboard, /foreground -ne \\\$owned -or \\\$owner -ne \$pid/);
  assert.match(keyboard, /IsIconic/);
  assert.match(keyboard, /IsWindowVisible/);
  assert.match(keyboard, /foregroundLockTimeout/);
  assert.match(keyboard, /GetClassName/);
  assert.match(keyboard, /if \(-not \\\$ready\) \{[\s\S]*AttachThreadInput/);
  assert.match(keyboard, /finally \{[\s\S]*AttachThreadInput\(\\\$currentThread, \\\$targetThread, \\\$false\)/);
  assert.match(keyboard, /ElapsedMilliseconds -lt 2000/);
  assert.match(keyboard, /debugPrint\(permission\)/);
  assert.match(keyboard, /debugPrint\(diagnostic\)/);
  assert.ok(keyboard.includes('Native keyboard input failed:\\n$permission\\n$diagnostic$error'),
    'GUI-process stdout diagnostics must also reach captured Flutter failure output.');
  assert.doesNotMatch(keyboard, /SwitchDesktop|SetThreadDesktop|ASFW_ANY/);
  if (process.platform === 'win32') {
    const script = keyboardScript(keyboard);
    execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      `$tokens = $null; $parseErrors = $null
      [void][Management.Automation.Language.Parser]::ParseInput(
        [Console]::In.ReadToEnd(), [ref]$tokens, [ref]$parseErrors)
      if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }`],
    { input: script, stdio: ['pipe', 'pipe', 'pipe'], timeout: 20000 });
  }
});
test('actual PowerShell activation flow restores, detaches and refuses input after ownership loss', {
  skip: process.platform !== 'win32',
}, () => {
  const source = keyboardScript(read('integration_test/support/windows_keyboard.dart').replaceAll('\r\n', '\n'));
  for (const mode of ['normal', 'attach', 'denied', 'lost']) {
    const mock = `using System;
      using System.Text;
      using System.Collections.Generic;
      public static class OwnedInput {
        public struct Keyboard { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
        public struct Input { public uint type; public Keyboard keyboard; }
        public struct Message { public IntPtr hwnd; }
        public static int Reads, Sent, Attached, Detached, Restored, Activated, Raised;
        static bool QueueReady;
        static string Mode = "${mode}";
        public static IntPtr Foreground = new IntPtr(99);
        static HashSet<uint> threads = new HashSet<uint>();
        public static IntPtr GetForegroundWindow() {
          Reads++;
          return Mode == "lost" && Reads >= 5 ? new IntPtr(99) : Foreground;
        }
        public static uint GetWindowThreadProcessId(IntPtr h, out uint p) { p = h.ToInt64() == 42 ? 424242u : 333u; return h.ToInt64() == 42 ? 7u : 3u; }
        public static int GetClassName(IntPtr h, StringBuilder name, int size) { name.Append("mock"); return 4; }
        public static bool IsIconic(IntPtr h) { return false; }
        public static bool IsWindowVisible(IntPtr h) { return true; }
        public static bool SystemParametersInfo(uint a, uint p, out uint v, uint f) { v = 200000; return true; }
        static void CheckOwned(IntPtr h) { if (h.ToInt64() != 42) throw new Exception("activated non-owned HWND"); }
        public static bool ShowWindow(IntPtr h, int command) { CheckOwned(h); if (command != 9) throw new Exception("not SW_RESTORE"); Restored++; return true; }
        public static bool SetForegroundWindow(IntPtr h) {
          CheckOwned(h); Activated++;
          if (Mode == "normal" || Mode == "lost" || (Mode == "attach" && threads.Count == 2)) Foreground = h;
          return Foreground == h;
        }
        public static bool BringWindowToTop(IntPtr h) { CheckOwned(h); Raised++; return true; }
        public static uint GetCurrentThreadId() { return 1; }
        public static bool PeekMessage(out Message message, IntPtr window, uint min, uint max, uint remove) {
          message = new Message(); QueueReady = true; return false;
        }
        public static bool AttachThreadInput(uint from, uint to, bool attach) {
          if (!QueueReady) throw new Exception("missing helper message queue");
          if (from != 1 || (to != 3 && to != 7)) throw new Exception("unexpected thread");
          if (attach) { threads.Add(to); Attached++; } else { threads.Remove(to); Detached++; }
          return true;
        }
        public static uint MapVirtualKey(uint vk, uint type) { return vk; }
        public static uint SendInput(uint count, Input[] input, int size) {
          if (GetForegroundWindow().ToInt64() != 42 || threads.Count != 0) throw new Exception("unsafe input");
          Sent++; return 1;
        }
      }`;
    const script = source.replace(/Add-Type @'\n[\s\S]*?\n'@/, `Add-Type @'\n${mock}\n'@`)
      .replace("[Console]::ReadLine()", "'activate-owned-window'")
      .replace('[Diagnostics.Process]::GetProcessById($pid).MainWindowHandle', '[IntPtr]42')
      .replaceAll('$pid', '424242').replace('$sequence', 'Key 65 0\nKey 65 2');
    const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      `try { ${script} } catch { Write-Output ("caught=" + $_.Exception.Message) }
      Write-Output ("counts={0},{1},{2},{3},{4},{5}" -f [OwnedInput]::Sent, [OwnedInput]::Attached, [OwnedInput]::Detached, [OwnedInput]::Restored, [OwnedInput]::Activated, [OwnedInput]::Raised)`],
    { encoding: 'utf8', timeout: 15000 });
    const fallback = mode === 'attach' || mode === 'denied';
    const sends = mode === 'normal' || mode === 'attach' ? 2 : 0;
    assert.match(output, new RegExp(`counts=${sends},${fallback ? '2,2,2,2,2' : '0,0,1,1,1'}`), mode);
    if (sends) assert.doesNotMatch(output, /caught=/, mode);
    else assert.match(output, /caught=Owned test (?:HWND could not become|window is not) foreground; no keys sent\./, mode);
  }
});
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
