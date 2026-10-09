# Disposable protected Windows installer validation

The earlier zero-click candidate is **withdrawn** after Defender behavior
quarantine. Do not restore or execute it, including inside this VM. No false
positive or cause is established. The standard user-driven redesign is a
product/implementation change, not a claim that changing packaging avoids
detection. A clean static scan alone does not prove clean behavior.

## Owner steps: Hyper-V Windows 11 VM

Hyper-V is preferred over Sandbox because it supports a persistent standard user,
checkpoints and an interactive ephemeral runner. This runbook does not provision
anything automatically. Use an existing Hyper-V-capable Windows host and an
official Windows 11 development VM/image from Microsoft, with the applicable
license. ARM64 coverage requires a separate supported ARM64 host; an x64 VM is
not ARM64 evidence.

1. Import/create a dedicated Windows 11 VM in Hyper-V Manager. Disable clipboard,
   drive sharing and Enhanced Session resource redirection. Do not attach customer
   data, work credentials, host directories, secrets or existing Bloomstep state.
   Use a dedicated disposable GitHub identity if runner registration is needed.
2. Complete ordinary Windows setup/updates. Verify Windows Security shows active
   Defender antivirus, real-time and behavior protection. Do not disable tamper
   protection, add exclusions, or override detections. If protection is unavailable,
   stop; this environment is unsuitable.
3. As the VM administrator, install Git, Node, PowerShell 7 and Inno Setup 6.7.1
   from their supported distributions for fixture compilation. Create a **standard user**
   `BloomstepTest` through Settings > Accounts > Other users. Do not grant it
   Administrators membership. No script stores passwords.
4. Shut down the clean VM and make a checkpoint `Bloomstep-clean-protected`.
   Start it and sign in locally as `BloomstepTest`. Keep the VM console open and
   unlocked. Do not run PowerShell as administrator or install a runner service.
5. In that VM only, clone the repo at the exact approved security-test source head.
   In the standard-user interactive PowerShell:

   ```powershell
   $env:BLOOMSTEP_DISPOSABLE_VM = 'true'
   .\tool\setup_defender_test_vm.ps1 -Mode Check
   ```

   The script checks Hyper-V identity, non-admin token, session/input desktop,
   `Get-MpComputerStatus` real-time/behavior/antivirus protection and prior detection
   status. It refuses installer execution if any check fails; it never configures
   Defender or provisions a VM.

## Optional ephemeral GitHub runner

Self-hosted runners on a public repository are unsafe for arbitrary PR code.
Never leave this runner attached unattended for untrusted jobs. Only the owner
should register it for an reviewed exact workflow/head; registration alone is
not authorization to run arbitrary repository code. Each ephemeral registration
runs one job. The architecture jobs additionally check the actual OS
architecture; a single x64 VM does not satisfy ARM64.

1. In the repository Settings > Actions > Runners > New self-hosted runner, choose
   Windows and the VM's architecture. Follow GitHub's current runner download and
   checksum commands **inside the VM**. Retrieve a fresh short-lived registration
   token as owner. Do not commit/log it or send it to the agent.
   **Before registration**, cancel all stale/unreviewed queued runs requesting
   this label. Inspect the exact queued job's workflow, source head and checkout
   ref; only the newly reviewed standard-flow head may remain eligible. GitHub
   labels do not pin a runner to a head or prevent older queued jobs being taken.
2. Configure as the standard user, not a service, using the UI-supplied token:

   ```powershell
   .\config.cmd --url https://github.com/Sampath-K/bloomstep `
     --token '<short-lived owner registration token>' `
     --labels defender-interactive --ephemeral --name 'bloomstep-disposable-review'
   $env:BLOOMSTEP_DISPOSABLE_VM = 'true'
   .\run.cmd
   ```

   Replace the placeholder only locally. Clear terminal history holding the token
   after registration. Jobs use `runs-on: [self-hosted, defender-interactive]` and
   the same preflight before executing any fixture or installer. Without this
   runner jobs remain queued: absence is not a pass or a security acceptance.
   Genuine jobs additionally use GitHub's automatic native `x64`/`ARM64` labels
   to avoid dispatching the ARM64 job to an x64 VM. Inno and required tools must
   already exist; jobs must not elevate to install them. If Defender scan cmdlets
   deny standard-user access, preserve the failed preflight and stop; do not
   elevate the runner or weaken protection to work around it.
3. Trigger only the reviewed exact CI source head via GitHub Actions. Collect
   preflight, Defender versions/detections, installer/app tokens, exact hashes,
   setup logs and checked/unchecked launch receipts. No provider credentials are
   needed for this synthetic test. MSA/Google acceptance remains separate.
   Revert the clean VM checkpoint and register a fresh ephemeral runner for
   **each** additional job; do not reuse a job's modified guest state. Stop if the
   expected job/head does not match. Several queued jobs require several isolated
   registrations (and a native VM of each required architecture), not one lasting
   runner session.

## Manual new-candidate trial, inside VM only

Download only the **new standard-flow** unpublished CI artifact and independently
verify its supplied SHA-256. Never download the withdrawn hash
`b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5`.
The owner uses the exact new hash/path, not the placeholder:

```powershell
$env:BLOOMSTEP_DISPOSABLE_VM = 'true'
.\tool\setup_defender_test_vm.ps1 -Mode RunInstaller `
  -Installer 'C:\VM-Test\new-standard-setup.exe' `
  -ExpectedSha256 '<64-character SHA-256 from exact CI receipt>' `
  -EvidenceDir 'C:\Users\BloomstepTest\AppData\Local\Temp\bloomstep-security-evidence'
```

The script scans with already-enabled protection, rechecks the hash, then starts
the visible installer. The **owner** selects Next on Welcome/destination, Install
on Ready, and optionally checks **Launch Bloomstep** on Finish (default unchecked).
No automatic page clicks, dwell or forced launch. Stop on any malware, managed
policy or protection warning; do not bypass it. A launcher exit alone is not an
app/token/security/full-journey verdict. Capture the visible application, process
token and before/after Defender events separately; trial habits are synthetic.
Use a restored clean checkpoint for checked vs unchecked independent trials.

## Evidence and teardown

Copy only sanitized test receipts/logs/screenshots out of the guest. Preserve
Defender event 1116/1117 identifiers and scan/signature/engine versions even on
failure. Do not upload source/binaries to external analysis services without
explicit permission. No production sign-in tokens, VM account credentials or
private habit data in artifacts.

Stop the runner with Ctrl+C after its job; verify the ephemeral entry was removed
in repository Settings (remove it manually if registration was never consumed).
Shut down the VM and restore `Bloomstep-clean-protected` before any new test.
Remove the exact test VM and its dedicated disks via Hyper-V Manager when finished;
never delete host/root directories. Revoke unused registration tokens. Do not
restore quarantine as part of teardown. An unresolved Defender detection keeps
distribution stopped, regardless of any earlier CI success.
