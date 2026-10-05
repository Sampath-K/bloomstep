import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

const helper = fileURLToPath(new URL('../infra/identity-callbacks.ps1', import.meta.url));
const tenant = '11111111-2222-4333-8444-555555555555';
function evaluate(expression) {
  const script = `$ErrorActionPreference = 'Stop'; . '${helper.replaceAll("'", "''")}'; ${expression}`;
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return JSON.parse(result.stdout);
}

test('federation callbacks include the observed canonical tenant-ID host, not the native loopback', () => {
  const callbacks = evaluate(`@(Get-BloomstepFederationCallbacks -TenantId '${tenant}' -Subdomain 'examplecustomers' -Domain 'examplecustomers.onmicrosoft.com') | ConvertTo-Json -AsArray`);
  assert.deepEqual(callbacks, [
    `https://${tenant}.ciamlogin.com/${tenant}/federation/oauth2`,
    `https://examplecustomers.ciamlogin.com/${tenant}/federation/oauth2`,
    'https://examplecustomers.ciamlogin.com/examplecustomers.onmicrosoft.com/federation/oauth2',
  ]);
  assert.ok(callbacks.every(uri => uri.startsWith('https://') && !uri.includes('*') && !uri.includes('127.0.0.1')));
});

test('callback reconciliation preserves existing registrations and is idempotent', () => {
  const callbacks = evaluate(`$required = @(Get-BloomstepFederationCallbacks -TenantId '${tenant}' -Subdomain 'examplecustomers' -Domain 'examplecustomers.onmicrosoft.com'); $existing = @('https://preserved.example/callback', $required[1]); $first = @(Merge-BloomstepFederationCallbacks -Existing $existing -Required $required); $second = @(Merge-BloomstepFederationCallbacks -Existing $first -Required $required); @{ first = $first; second = $second } | ConvertTo-Json -Depth 4`);
  assert.equal(callbacks.first.length, 4);
  assert.equal(callbacks.first[0], 'https://preserved.example/callback');
  assert.deepEqual(callbacks.first, callbacks.second);
});

test('provisioning reconciles the existing managed federation app and verifies readback', () => {
  const source = readFileSync(new URL('../infra/configure-identity.ps1', import.meta.url), 'utf8');
  assert.match(source, /Merge-BloomstepFederationCallbacks/);
  assert.match(source, /Graph "applications\/\$\(\$microsoft\.id\)" 'PATCH'/);
  assert.match(source, /Federation callback readback mismatch/);
});
