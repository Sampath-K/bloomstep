import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('inert journey proof tests checked, unchecked, silent, suppressed, cancel, failure and elevated branches', () => {
  const proof = read('tool/verify_installer_journey.ps1');
  for (const scenario of ['checked-launch', 'unchecked-launch', 'silent', 'unattended', 'cancel', 'failure', 'elevated']) {
    assert.ok(proof.includes(scenario), scenario);
  }
  assert.match(proof, /GITHUB_ACTIONS/);
  assert.match(proof, /BUDLARK_ISOLATED_JOURNEY_FIXTURE/);
  assert.match(proof, /BUDLARK_DISPOSABLE_VM/);
  assert.match(proof, /compiledFixture\.installerSha256[\s\S]*Get-FileHash/);
  assert.match(proof, /exact hash-authorized compiled inert journey fixture/);
  assert.match(proof, /Invoke-StandardWizardStep/);
  assert.match(proof, /Assert-StandardWizardJourney/);
  assert.match(proof, /Launch count mismatch/);
  assert.match(proof, /Installing user or non-elevated launch token mismatch/);
  assert.match(proof, /100, 150, 200/);
  assert.match(proof, /proofAutomation/);
});

test('proof fails closed on wrong token or desktop, never lowers or raises it', () => {
  const proof = read('tool/verify_installer_journey.ps1');
  assert.match(proof, /Normal launch proof must have an actual non-elevated token/);
  assert.match(proof, /Elevated no-launch branch needs an actual elevated CI token/);
  assert.match(proof, /UserInteractive/);
  assert.doesNotMatch(proof, /ScheduledTask|RunLevel|Verb RunAs|\$Worker/);
  assert.match(proof, /if \(\$launches.Count -ne \$expected\) \{ throw/);
  assert.match(proof, /if \(\$launches\[0\]\.sid -ne \$sid -or \$launches\[0\]\.elevated\) \{ throw/);
  assert.match(proof, /errorType/);
  assert.match(proof, /errorLine/);
  assert.doesNotMatch(proof, /errorMessage\s*=|userName\s*=/);
});

test('source never manufactures observations and installer launch is outside automated CI', () => {
  const installer = read('packaging/budlark.iss');
  assert.doesNotMatch(installer, /CreateCustomPage|SaveStringToFile|CoCreateGuid|MeasurementCheckBox/);
  const workflow = read('.github/workflows/ci.yml');
  for (const job of ['installer-launch-evidence', 'protected-installer-lifecycle',
    'universal-native-proof', 'universal-app-launch-evidence']) {
    assert.doesNotMatch(workflow, new RegExp(`^  ${job}:`, 'm'));
  }
  assert.doesNotMatch(workflow, /runs-on:\s*\[self-hosted/);
  assert.match(read('tool/verify_installer_journey.ps1'),
    /\[ValidateSet\('checked-launch','unchecked-launch','silent','unattended','cancel','failure','elevated'\)\]/);
  assert.match(read('tool/release_bundle.mjs'), /ownerManualVerification[\s\S]*status: 'PENDING'/);
});
