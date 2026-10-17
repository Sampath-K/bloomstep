# Protected Windows runner: owner preparation and explicit execution

**Single-entry delivery supersedes the manual setup steps below.** Use the
[packaged bootstrap instructions](../tool/protected-vm/README.md): unzip once,
run `.\Bootstrap.ps1` as the standard user, and let its internal prompts handle
safe prerequisite preparation and resume. The older registration examples below
are reference only, not an alternative way around the bootstrap's `TrustBlocked`
result. Registration is still unauthorized until the enforceable trust restriction
described here is independently verified.

This is preparation, not permission to register a runner, dispatch a job, or run
an installer. Nothing here provisions a VM, installs a service, enables autologon,
changes execution policy, disables protection, or grants persistent access.
Do not run these instructions on your normal Windows host.

## 1. Understand the actual gates and public-repository risk

The reviewed release candidate is source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, run
<https://github.com/Sampath-K/bloomstep/actions/runs/38994109408>.
Preparation files added later do not change that candidate's identity or attest
their own new CI head. Never substitute a different SHA without reviewing it.

The repository is public. In `.github/workflows/ci.yml`:

| Required job | Runner labels | Timeout |
| --- | --- | --- |
| `installer-launch-evidence` (inert launch branches) | `self-hosted`, `defender-interactive` | 20 minutes |
| `protected-installer-lifecycle` | same plus `x64` or `arm64` | 20 minutes |
| `universal-native-proof` | same plus `x64` or `arm64` | 15 minutes |
| `universal-app-launch-evidence` (genuine app) | same plus `x64` or `arm64` | 15 minutes |

Each architecture-specific family needs BOTH native OS architectures. One x64
Hyper-V guest cannot satisfy ARM64; changing a label or emulating an ARM64 label
is not evidence. The ARM64 native proof also tests x64-process emulation on ARM64.
There are seven protected jobs per complete run: one inert and three per architecture.
Use a restored clean guest and fresh ephemeral registration for EACH job.

**No protected job currently declares a GitHub `environment:` approval gate.**
The release relies on runner availability and harness checks, not an automatic
reviewer approval prompt. Jobs check out the PR head SHA or event SHA with
`persist-credentials: false`. They have `contents: read`, and artifact consumers
also have `actions: read`. Same-repository PRs, pushes and eligible dispatches can
request these labels; the lifecycle job does not independently exclude fork PRs.
Other workflows or future changes can also request a matching runner.

**Labels and `--ephemeral` do NOT pin a job to a SHA or run.** Ephemeral means one
job, not one approved job. A queued old/untrusted job could take it first.
Installer preflight runs AFTER checkout, so it is not protection from malicious
workflow code. A last-second queue check is not an atomic security boundary.

**Registration is BLOCKED unless the owner can enforce that ONLY the reviewed
workflow/ref may use the runner**, for example through an existing supported
runner-access restriction verified in repository/organization Settings. Do not
assume a repository-scoped runner has per-SHA scheduling restrictions. If no
enforceable restriction exists, STOP and report that limitation; a generic
repository runner plus a clean queue cannot guarantee it will not pick up
arbitrary code. Do not change workflows, runner labels, repository visibility,
or protections as a workaround. No runner should exist while this is unresolved.

Before any later authorized registration, review ALL queued/in-progress runs,
not only the candidate, cancel stale/unreviewed eligible work only with owner
authorization, and prevent new unreviewed eligible work through the enforced
access restriction. Check the workflow file and actual checkout SHA as well as
the run's displayed head; PR jobs may have a synthetic merge SHA for hosted jobs.

## 2. Prepare the guest manually

Use an official licensed Windows 11 Hyper-V guest. The harness explicitly checks
manufacturer `Microsoft Corporation`, model `Virtual Machine`; another hypervisor
is not supported by this harness. No provisioning is performed by the script.

