import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('disposable Defender gate scans the quarantined exact artifact, never rebuilds or executes it', () => {
  const workflow = read('.github/workflows/installer-security.yml');
  assert.match(workflow, /runs-on: windows-latest/);
  assert.match(workflow, /run-id: 37815203643/);
  assert.match(workflow, /bloomstep-universal-zeroclick-installer-PRIVATE-EXPERIMENT/);
  assert.match(workflow, /bloomstep-windows-x64/);
  assert.match(workflow, /bloomstep-windows-arm64/);
  assert.match(workflow, /if: always\(\)/);
  assert.doesNotMatch(workflow, /ISCC|flutter build|release:|gh release/);
});

test('security preflight fails closed and its static scan cannot override behavior quarantine', () => {
  const script = read('tool/verify_installer_security.ps1');
  for (const value of ['Get-MpComputerStatus', 'Start-MpScan', 'Get-MpThreatDetection',
    'RealTimeProtectionEnabled', 'BehaviorMonitorEnabled', 'AntivirusEnabled',
    'AMRunningMode', 'sourceRevision', 'candidateSha256', 'signatureVersion',
    'nonElevatedExecution', 'localBehaviorQuarantine', 'finally']) {
    assert.ok(script.includes(value), value);
  }
  assert.match(script, /b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5/);
  assert.match(script, /throw 'Defender protection unavailable or inactive/);
  assert.match(script, /throw 'Defender detected threats/);
  assert.doesNotMatch(script, /Set-MpPreference|Add-MpPreference|Remove-MpThreat|Restore-Mp|Start-Process|Invoke-Expression|ExecAsOriginalUser/);
});
