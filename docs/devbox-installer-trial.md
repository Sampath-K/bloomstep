# Standalone Dev Box installer trial

This is a **supplemental owner test only**, not protected CI evidence or a
release. It bundles the exact unsigned, unpublished universal-installer artifact
from Actions run `38994109408`, source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, artifact ID `12086798368`.

Download [bloomstep-devbox-installer-trial.zip](downloads/bloomstep-devbox-installer-trial.zip)
and verify SHA-256:

```text
TBD
```

Extract it beside the earlier `BloomstepVM` folder, if present. Open built-in
Windows PowerShell on the already-provisioned Dev Box as a non-admin standard
user. The two commands are:

```powershell
if ((Get-FileHash .\bloomstep-devbox-installer-trial.zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'TBD') { throw 'ZIP SHA-256 mismatch: STOP' }; Expand-Archive .\bloomstep-devbox-installer-trial.zip -DestinationPath .\BloomstepTrial
.\BloomstepTrial\bloomstep-devbox-installer-trial\Run-InstallerTrial.ps1
```

The script requires a usable **Microsoft Dev Box managed snapshot** created and
confirmed in the Developer Portal before it will run the installer. This is
not a host Hyper-V checkpoint; the script does not create or independently
verify the restore point. Restore discards all later changes on that Dev Box.
Follow [Microsoft's Dev Box snapshot and restore guidance](https://learn.microsoft.com/en-us/azure/dev-box/how-to-restore-from-snapshot).
It checks native x64/ARM64 architecture, non-admin interactive desktop,
Defender protection and unresolved/new detections, clean Bloomstep state, the
candidate and architecture manifests, and recognized caches from the previous
bootstrap (read-only). It does not require Inno, Git, Node, PowerShell 7,
GitHub credentials or network access.

The installer runs visibly as the standard user, only after a separate
`RUN UNSIGNED CANDIDATE` confirmation. Do not bypass SmartScreen/Defender or
continue after a warning or quarantine. The script does not restore the Dev Box,
reboot, remove data, register a runner, alter a policy, or automatically start
another trial after an interrupted installer. It writes a sanitized local
receipt at `state\trial-receipt.json`; only manually observed outcomes are
recorded. The prior entered checkpoint name `Baseline` is ignored as recovery
evidence.

This manual trial cannot satisfy exact-head protected lifecycle, launch,
native x64/ARM64, funnel or other Actions requirements. Protected acceptance
and release authorization remain false. No merge, tag, publishing, signing or
website promotion is performed.

The package's internal inventory pins its source scripts and candidate files.
The separately supplied outer ZIP digest is required to authenticate that
inventory. The source scripts were parser-checked on Linux; actual Windows
PowerShell 5.1, Dev Box recovery, Defender and candidate execution are not
verified by this worktree.