Before taking the clean checkpoint, the VM administrator separately installs
Git, supported Node.js 22+, PowerShell 7 and Inno Setup **6.7.1** from their official
distributions. The workflow expects Inno at
`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`, and requires the existing compiler
`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.
The protected jobs consume hosted compiled artifacts; Flutter/Visual Studio are
not required for those jobs. Download the official GitHub Actions Windows runner
for the native guest architecture using Settings > Actions > Runners >
New self-hosted runner. Verify its displayed checksum before extraction.
Do not install or configure the runner yet.

Create a dedicated **standard user**, not an administrator with a filtered UAC
token. Remove no security controls. Complete updates and verify Defender antivirus,
real-time, behavior monitoring, service and Normal mode are already active.
No exclusions, quarantine restoration, warning bypass, autologon or policy change.
If standard-user Defender cmdlets/scans are denied, STOP; do not elevate the runner.

No customer data, provider credentials, personal/work tokens, shared host drives,
clipboard/drive redirection or existing Bloomstep state. Disable VM integration
sharing manually. Take a clean checkpoint. Sign in as the standard user and keep
the local VM console unlocked. Never use a runner service or a background session.

## 3. Download/review the preparation script and check readiness

Obtain a clean checkout of the committed preparation source linked by the
coordinator. Review `tool/prepare_protected_runner.ps1` and the existing
`tool/setup_defender_test_vm.ps1` before executing either.
Use the full immutable preparation commit SHA supplied with this guide, not a
moving branch. Preparation script execution is a separate user decision.

In ordinary, non-administrator PowerShell 7 inside the guest:

```powershell
# Replace this with the independently supplied full preparation commit SHA.
$ReviewedPreparationSha = '<40-character preparation commit SHA>'
git clone https://github.com/Sampath-K/bloomstep.git Bloomstep-reviewed
if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
Set-Location Bloomstep-reviewed
git checkout --detach $ReviewedPreparationSha
if ($LASTEXITCODE -ne 0) { throw 'Reviewed source checkout failed' }
$env:BLOOMSTEP_DISPOSABLE_VM = 'true'
.\tool\prepare_protected_runner.ps1 -ExpectedArch x64 `
  -ExpectedSource $ReviewedPreparationSha
```

Use `-ExpectedArch arm64` only on native ARM64 Windows. The script asks you to type
`CHECK DISPOSABLE VM`. It checks source/clean checkout, dependencies, architecture,
existing product state, standard-user interactive/input desktop and Defender.
It writes receipts in `$env:TEMP\bloomstep-runner-readiness`.
It also uses the repository's existing compile-only Inno toolchain probe (output
disabled) to verify the engine banner, not unreliable executable version metadata.
It neither downloads nor installs anything, registers a runner, nor executes
an installer. No bypass flag is provided. If script execution is blocked by
policy, STOP and report it; do not run `Set-ExecutionPolicy` or `Unblock-File`.

## 4. Separate explicit registration (ONLY after the trust blocker is resolved)

Review section 1 again. The following commands are NOT safe to run merely
because readiness passed. First obtain owner confirmation for the exact run,
workflow source, checkout SHA, architecture, ONE expected job and enforced access
restriction. If any is unknown, do not register. Existing queued run 38994109408
is a historical candidate, not automatic authorization to consume it.

Inside the verified official runner directory, as the standard user, use a
fresh **repository registration token**, created by the owner through repository
Settings, not a PAT/OAuth token and not a credential stored on the VM. Registration
tokens are short-lived (normally one hour). Never send it to the agent, include
it in a file, command literal, terminal transcript, screenshot or shell history.
Token retrieval can happen on the owner's trusted machine:

```powershell
# Owner only, trusted machine: response contains a secret; do not share/log it.
gh api --method POST repos/Sampath-K/bloomstep/actions/runners/registration-token
```

Alternatively use the repository Settings UI. Enter only that registration token
at the masked prompt below. The Actions runner supports `ACTIONS_RUNNER_INPUT_TOKEN`;
the command line and shell history contain no token literal.

