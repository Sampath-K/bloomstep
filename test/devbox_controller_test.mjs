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
  assert.doesNotMatch(verifier, /Start-Process/);
  assert.match(verifier, /Authorization="Bearer \$env:GITHUB_TOKEN"/);
  assert.match(verifier, /-MaximumRedirection 0/);
  assert.match(verifier, /Invoke-WebRequest -Uri \$candidate\.packageUrl -OutFile \$archive -TimeoutSec 180/);
  assert.doesNotMatch(verifier, /Invoke-WebRequest -Uri \$candidate\.packageUrl[^\n]*-Headers/);
});

test('candidate verifier parses before controller publication', () => {
  const file = fileURLToPath(new URL('Verify-Candidate.ps1', base));
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command',
    '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)|Out-Null;if($e.Count){$e|ForEach-Object{Write-Error $_};exit 1}'],
  { encoding:'utf8', env:{ ...process.env, SCRIPT:file } });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});

test('connection setup and autonomous harness are gated, non-admin, local-auth and never fake protected proof', () => {
  const setup = read('Connect-DevBox.ps1');
  const harness = read('Invoke-ControllerTrial.ps1');
  for (const source of [setup,harness]) {
    assert.doesNotMatch(source, /Set-ExecutionPolicy|Set-MpPreference|Add-MpPreference|Unblock-File|New-Service|schtasks|Stop-Process|BLOOMSTEP_DISPOSABLE_VM|--runasservice|--windowslogonaccount/);
  }
  for (const required of ['Read-Host', '-AsSecureString', 'ZeroFreeBSTR', 'PERSISTENT PRIVATE CONTROLLER',
    'actions/permissions', 'collaborators', 'runnerRegistrationStarted', 'config.cmd', 'run.cmd']) assert.ok(setup.includes(required), required);
  assert.doesNotMatch(harness, /Read-Host|Confirm-Operator/);
  for (const required of ['Get-DefenderSnapshot', 'Assert-InteractiveStandardUser', 'Assert-OwnedUninstaller',
    'Assert-UninstallResult', 'CloseMainWindow', 'AddSeconds(120)', 'CONTROLLER_TOKEN', 'UNVERIFIED',
    'approved-candidates.json', 'Invoke-StandardWizardStep']) assert.ok(harness.includes(required), required);
  for (const name of ['Connect-DevBox.ps1','Invoke-ControllerTrial.ps1']) {
    const file = fileURLToPath(new URL(name, base));
    const result = spawnSync('pwsh', ['-NoProfile','-NonInteractive','-Command',
      '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)|Out-Null;if($e.Count){$e|ForEach-Object{Write-Error $_};exit 1}'],
    { encoding:'utf8', env:{...process.env,SCRIPT:file} });
    assert.equal(result.status,0,result.stderr||result.error?.message);
  }
});

test('metadata token is sent only to exact GitHub build API without redirects or raw download headers', () => {
  const file = fileURLToPath(new URL('Verify-Candidate.ps1', base));
  const result = spawnSync('pwsh', ['-NoProfile','-NonInteractive','-Command', `
    $ErrorActionPreference='Stop'
    $t=$null;$e=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)
    $node=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GitHubBuildMetadata'},$true)
    . ([scriptblock]::Create($node.Extent.Text))
    $env:GITHUB_TOKEN='test-only-not-a-credential'
    $script:calls=0
    function Invoke-WebRequest {
      param($Headers,$Uri,$TimeoutSec,$MaximumRedirection)
      $script:calls++
      if($Uri -cne 'https://api.github.com/repos/Sampath-K/bloomstep/actions/runs/123'){throw 'Wrong API host/path'}
      if($Headers.Authorization -cne 'Bearer test-only-not-a-credential' -or $MaximumRedirection -ne 0){throw 'Missing bounded authenticated API contract'}
      @{Content='{"head_sha":"reviewed"}'}
    }
    $run=Get-GitHubBuildMetadata 'actions/runs/123'
    if($run.head_sha -cne 'reviewed' -or $script:calls -ne 1){throw 'Valid metadata request failed'}
    foreach($path in @('https://other.example','../contents/file','actions/runs/123/../../secrets','actions/runs/123?redirect=1')){
      $rejected=$false
      try{Get-GitHubBuildMetadata $path|Out-Null}catch{$rejected=$true}
      if(-not $rejected){throw 'Unallowlisted metadata request accepted'}
    }
    if($script:calls -ne 1){throw 'Unallowlisted path reached transport'}
    $env:GITHUB_TOKEN=$null
    $rejected=$false
    try{Get-GitHubBuildMetadata 'actions/runs/123'|Out-Null}catch{$rejected=$true}
    if(-not $rejected -or $script:calls -ne 1){throw 'Unauthenticated rate-limit fallback accepted'}
  `], {encoding:'utf8',env:{...process.env,SCRIPT:file}});
  assert.equal(result.status,0,result.stderr||result.error?.message);
});

