import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const base = new URL('../tool/devbox-controller/', import.meta.url);
const read = name => readFileSync(new URL(name, base), 'utf8');

test('controller dispatch uses private main, fixed candidate choices and no public runner activation', () => {
  const workflow = read('validate.yml');
  for (const expected of ['workflow_dispatch:', "refs/heads/main", 'Sampath-K/bloomstep-vm-controller',
    'DEVBOX_CONNECTION_AUDITED', 'bloomstep-private-controller', 'cancel-in-progress: false',
    'persist-credentials: false', 'Invoke-ControllerTrial.ps1']) {
    assert.ok(workflow.includes(expected), expected);
  }
  assert.doesNotMatch(workflow, /pull_request_target:|pull_request:|defender-interactive|BLOOMSTEP_DISPOSABLE_VM|secrets\./);
  for (const [, ref] of workflow.matchAll(/uses:\s+([^\s]+)/g)) assert.match(ref, /@[a-f0-9]{40}$/);
});

test('approval contains immutable reviewed candidate and no arbitrary command/url dispatch input', () => {
  const policy = JSON.parse(read('approved-candidates.json'));
  assert.equal(policy.schema, 1);
  const candidate = policy.candidates['bd5ad93-owner-trial'];
  assert.equal(candidate.source, 'bd5ad93ad28988123ef7d3e28eab989f91cc4362');
  assert.equal(candidate.installerSha256, '664b60d44929da601e22832568d0c88d8baa70f119764958336e065ff4892162');
  assert.equal(candidate.runId, '38994109408');
  assert.match(candidate.packageUrl, /\/[a-f0-9]{40}\//);
  assert.match(candidate.packageSha256, /^[a-f0-9]{64}$/);
  const verifier = read('Verify-Candidate.ps1');
  for (const expected of ['head_sha', 'head_repository.full_name', 'universal-installer',
    'test-and-build-windows', 'Get-FileHash', "protectedGatesAccepted=$false"]) assert.ok(verifier.includes(expected), expected);
  assert.doesNotMatch(verifier, /Authorization|GH_TOKEN|GITHUB_TOKEN|Start-Process/);
});

test('candidate verifier parses before controller publication', () => {
  const file = fileURLToPath(new URL('Verify-Candidate.ps1', base));
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command',
    '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)|Out-Null;if($e.Count){$e|ForEach-Object{Write-Error $_};exit 1}'],
  { encoding:'utf8', env:{ ...process.env, SCRIPT:file } });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});
