# Scope note

This is the earlier **prerequisite-only protected-runner bootstrap**. It is not
the Dev Box installer-test package and its manually entered checkpoint name is
not recovery evidence. Do not start it concurrently with another setup. For
the standalone, supplemental owner installer trial on an existing Dev Box, use
[the Dev Box installer-trial bundle](devbox-installer-trial.md).

# Run one script inside your disposable VM

Download [bloomstep-vm-bootstrap.zip](downloads/bloomstep-vm-bootstrap.zip).
In its download folder, open built-in **Windows PowerShell as a standard user**
inside the disposable Hyper-V guest, then paste these two lines:

```powershell
if ((Get-FileHash .\bloomstep-vm-bootstrap.zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne '7ee7b36f1b80d50a71cb7d9b4b5ae1629f04377de408ead4c53fba0a186cee98') { throw 'ZIP hash mismatch: STOP' }; Expand-Archive .\bloomstep-vm-bootstrap.zip -DestinationPath .\BloomstepVM
.\BloomstepVM\bloomstep-vm-bootstrap\Bootstrap.ps1
```

It handles prerequisite detection/downloads, checksum verification, bounded
transient retries, protection checks, separate dependency-only UAC setup,
machine-readable receipts and next actions. Follow the prompts in that one
script. After it requests a restart/resume, run the **same** entry point:
`.\BloomstepVM\bloomstep-vm-bootstrap\Bootstrap.ps1 -Resume`.
Do not unzip again over a prior run; reuse the existing extracted folder.

**This is preparation, not a complete runner setup.** It stops at `TrustBlocked`
until an enforceable restriction can exclude unreviewed public-repository code.
There is no token prompt, runner registration or installer test execution.
Do not replace that block with a yes, label, queue audit or ephemeral flag.
Corporate DevBox/IT approval still applies; no environment is provisioned.

The script asks for confirmation that a clean host checkpoint exists before
setup. It cannot create a host checkpoint from inside the guest or independently
verify that operator attestation. No autologon, automatic restart, service,
scheduled task, execution-policy change, Defender exclusion or warning bypass.
If Windows blocks script execution, STOP and return the error, not a bypass command.

Return `BloomstepVM\bloomstep-vm-bootstrap\state\bootstrap-receipt.json` and
sanitized preflight receipts. Do not upload the whole state directory.
Exit 1 means failed/declined; 2 means dependency setup/restart/resume needed;
3 means prerequisites prepared but registration blocked. None means all gates passed.

Bundle source: `33ca30f373a6883ad464834b3cd5c6dc69845c44`.
ZIP SHA-256:
`7ee7b36f1b80d50a71cb7d9b4b5ae1629f04377de408ead4c53fba0a186cee98`.
All bundled files and the existing protected harness are pinned in its manifest.
See bundled `README.md` for the risk boundaries and receipts.

Verified on Linux: PowerShell parsing, retry/backoff, resume exit mapping, package
inventory, tamper detection and deterministic packaging. Actual Windows PowerShell
5.1, Hyper-V/Defender/input desktop, UAC and restart/resume behavior remain unverified
until run inside the VM. x64 cannot satisfy native ARM64 evidence.