test('metadata distinguishes permanent auth/resource/rate failures and bounds transient Retry-After', () => {
  const file = fileURLToPath(new URL('Verify-Candidate.ps1', base));
  const result = spawnSync('pwsh', ['-NoProfile','-NonInteractive','-Command', `
    $ErrorActionPreference='Stop'
    $null=Get-Command Invoke-WebRequest
    $t=$null;$e=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)
    $node=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GitHubBuildMetadata'},$true)
    . ([scriptblock]::Create($node.Extent.Text))
    $env:GITHUB_TOKEN='test-only-not-a-credential'
    function Start-Sleep {param($Seconds) $script:waits+=@($Seconds)}
    function Invoke-WebRequest {
      param($Headers,$Uri,$TimeoutSec,$MaximumRedirection)
      $script:calls++
      if($Headers.Authorization -cne 'Bearer test-only-not-a-credential'){throw 'Retry lost authenticated routing'}
      if($script:calls -gt $script:failUntil){return @{Content='{"ok":true}'}}
      $response=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$script:status)
      if($script:retry -ge 0){$response.Headers.RetryAfter=[Net.Http.Headers.RetryConditionHeaderValue]::new([TimeSpan]::FromSeconds($script:retry))}
      if($script:exhausted){$null=$response.Headers.TryAddWithoutValidation('X-RateLimit-Remaining','0')}
      throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Controlled fixture',$response)
    }
    foreach($case in @(
      @{status=401;reason='token rejected';calls=1;retry=-1;exhausted=$false},
      @{status=403;reason='access or policy denied';calls=1;retry=-1;exhausted=$false},
      @{status=403;reason='rate limit exhausted';calls=1;retry=-1;exhausted=$true},
      @{status=404;reason='resource unavailable';calls=1;retry=-1;exhausted=$false},
      @{status=503;reason='retry budget exhausted';calls=3;retry=-1;exhausted=$false},
      @{status=429;reason='bounded wait';calls=1;retry=61;exhausted=$false}
    )){
      $script:calls=0;$script:waits=@();$script:status=$case.status
      $script:retry=$case.retry;$script:exhausted=$case.exhausted;$script:failUntil=99
      $message=''
      try{Get-GitHubBuildMetadata 'actions/runs/123'|Out-Null}catch{$message=$_.Exception.Message}
      if($message -notmatch $case.reason -or $script:calls -ne $case.calls){throw "Wrong failure contract: $message; calls=$script:calls"}
      if($case.status -eq 503 -and ($script:waits -join ',') -cne '2,4'){throw 'Retry budget/backoff differs'}
      if($case.calls -eq 1 -and $script:waits.Count){throw 'Permanent/unbounded case slept'}
    }
    $script:calls=0;$script:waits=@();$script:status=429
    $script:retry=1;$script:exhausted=$false;$script:failUntil=1
    $actual=Get-GitHubBuildMetadata 'actions/runs/123'
    if(-not $actual.ok -or $script:calls -ne 2 -or ($script:waits -join ',') -cne '1'){throw 'Bounded Retry-After recovery failed'}
  `], {encoding:'utf8',env:{...process.env,SCRIPT:file}});
  assert.equal(result.status,0,result.stderr||result.error?.message);
});

test('preflight failures and failed lock acquisition cannot erase prior cleanup or unresolved installation authority', () => {
  const file = fileURLToPath(new URL('Invoke-ControllerTrial.ps1', base));
  const result = spawnSync('pwsh', ['-NoProfile','-NonInteractive','-Command', `
    $ErrorActionPreference='Stop'
    $t=$null;$e=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$t,[ref]$e)
    $main=@($ast.EndBlock.Statements|Where-Object {$_ -is [System.Management.Automation.Language.TryStatementAst]})[-1]
    $final=[scriptblock]::Create(($main.Finally.Statements.Extent.Text -join [Environment]::NewLine))
    $output='sanitized-output';$receiptPath='persistent-authority'
    function Save-DevBoxTrialReceipt {param($Path,$Value) $script:saved+=@($Path)}
    foreach($case in @(
      @{mutated=$false;locked=$true;writes=0},
      @{mutated=$false;locked=$false;writes=0},
      @{mutated=$true;locked=$true;writes=1},
      @{mutated=$true;locked=$false;writes=0}
    )){
      $script:saved=@()
      $report=[ordered]@{productMutationStarted=$case.mutated}
      $lock=if($case.locked){[IO.MemoryStream]::new()}else{$null}
      . $final
      if(@($script:saved|Where-Object {$_ -ceq $receiptPath}).Count -ne $case.writes){throw 'Persistent authority overwritten by unauthoritative preflight/lock failure'}
      if($script:saved.Count -ne (1+$case.writes)){throw 'Missing sanitized failure artifact'}
    }
  `], {encoding:'utf8',env:{...process.env,SCRIPT:file}});
  assert.equal(result.status,0,result.stderr||result.error?.message);
});

test('owner guide gives exact app audit, local scoped token/revocation pages and only the workflow action pins', () => {
  const readme=read('README.md');
  for(const path of [
    '/settings/installations','/settings/apps/authorizations','/settings/applications',
    '/settings/personal-access-tokens/new',
    '/bloomstep-vm-controller/settings/access','/bloomstep-vm-controller/settings/actions/runners',
  ]) assert.ok(readme.includes(path),path);
  const bodies=[...readme.matchAll(/```json\n([\s\S]*?)\n```/g)].map(match=>JSON.parse(match[1]));
  assert.deepEqual(bodies[0],{enabled:true,allowed_actions:'selected'});
  const actions=bodies[1];
  assert.equal(actions.github_owned_allowed,false);
  assert.equal(actions.verified_allowed,false);
  const workflow=read('validate.yml');
  const pins=[...new Set([...workflow.matchAll(/uses: (actions\/[\w-]+@[a-f0-9]{40})/g)].map(match=>match[1]))];
  assert.deepEqual([...actions.patterns_allowed].sort(),pins.sort());
  assert.match(readme,/Revoking the setup token alone does \*\*not\*\* revoke the runner/);
});
