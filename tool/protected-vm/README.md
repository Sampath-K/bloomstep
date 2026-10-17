# One entry point: disposable protected VM preparation

Extract the supplied pinned ZIP in the disposable VM. Open ordinary **Windows
PowerShell as a true standard user**, in the extracted `bloomstep-vm-bootstrap`
directory. No installed Git, Node or PowerShell 7 is needed to start.

```powershell
.\Bootstrap.ps1
# After dependency setup / a manually approved restart, use the SAME entry point:
.\Bootstrap.ps1 -Resume
```

Prompts inside the script handle approvals. Do not bypass execution policy if
Windows refuses the script; report that block. Do not run as administrator.
The first prompt also asks for corporate DevBox/IT approval where applicable;
this script cannot grant that approval or provision a corporate environment.

The ZIP contains all bootstrap scripts and the existing protected preflight and
compile-only Inno harness, hash-bound by `package-manifest.json` to one source
commit. Verify the independently supplied ZIP SHA256 before extracting/running.
Internal file hashes detect accidental modification; they do not authenticate a
replaced ZIP/manifest, so the separately supplied outer digest is essential.

## What the single invocation does

1. Checks package inventory, true standard-user status, native x64/ARM64 Windows,
   actual Hyper-V identity, unlocked interactive input desktop and active Defender
   (existing `setup_defender_test_vm.ps1 -Mode Check`).
2. Requires a clean guest with no Bloomstep state. Prompts for a host checkpoint
   name before setup. **The checkpoint is an operator attestation**, not a claim
   the script created/verified it. A guest cannot safely create its own Hyper-V
   host checkpoint; that host boundary cannot be automated from inside this VM.
3. Fetches pinned official portable PowerShell 7.6.7, MinGit 2.56.0.2 and Node
   22.23.3 for the native architecture. Checks pinned SHA256 before extraction
   or execution and verifies actual versions. Tools stay under `state/tools`;
   no global PATH or policy is changed. Each subsequent invocation verifies
   cached archives and extracted file contents, reuses matching tools and
   resumes partial downloads/extraction safely. Modified files stop preparation.
4. Detects existing Inno. If absent, offers a separate UAC administrator child
   **only** for official pinned Inno 6.7.1. The child checks its checksum,
   Authenticode signature and protection; setup remains visible. No runner,
   app or installer test runs elevated. Close the child, restart manually if
   requested, then rerun the same entry point as the original standard user.
   No autologon, automatic restart, service or scheduled task is created.
5. Checks the required existing Windows .NET Framework compiler, probes Inno's
   authoritative engine banner with installer output disabled, and repeats
   Defender preflight. Writes sanitized machine-readable receipts.
6. Stops with **`TrustBlocked`**, not success, because the current PUBLIC repository
   protected workflows do not enforce a reviewed workflow/ref runner restriction.
   No runner package/token is requested and no registration/listener exists.

Downloads have a 180-second per-attempt timeout, at most three attempts with
2/4-second backoff, only for transient transport faults or HTTP
408/429/500/502/503/504. Hash/signature, TLS trust, authorization, unsupported host,
policy, Defender and permission failures are never retried or bypassed.
No broad cleanup occurs; only a known incomplete download file is removed.

## Return the receipt, not secrets

`state/bootstrap-receipt.json` is the sanitized summary with stage, source,
native architecture, dependency versions and explicit next action.
`state/preflight*/vm-security-receipt.json` has existing Defender/desktop details;
review it for private details before sharing. The host checkpoint name remains
only in local `state/checkpoint.json`. Do not share the entire state directory.
Local errors are shown but not copied verbatim into the summary receipt.

Exit codes: **1** failed/declined; **2** dependency setup completed or restart/resume
needed (not ready); **3** prerequisites prepared but **trust blocked**. There is
intentionally no "everything complete" or registration-success path.
Resume rechecks all guards and never treats earlier prompts or a receipt as
authorization to run repository code.

## Why runner setup cannot finish today

Current `.github/workflows/ci.yml` has NO protected-job `environment:` approval.
Labels `self-hosted,defender-interactive` and native `x64`/`arm64` select machines,
not approved source SHAs. `--ephemeral` means one job, not one trusted job.
A clean queue or a user-entered yes is not an enforceable restriction. The lifecycle
job does not independently exclude fork PRs. A malicious matching workflow can
execute before installer preflight, so watching the job after dispatch is too late.

Registration must remain blocked until independently verifiable runner-access
restrictions exclude ALL unreviewed workflow/ref execution. This bundle deliberately
has no generic registration path and does not change repository protections to
manufacture one. Return the receipt for a reviewed restriction-specific follow-up.
Do not fall back to the older manual registration snippets.

Required coverage is seven jobs per full reviewed run: one inert launch job,
plus lifecycle/native proof/genuine checked-unchecked launch on BOTH native x64
and ARM64. Each needs a clean checkpoint and fresh ephemeral registration AFTER
trust is resolved. x64 emulation cannot replace native ARM64. Preflight/manual
results do not satisfy these gates. No merge, tag, release, signing/updater
activation, site promotion, VM provisioning or installer execution is authorized.

## Evidence limitations

The packaged scripts and tests are syntax/contract checked on Linux using the
official PowerShell parser. Actual Windows PowerShell 5.1 execution, UAC/alternate
administrator credentials, restart/resume, Hyper-V, standard-user Defender scans,
native ARM64 tool compatibility and desktop/input behavior require VM evidence.
Report failures with receipts; no protected gate is assumed green.
