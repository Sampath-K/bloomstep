# Dev Box: install, observe, uninstall

Run `.\Run-InstallerTrial.ps1` from built-in 64-bit Windows PowerShell as a true
non-admin standard user on the dedicated, owner-authorized Dev Box. No snapshot,
host Hyper-V, GitHub auth, runner, network, Inno, Git, Node or PowerShell 7 is
required. Do not overlap the old bootstrap/UAC helper or another trial.

The bundle contains the unsigned, unpublished universal CI candidate from source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, Actions run `38994109408`, artifact
`12086798368`. It verifies the candidate, source inventory and native payload
manifests before execution. Verify the separately supplied outer ZIP digest too.
Existing portable-tool caches in the earlier sibling `BloomstepVM` folder are
checked read-only; an incomplete/modified cache stops the trial, never overwrites
it. Inno is not needed for an already-built installer.

## One entry point

The script checks standard-user/interactive desktop, Defender protection,
unresolved threats, clean product state and other product registrations. It
refuses to adopt, uninstall or overwrite preexisting/unrelated Bloomstep state.
It requires explicit `RUN UNSIGNED CANDIDATE` confirmation before starting the
visible installer. Drive the wizard normally, observe the app and answer the
in-script observation prompts. Windows warnings/quarantine are blockers: do not
bypass them.

After verifying installed files and registration, the script binds a local
ownership record to this installing user, exact default install path, candidate
hash and generated uninstaller EXE/DAT hashes. It then asks you to close the app
normally (including its tray menu) and explicitly type `UNINSTALL OWNED TRIAL`.
This removes **only the owned program, its shortcuts/startup integration and
protocol** using the verified native uninstaller. Application databases/user
files are preserved. The native uninstaller may remove its own optional
measurement receipt. No broad deletion, force kill or silent uninstaller is used.

Uninstall waits at most 120 seconds, then checks for up to 15 seconds that its
EXE/DAT, app executable, uninstall registration, protocol, shortcuts/startup and
app processes are gone. Any nonzero exit (including restart-required), timeout,
changed hashes, unexpected registration, reparse path or protection failure
withholds cleanup success. A timed-out uninstaller is **not killed or retried**.
Finish/cancel its window normally and return the blocker for review.

`.\Run-InstallerTrial.ps1 -Resume` is the same entry point: before install it
rechecks all guards/consent; after install it can only perform verified owned
cleanup, never reinstall. If uninstall started but its exit code was lost, stop
for review; do not invent a successful result. If partial installation or
changed state cannot be attributed safely, automated cleanup is blocked.

## Limits and evidence

This is **supplemental owner testing**, NOT clean-VM/protected CI proof.
Uninstall is not a snapshot rollback and cannot reverse arbitrary machine or
app/server/account changes. It preserves app-created user data, unknown residual
files and any leftover installation directory. Named residual-data locations
are reported, not deleted; their absence is not proof that no other data exists.
Do not use real/customer data in this trial.

Return only `state\trial-receipt.json`, which separates owner observations from
verified cleanup and explicitly keeps protected gates `UNVERIFIED`. The local
`installation-owner.json` contains a path/SID; do not upload the whole state
folder. `Baseline` from the old bootstrap is never read as recovery evidence.
No runner registration, policy/security change, auto reboot, machine restore,
provisioning, merge, release or site promotion occurs.

Contract/parser tests run on Linux; actual Windows PowerShell 5.1, Defender,
Dev Box, native installer/uninstaller and desktop behavior require owner VM
evidence. Native x64 cannot satisfy protected native ARM64 evidence.
