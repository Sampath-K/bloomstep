import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('one native Install commitment replaces extra Next screens without autonomous navigation', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /DisableWelcomePage=yes/);
  assert.match(setup, /DisableDirPage=yes/);
  assert.match(setup, /DisableReadyPage=no/);
  assert.match(setup, /DisableReadyMemo=yes/);
  assert.match(setup, /DisableFinishedPage=no/);
  assert.match(setup, /\[Run\][\s\S]*Description: "Launch Bloomstep"[\s\S]*postinstall[\s\S]*skipifsilent/);
  assert.doesNotMatch(setup, /postinstall unchecked/);
  assert.match(read('packaging/install-progress.iss'), /WizardForm\.ReadyPage/);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.doesNotMatch(setup, /InstallFlow|HoldZeroClickVisual|ExecAsOriginalUser|BackButtonClick|NextButton\.OnClick|SetTimer|CreateCallback|PeekMessage|DispatchMessage/);
  assert.doesNotMatch(read('packaging/install-progress.iss'), /SetTimer|CreateCallback|PeekMessage|DispatchMessage|OnClick|Sleep\(/);
});

test('launch jobs require protected disposable interactive runner, never enable protection', () => {
  const workflow = read('.github/workflows/ci.yml');
  for (const job of ['installer-launch-evidence', 'universal-app-launch-evidence']) {
    const section = workflow.split(`  ${job}:`)[1]?.split(/\n  [a-z][a-z-]+:/)[0];
    assert.ok(section);
    assert.match(section, /runs-on: \[self-hosted, defender-interactive(?:, '[^']+')?\]/);
    assert.match(section, /setup_defender_test_vm\.ps1/);
  }
  assert.doesNotMatch(workflow, /DInstallFlow=zeroclick|universal-zeroclick-output/);
  const script = read('tool/setup_defender_test_vm.ps1');
  for (const key of ['Get-MpComputerStatus', 'RealTimeProtectionEnabled', 'BehaviorMonitorEnabled', 'AntivirusEnabled',
    'WindowsPrincipal', 'UserInteractive', 'BLOOMSTEP_DISPOSABLE_VM', 'Get-FileHash', 'Get-MpThreatDetection', 'Start-MpScan']) {
    assert.ok(script.includes(key), key);
  }
  assert.doesNotMatch(script, /Set-MpPreference|Add-MpPreference|Remove-MpThreat|Register-ScheduledTask/);
  const docs = read('docs/defender-test-vm.md');
  assert.match(docs, /Hyper-V/);
  assert.match(docs, /defender-interactive/);
  assert.match(docs, /ephemeral/);
  assert.match(docs, /standard user/);
  assert.match(docs, /withdrawn/);
});

test('VM tooling cannot execute without exact authority or leave security failures success-shaped', () => {
  const script = read('tool/setup_defender_test_vm.ps1');
  assert.match(script, /Model -ne 'Virtual Machine'/);
  assert.match(script, /OpenInputDesktop/);
  assert.match(script, /SessionId -eq 0/);
  assert.match(script, /ExpectedSha256\.ToLower\(\) -eq \$withdrawnHash/);
  assert.match(script, /actualHash -ne \$ExpectedSha256\.ToLower\(\)/);
  assert.ok(script.indexOf('Start-MpScan') < script.indexOf('Start-Process'));
  assert.ok(script.indexOf('Protection changed before launch') < script.indexOf('Start-Process'));
  assert.match(script, /Defender behavior detection during execution/);
  assert.match(script, /finally[\s\S]*vm-security-receipt\.json/);
  assert.match(script, /catch[\s\S]*throw/);
  assert.doesNotMatch(script, /--token|config\.cmd|New-VM|Enable-VM|Set-VM/);
});
