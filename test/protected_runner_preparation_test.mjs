import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = new URL('../tool/prepare_protected_runner.ps1', import.meta.url);
const text = readFileSync(script, 'utf8');
const guide = readFileSync(new URL('../docs/protected-runner-operator.md', import.meta.url), 'utf8');

test('preparation requires confirmation, exact source, architecture and existing protected preflight', () => {
  for (const required of ['CHECK DISPOSABLE VM', '$ExpectedSource', '$ExpectedArch',
    'status --porcelain', 'setup_defender_test_vm.ps1', '-Mode Check',
    'PREFLIGHT PASS ONLY; no installer or app execution',
    'inno_compiler_version.ps1', 'inno-toolchain-probe.iss', 'Get-InnoEngineVersion']) {
    assert.ok(text.includes(required), required);
  }
  assert.doesNotMatch(text, /config\.cmd|run\.cmd|Start-Process|Set-ExecutionPolicy|Set-MpPreference|Invoke-WebRequest|registration-token/);
});

test('guide fails closed on unpinned public runner scheduling and separates native coverage', () => {
  for (const required of ['Registration is BLOCKED', 'not an atomic security boundary',
    'No protected job currently declares', 'BOTH native OS architectures',
    'REGISTER ONE REVIEWED JOB', 'RUN ONE REVIEWED JOB',
    'ACTIONS_RUNNER_INPUT_TOKEN', 'ZeroFreeBSTR', 'No merge, tag, publication']) {
    assert.ok(guide.includes(required), required);
  }
});

test('PowerShell preparation script parses without execution', () => {
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command',
    '$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($env:BUDLARK_PREPARATION_SCRIPT, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }'],
  { encoding: 'utf8', env: { ...process.env, BUDLARK_PREPARATION_SCRIPT: fileURLToPath(script) } });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});

test('operator PowerShell command blocks parse without execution', () => {
  for (const [, block] of guide.matchAll(/```powershell\n([\s\S]*?)```/g)) {
    const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command',
      '$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseInput($env:BUDLARK_OPERATOR_BLOCK, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }'],
    { encoding: 'utf8', env: { ...process.env, BUDLARK_OPERATOR_BLOCK: block } });
    assert.equal(result.status, 0, result.stderr || result.error?.message);
  }
});
