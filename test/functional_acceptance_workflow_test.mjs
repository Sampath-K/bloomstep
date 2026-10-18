import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const wf = readFileSync(new URL('../.github/workflows/functional-acceptance.yml', import.meta.url), 'utf8');

test('functional acceptance runs only on demand against an exact artifact on a fresh hosted Windows VM', () => {
  assert.match(wf, /^on:\n  workflow_dispatch:/m);
  assert.doesNotMatch(wf, /^\s+(push|pull_request|schedule):/m);
  for (const input of ['candidate', 'run_id', 'artifact_id', 'installer_sha256', 'mode']) assert.match(wf, new RegExp(`\\n      ${input}:`));
  assert.match(wf, /runs-on: windows-latest/);
  assert.match(wf, /permissions:\n  contents: read\n  actions: read/);
  assert.doesNotMatch(wf, /secrets\.GITHUB_TOKEN.*write|contents: write|environment: public-launch/);
});

test('installer identity is proven before execution and never relabelled', () => {
  assert.match(wf, /actions\/artifacts\/\$\{\{ inputs\.artifact_id \}\}/);
  assert.match(wf, /workflow_run\.id/);
  assert.match(wf, /workflow_run\.head_sha/);
  assert.match(wf, /Get-FileHash .* -Algorithm SHA256/);
  assert.match(wf, /installer SHA-256 mismatch/);
  assert.match(wf, /\/VERYSILENT \/SUPPRESSMSGBOXES \/NORESTART/);
});

test('harness owns results; a missing harness or failed install is recorded as FAIL, never PASS', () => {
  assert.match(wf, /tool\/functional\/run_installed_acceptance\.ps1/);
  assert.match(wf, /harness-missing/);
  assert.doesNotMatch(wf, /result\s*=\s*'PASS'|"result":\s*"PASS"/);
  assert.match(wf, /if: always\(\)/);
  assert.match(wf, /upload-artifact@v4/);
  assert.match(wf, /budlark-functional-\$\{\{ inputs\.mode \}\}-\$\{\{ inputs\.candidate \}\}/);
});
