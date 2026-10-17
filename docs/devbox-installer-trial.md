# Current Dev Box: one-script installer trial

**No snapshot is required.** This revised package installs the pinned CI
candidate, records your observations, and uninstalls only its own verified
installation. It preserves user data. Uninstall is **not machine rollback** and
does not satisfy protected CI clean-VM requirements.

Download [bloomstep-devbox-installer-trial.zip](downloads/bloomstep-devbox-installer-trial.zip).
In its download directory, open built-in **64-bit Windows PowerShell as a true
non-admin standard user** inside the dedicated Dev Box. Let the old bootstrap
and any Inno UAC window finish/close first. Paste these two lines:

```powershell
if ((Get-FileHash .\bloomstep-devbox-installer-trial.zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'ca521b4921cbeade0745984ba725c154f531f0f069f5e668d5ad5f6def23d822') { throw 'ZIP SHA-256 mismatch: STOP' }; Expand-Archive .\bloomstep-devbox-installer-trial.zip -DestinationPath .\BloomstepTrialUninstall
.\BloomstepTrialUninstall\bloomstep-devbox-installer-trial\Run-InstallerTrial.ps1
```

Use the new extraction folder, not the old snapshot-based package. All safety,
execution and uninstall confirmations are inside this entry point. The visible
wizard/app require owner observation. Exit Bloomstep normally via its tray menu
when asked. No force kills, security-warning bypass, automatic reboot, broad
cleanup, runner registration, cloud access or policy changes.

The script refuses unowned/preexisting product state, binds the installed
uninstaller and log hashes to its exact target/user/candidate, and confirms the
precise product-only removal consequence before invoking it. It checks uninstall
exit status and residual executable/registration/protocol/shortcut/process
state. Timeout (120 seconds) or failure is not success; no automatic retry.
Unknown residual directories and app databases are left intact and reported.
Cleanup cannot reverse arbitrary app/OS/server changes. Use no real data.

If stopped before uninstall starts, rerun the **same script with `-Resume`**:
after an install this only attempts verified owned uninstall, never reinstalls.
If ownership, partial setup or a lost uninstall exit code is ambiguous, preserve
the state and return the blocker; the script does not adopt someone else's
installation. No snapshot/restore operation is attempted and the old typed
`Baseline` is not used.

Return `BloomstepTrialUninstall\bloomstep-devbox-installer-trial\state\trial-receipt.json`,
not the whole state folder. User-observed trial outcome and verified uninstall
are separate fields; protected CI gates remain **UNVERIFIED** regardless of
either. There is no merge, tag, release or website promotion.

Candidate: unsigned, unpublished universal installer from source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, Actions run `38994109408`, artifact
`12086798368`, EXE SHA-256
`664b60d44929da601e22832568d0c88d8baa70f119764958336e065ff4892162`.

Validated on Linux with contract tests/PowerShell parser, inventory hashes and
deterministic packaging. Actual Windows PowerShell 5.1, Defender, Dev Box and
installer/uninstaller execution remain unverified until the owner returns VM
evidence. This package does not require dependencies from the old bootstrap.

Bundle source: `0e9c98714530b5a602d5d634b0dce1ccb1f5383b`.
ZIP SHA-256: `ca521b4921cbeade0745984ba725c154f531f0f069f5e668d5ad5f6def23d822`.