```powershell
if ((Read-Host 'Type REGISTER ONE REVIEWED JOB after enforcing access restrictions') `
    -cne 'REGISTER ONE REVIEWED JOB') { throw 'Registration not authorized' }
$secret = Read-Host 'Fresh repository runner registration token' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
  $env:ACTIONS_RUNNER_INPUT_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  & .\config.cmd --unattended --url https://github.com/Sampath-K/bloomstep `
    --labels defender-interactive --ephemeral `
    --name "bloomstep-disposable-$([Guid]::NewGuid().ToString('N').Substring(0,8))" `
    --work _work
  if ($LASTEXITCODE -ne 0) { throw 'Runner registration failed' }
} finally {
  Remove-Item Env:\ACTIONS_RUNNER_INPUT_TOKEN -ErrorAction SilentlyContinue
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  $secret.Dispose()
}
```

Do NOT install a service. Registration writes runner credentials to that
disposable runner directory; it is not secret-free just because the token is
short-lived. Do not copy that directory off the guest. No token scopes or broader
GitHub access should be granted for the harness.

## 5. Separate explicit execution and evidence

After a final independently verified trust/queue check and explicit owner approval:

```powershell
if ((Read-Host 'Type RUN ONE REVIEWED JOB to start the interactive listener') `
    -cne 'RUN ONE REVIEWED JOB') { throw 'Execution not authorized' }
$env:BLOOMSTEP_DISPOSABLE_VM = 'true'
& .\run.cmd
if ($LASTEXITCODE -ne 0) { throw 'Runner exited with failure; preserve evidence' }
```

The existing job sets its own fixture/proof variables. Do not fake `GITHUB_ACTIONS`,
`RUNNER_TEMP` or proof results locally. If the assigned run/job/head is not the
reviewed one, stop the listener, disconnect the guest and report possible exposure;
stopping AFTER assignment cannot guarantee no code executed. Keep the console
unlocked. Any Defender detection, policy block or changed protection means STOP,
preserve sanitized receipts, do not restore quarantine or rerun to hide failure.

Return these sanitized facts to the coordinator (never tokens or runner credentials):

- BEFORE registration: native OS architecture/version; full reviewed source SHA;
  `runner-readiness.json` and `vm-security-receipt.json`; checkpoint identifier;
  standard-user/non-admin and input-desktop status; dependency versions; Defender
  engine/signature/product versions and detection status; exact enforced trust
  restriction, intended run ID/job URL/head SHA, and request for explicit approval.
- AFTER each separately approved job: actual Actions run/job URL, checkout source,
  actual runner architecture, job conclusion and uploaded receipt/artifact URLs.
  Include installer SHA and unchanged-protection/detection receipts. Preserve
  failure evidence too. An inert proof is not genuine app acceptance.
- Genuine acceptance needs checked, unchecked and silent outcomes, actual app
  owner SID/non-elevated token, visible surviving app and native architecture;
  x64 and ARM64 receipts remain separate. Ordinary provider sign-in, Narrator,
  high contrast, mixed DPI and owner journey remain separate acceptance work.

The gates are unchanged: readiness/manual feedback does not turn queued jobs
green. No merge, tag, publication or site promotion is authorized here.

## 6. Stop and teardown

Each registration may consume only one job. Verify the ephemeral entry disappears
from repository Settings. If it never consumed a job, the owner removes that
specific runner registration manually. Close the listener; do not leave access
attached. Export only sanitized evidence, shut down the VM and restore the clean
checkpoint before EACH next job with a NEW registration. Do not reuse installer
or runner state. Remove the disposable guest and its specific disks manually
when finished; never delete broad host directories.

## Validation boundary

This script must pass PowerShell parsing and its repository contract test before
handoff. Linux checks cannot establish Hyper-V identity, Defender permissions,
Windows compiler availability, input-desktop access, actual runner assignment,
native x64/ARM64 routing or installer behavior. Those remain operator/Windows CI
evidence, never assumed successes.
