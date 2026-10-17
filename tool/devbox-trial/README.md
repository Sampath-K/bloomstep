# Bloomstep Dev Box installer trial

This ZIP contains one entry point, the exact retained CI universal installer,
its x64/ARM64 manifests, and a fixed source/hash inventory. It is an
**unsigned, unpublished CI candidate** from source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, Actions run `38994109408`,
artifact `bloomstep-universal-installer` (artifact ID `12086798368`).

Extract it beside the earlier `BloomstepVM` folder, if present, so cached
portable tools can be checked without being changed. Open built-in Windows
PowerShell on the already-provisioned, owner-authorized Dev Box as a standard
user, then run:

```powershell
.\bloomstep-devbox-installer-trial\Run-InstallerTrial.ps1
```

If the script stops before authorizing/starting the installer, rerun the same
entry point with `-Resume`; every guard runs again and no prior confirmation is
reused. Never run a second copy while the old prerequisite bootstrap or this
trial is active.

The script requires a manually created and owner-verified Microsoft Dev Box
managed snapshot in the Developer Portal. This is **not** a host Hyper-V
checkpoint; the script cannot create or independently verify it. Restoring a
Dev Box snapshot discards changes made later on that Dev Box. The operator must
confirm the listed, usable restore point and accept that loss before the script
can launch the installer. See [Microsoft's Dev Box snapshot/restore guidance](https://learn.microsoft.com/en-us/azure/dev-box/how-to-restore-from-snapshot).
There is no automatic restore or reboot.

The script checks native architecture, Microsoft virtual-machine identity,
non-admin interactive desktop, Defender availability/protection and unresolved
detections, clean product state, candidate and manifest hashes, and any
recognized previous bootstrap cache. It does not install dependencies, run
Inno, access GitHub, register a runner, change policy, disable protection,
clean files, or bypass SmartScreen/Defender. If Windows blocks or quarantines
the unsigned installer, stop and preserve the warning.

Installer execution is a separate explicit confirmation. The visible standard
user runs the wizard and manually checks the app; the package records sanitized
owner observations and a local receipt at `state\trial-receipt.json`. It never
claims protected CI acceptance or release readiness. Protected launch,
lifecycle, x64/ARM64 native and other exact-head Actions gates remain
**UNVERIFIED**; this Dev Box result is supplemental only.

The prior prerequisite bootstrap's entered checkpoint label (including the
operator-entered `Baseline`) is not treated as a recovery point. Existing pinned
tool caches are read-only checked where the previous bundle is in the documented
sibling location. Do not launch this package while the old Bootstrap or
Install-Inno script is still running. Its missing Inno dependency is not needed
for this already-built standalone candidate trial.

The bundle requires no network access, GitHub credentials, PowerShell 7,
Node.js or Inno Setup. Actual Windows/Dev Box, Defender and installer behavior
cannot be validated from the Linux build host.
