# Budlock supplemental Dev Box connection

**Published setup package, not an established VM connection.** Current
controller Actions policy still allows all Actions; owner approval/configuration
of the exact three-pin policy and effective owner/app audit remain outstanding.
Setup deliberately stops before registration until they are resolved. There is
no runner registration, snapshot, release acceptance or protected-CI substitution.
Do not interpret the hosted authorization PASS below as a Windows trial PASS.

The approved legacy Bloomstep EXE, hashes, paths, controller slug and public
PR48/PR51 heads are unchanged. This connection does not apply the separate
Budlock customer-facing rename to that candidate.

## Immutable source and package

Source commit: `7f1bc11770d588bb87922badc836c639defc2697`, preparation branch
`sampath-k-cautious-umbrella`.

Download [budlock-devbox-controller.zip](downloads/budlock-devbox-controller.zip).
SHA-256:

```text
4acc854ba2bbfb3fbaa30c4eb22524f78eb3ba8b95e93cedba08d223ddb4d3ad
```

The ZIP was built twice independently from that commit; bytes matched.
Its manifest identifies that exact source and all **13 source files**.
All file SHA-256 values and original git bytes were independently compared.
There are 14 ZIP entries including `package-manifest.json`, no executable
candidate or credential. Official portable runtime/runner release asset digests
were independently read back from GitHub and matched all four architecture pins.

Exact source inventory:

```text
tool/devbox-controller/Connect-DevBox.ps1
tool/devbox-controller/Invoke-ControllerTrial.ps1
tool/devbox-controller/connection-dependencies.json
tool/devbox-controller/validate.yml
tool/devbox-controller/Verify-Candidate.ps1
tool/devbox-controller/approved-candidates.json
tool/devbox-controller/README.md
tool/protected-vm/Bootstrap.Common.ps1
tool/devbox-trial/Run-InstallerTrial.ps1
tool/devbox-trial/Trial.Common.ps1
tool/verify_onboarding_wizard.ps1
tool/universal_integrity_contract.ps1
tool/process_token_probe.cs
```

The deterministic packager is `tool/package_devbox_controller.py`; focused
controller contracts are `test/devbox_controller_test.mjs` at the same source.

## Required one-time owner steps, then two commands

Follow the bundled `README.md` or the [immutable owner setup/audit guide](https://github.com/Sampath-K/bloomstep/blob/7f1bc11770d588bb87922badc836c639defc2697/tool/devbox-controller/README.md).
It gives exact GitHub collaborator/app/token/settings pages, the two narrow
Actions policy JSON bodies, selected-repository setup token permissions and
revocation. These are real required owner-side gates, not checks the cloud can
silently satisfy or bypass. No repository/app/policy change is performed by the
VM script. A local masked token and the owner trust/IT attestation are required
once at connection setup, not for each subsequent approved-candidate trial.

After those gates are resolved, download the ZIP into Downloads and use ordinary
64-bit Windows PowerShell under a **true standard user**, not Administrator.
The first line verifies the outer digest before extraction. Leave the second
command's interactive listener open:

```powershell
$ErrorActionPreference='Stop'; $z="$HOME\Downloads\budlock-devbox-controller.zip"; if((Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash.ToLowerInvariant() -cne '4acc854ba2bbfb3fbaa30c4eb22524f78eb3ba8b95e93cedba08d223ddb4d3ad'){throw 'ZIP digest mismatch'}; Expand-Archive -LiteralPath $z -DestinationPath "$HOME\BudlockConnection"
& "$HOME\BudlockConnection\bloomstep-private-controller\Connect-DevBox.ps1"
```

Do not change execution policy or bypass signing/security warnings if blocked;
use the organization's approved signing/authorization route. Later explicit
listener recovery uses the same installed bundle entry with `-Resume`; it
revalidates the registration and files, never silently replaces them. No
service, autologon, scheduled task or lock bypass is configured.

The one-time confirmation authorizes exact reviewed candidate execution and
bounded owned native uninstall of program/shortcut/protocol/startup state.
Data is preserved, unrelated/preexisting state blocks execution, unknown dialogs
and normal-exit failures stop with evidence. Uninstall is **not VM rollback**.

## Observed test and artifact receipts

The following command completed with **28 tests, 28 passed, 0 failed, 0 skipped**
using isolated PowerShell 7 on Linux:

```sh
node --test test/devbox_controller_test.mjs test/devbox_installer_trial_test.mjs test/protected_vm_bootstrap_test.mjs test/protected_runner_preparation_test.mjs
```

Coverage includes metadata header/path/no-redirect routing and no unauthenticated
fallback; permanent 401/403/404 versus rate-limit diagnostics; bounded transient
503/429 and Retry-After; preservation of earlier cleanup/failure authority during
preflight/lock failures; source parser, native-payload/cache/uninstaller ownership,
Defender guards and exact action-policy/documentation contracts. These are
contracts/mocked boundary checks, not actual Windows UI/runner execution.

Real authenticated hosted authorization:
[run 39019811122](https://github.com/Sampath-K/bloomstep-vm-controller/actions/runs/39019811122),
private controller head `f183221c3ebe956b746f325c3f8236b2dc8ffa9a`.
`authorize` **SUCCESS**, `trial` **SKIPPED** (activation absent).
Cloud downloaded `approved-candidate` artifact **12096202559** and independently
verified its ZIP digest:

```text
fd7133a35b62d0fb35f20e8c39d20e21189115116d08be5f0f4671f1148c44b2
```

Its real receipt records candidate source
`bd5ad93ad28988123ef7d3e28eab989f91cc4362`, upstream run `38994109408`,
installer SHA-256
`664b60d44929da601e22832568d0c88d8baa70f119764958336e065ff4892162`,
retained candidate package SHA-256
`ca521b4921cbeade0745984ba725c154f531f0f069f5e668d5ad5f6def23d822`,
and `protectedGatesAccepted=false`, `protectedGateStatus=UNVERIFIED`.
The transferred candidate ZIP's bytes matched that receipt.
Earlier run `39019173776` remains FAILURE; it was not reclassified.

## What is not verified

Actual Windows PowerShell 5.1 setup, local masked authentication, server
registration/online listener, interactive desktop/Defender state, native
installer/app/uninstaller automation and the subsequent uploaded VM result remain
**UNVERIFIED**. Actual app/window observation is deliberately limited, not full
customer journeys or accessibility acceptance.

`connection-receipt.json` explicitly reports
`LISTENER_STARTING_NOT_CONNECTION_PROOF`. The cloud/coordinator owns the final
connection confirmation: read the real private run, verify native VM trial
success and download its sanitized `supplemental-result.json`. No connection
success may be claimed from that local starting receipt or hosted-only run.
An unlocked interactive session must remain available; logout, lock, reboot and
runner version aging can require explicit local recovery.
