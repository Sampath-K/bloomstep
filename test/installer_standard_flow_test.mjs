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
  assert.match(setup, /\[Run\][\s\S]*Description: "Launch Budlark"[\s\S]*postinstall[\s\S]*skipifsilent/);
  assert.doesNotMatch(setup, /postinstall unchecked/);
  assert.match(read('packaging/install-progress.iss'), /WizardForm\.ReadyPage/);
  assert.match(setup, /PrivilegesRequired=lowest/);
  assert.doesNotMatch(setup, /InstallFlow|HoldZeroClickVisual|ExecAsOriginalUser|BackButtonClick|NextButton\.OnClick|SetTimer|CreateCallback|PeekMessage|DispatchMessage/);
  assert.doesNotMatch(read('packaging/install-progress.iss'), /SetTimer|CreateCallback|PeekMessage|DispatchMessage|OnClick|Sleep\(/);
});

test('manual installer verification remains explicit; automated CI does not request a VM runner', () => {
  const workflow = read('.github/workflows/ci.yml');
  for (const job of ['installer-launch-evidence', 'protected-installer-lifecycle',
    'universal-native-proof', 'universal-app-launch-evidence']) {
    assert.doesNotMatch(workflow, new RegExp(`^  ${job}:`, 'm'));
  }
  assert.doesNotMatch(workflow, /runs-on:\s*\[self-hosted/);
  assert.match(workflow, /release_bundle\.mjs/);
  assert.match(read('tool/release_bundle.mjs'), /ownerManualVerification[\s\S]*status: 'PENDING'/);
  assert.match(workflow, /PENDING/);
  assert.doesNotMatch(workflow, /DInstallFlow=zeroclick|universal-zeroclick-output/);
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
