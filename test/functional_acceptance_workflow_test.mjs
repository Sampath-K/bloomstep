import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const wf = readFileSync(new URL('../.github/workflows/functional-acceptance.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const runBlocks = [...wf.matchAll(/run: \|\n((?:          .*\n|\n)+)/g)].map((m) => m[1]).join('\n');

test('functional acceptance runs only on demand against an exact artifact on a fresh hosted Windows VM', () => {
  assert.match(wf, /^on:\n(?:  #.*\n)*  workflow_call:/m);
  assert.match(wf, /^  workflow_dispatch:/m);
  assert.doesNotMatch(wf, /^\s+(push|pull_request|schedule):/m);
  for (const input of ['candidate', 'run_id', 'artifact_id', 'installer_sha256', 'mode']) assert.match(wf, new RegExp(`\\n      ${input}:`));
  assert.match(wf, /runs-on: .*'windows-latest'/);
  assert.match(wf, /permissions:\n  contents: read\n  actions: read/);
  assert.doesNotMatch(wf, /contents: write|environment: public-launch/);
});

test('inputs never reach shell scripts by expression interpolation', () => {
  assert.ok(runBlocks.length > 0);
  assert.doesNotMatch(runBlocks, /\$\{\{/);
  assert.match(wf, /IN_CANDIDATE: \$\{\{ inputs\.candidate \}\}/);
  assert.match(runBlocks, /-cnotmatch '\^\[0-9a-f\]\{40\}\$'/);
});

test('installer identity is proven before execution and gh failures are fatal', () => {
  assert.match(runBlocks, /actions\/artifacts\/\$env:IN_ARTIFACT_ID/);
  assert.match(runBlocks, /workflow_run\.id/);
  assert.match(runBlocks, /workflow_run\.head_sha/);
  assert.equal((runBlocks.match(/if \(\$LASTEXITCODE -ne 0\) \{ throw/g) || []).length, 2);
  assert.match(runBlocks, /Get-FileHash .* -Algorithm SHA256/);
  assert.match(runBlocks, /installer SHA-256 mismatch/);
});

test('harness owns install and results; cleanup touches only the owned install dir', () => {
  assert.match(runBlocks, /tool\/verify_installed_functional\.ps1/);
  assert.match(runBlocks, /-Installer \$env:INSTALLER -ExpectedSha256 \$env:IN_SHA256 -InstallDir \$env:INSTALL_DIR/);
  assert.match(runBlocks, /RUNNER_TEMP "budlark-install-\$env:GITHUB_RUN_ID"/);
  assert.match(runBlocks, /harness-missing/);
  assert.doesNotMatch(runBlocks, /-Recurse -Filter 'unins|ProgramFiles|LOCALAPPDATA\\\\Programs/);
  assert.match(runBlocks, /Join-Path \$env:INSTALL_DIR 'unins000\.exe'/);
  assert.doesNotMatch(wf, /result\s*=\s*'PASS'|"result":\s*"PASS"/);
  assert.match(wf, /if: always\(\)/);
  assert.match(wf, /upload-artifact@v4/);
});

test('ci.yml (registered on the default branch) dispatches functional acceptance exclusively', () => {
  const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  assert.match(ci, /functional_mode:\n        description: .*\n        type: choice\n        options: \[none, candidate, baseline\]\n        default: none/);
  const job = ci.match(/\n  functional-acceptance:\n((?:    .*\n)+)/)?.[1] ?? '';
  assert.match(job, /if: github\.event_name == 'workflow_dispatch' && inputs\.functional_mode != 'none'/);
  assert.match(job, /uses: \.\/\.github\/workflows\/functional-acceptance\.yml/);
  assert.match(job, /mode: \$\{\{ inputs\.functional_mode \}\}/);
  assert.doesNotMatch(job, /secrets: inherit|contents: write/);
  for (const name of ['api', 'funnel-composed-acceptance', 'test-and-build-windows', 'edge-download-observation']) {
    const ifLine = ci.match(new RegExp('\\n  ' + name + ':\\n(?:    (?!if:).*\\n)*    if: (.*)\\n'))?.[1] ?? '';
    assert.match(ifLine, /inputs\.functional_mode == 'none' && !inputs\.export_installer_art/, name);
  }
});

test('ci.yml exposes an exclusive opt-in real PlantArt export that uploads unmodified outputs and commits nothing', () => {
  const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  const job = ci.match(/\n  installer-art-export:\n((?:    .*\n)+)/)?.[1] ?? '';
  assert.match(job, /if: github\.event_name == 'workflow_dispatch' && inputs\.export_installer_art && inputs\.functional_mode == 'none'/);
  assert.match(job, /BLOOMSTEP_EXPORT_INSTALLER_ART: 'true'/);
  assert.match(job, /flutter test tool\/installer_art_export_test\.dart/);
  assert.match(job, /node tool\/generate_installer_art\.mjs --check/);
  for (const f of ['welcome-steps.bmp', 'welcome-garden.bmp', 'education-art-provenance.json']) assert.ok(job.includes('packaging/assets/' + f), f);
  assert.doesNotMatch(job, /contents: write|git (commit|push)|secrets\./);
});
test('functional acceptance can target an owner-registered live-Defender runner only by explicit choice', () => {
  const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  assert.match(wf, /runner: \{ type: string, required: false, default: hosted \}/);
  assert.match(wf, /options: \[hosted, self-hosted-defender\]/);
  assert.match(wf, /inputs\.runner == 'self-hosted-defender' && fromJSON\('\["self-hosted","windows","x64","budlark-defender"\]'\) \|\| 'windows-latest'/);
  assert.doesNotMatch(wf, /^\s*(pull_request|pull_request_target|push):/m);
  assert.match(ci, /functional_runner:[\s\S]*?default: hosted/);
  assert.match(ci, /runner: \$\{\{ inputs\.functional_runner \}\}/);
});
