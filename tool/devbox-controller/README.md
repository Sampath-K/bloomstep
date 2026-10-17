# Budlock private Dev Box controller connection

This connection source is for **supplemental automated installer testing** on
the owner's dedicated Dev Box. It never satisfies public protected CI,
accessibility acceptance, full customer journeys or release approval. No
snapshot is required; uninstall is not machine rollback. No runner has been
registered or VM execution verified by the Linux authoring session.
The pinned EXE, paths, repository slug and internal protocol identifiers retain
their legacy **Bloomstep** identity; this package does not rename that candidate.

## Trust and owner-side publication

The controller is `Sampath-K/bloomstep-vm-controller`, PRIVATE, owner-only human
collaboration. Personal repository runners cannot enforce selected-workflow
access. **Every controller writer/admin and authorized app can execute as the
Dev Box user**. Labels, activation variables and ephemeral mode do not create
workflow isolation. Owner must audit actual app access before installation;
this script cannot enumerate every authorized app using a repo-scoped token.
Do not install if that audit or corporate permission is unresolved.

Publish `validate.yml` as `.github/workflows/validate.yml`, and
`Verify-Candidate.ps1` plus `approved-candidates.json` under `controller/`.
Setup checks published workflow/verifier hashes against its own reviewed
bundle before it will register anything.

Owner-configured Actions policy must be enabled, `allowed_actions=selected`,
with GitHub-owned/verified blanket allowances FALSE and exactly these patterns:

```text
actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
```

Default workflow token is read-only and cannot approve pull requests.
`Connect-DevBox.ps1` audits this policy but never changes it. Activation variable
`DEVBOX_CONNECTION_AUDITED` is set only after the verified private/human/pinned
workflow policy and the explicit one-time owner app/IT audit confirmation.
It is an activation interlock, not protection against a malicious writer.

## One entry point on the VM

After verifying the independently provided connection ZIP digest, extract and
run `.\Connect-DevBox.ps1` using ordinary built-in **64-bit Windows PowerShell**
as a true non-admin standard user. Leave its interactive listener open. It
downloads pinned/checksummed official portable PowerShell and GitHub runner
assets with bounded transient retries; no global install, UAC, execution-policy
change, Defender exclusion, service, autologon, scheduled task or incoming port.

One-time prompts confirm persistent private-controller access and take a masked,
short-lived fine-grained setup token scoped ONLY to the private controller:
Administration read/write for runner audit/registration, Actions read/write for
dispatch, Contents read for reviewed workflow audit, Variables read/write for
activation. Authenticate locally; never send a token in chat. The token stays
in process memory, not the ZIP/receipts/runner arguments. Short-lived runner
registration input is passed through the runner's supported environment input
and cleared; the runner's own persistent credentials remain in its local folder.
Do not upload that folder.

The same `Connect-DevBox.ps1 -Resume` rechecks guards, source, pinned executables
and server registration before restarting the existing listener. It does not
silently update/replace code or register a second runner. A stopped, outdated
runner or revoked token is a clear failure, not a bypass. Official runner
updates are disabled until a new version/hash is reviewed; GitHub may refuse
outdated runners. Stop the listener to stop work; remove it from private
repository Settings to revoke registration. No automatic restart/logon exists.
Lock, logout, RDP/session changes and reboot can make the desktop unavailable.

## Authenticated test and result flow

The script sends a real fixed-candidate dispatch after setup, then starts the
interactive listener. `connection-receipt.json` says LISTENER_STARTING, not
connection success. Cloud must independently read the resulting private Actions
run and uploaded sanitized result before claiming a working connection.

Later runs are dispatched by candidate ID/native architecture, with no arbitrary
URL/command/ref input and no per-run human confirmation. A trusted writer must
review exact source, successful hosted native builds, packaging and immutable
package/EXE hashes into the committed policy before a new candidate is eligible.
The hosted verifier uses only built-in read-only `GITHUB_TOKEN` for exact
`api.github.com` public build metadata; redirects are forbidden and that header
is never sent to raw/download hosts. HTTP auth/rate/resource failures are not
success. Only 408/429/selected 5xx use bounded retry/backoff.

The VM harness checks private main-dispatch context, committed private policy,
transferred candidate hashes, native architecture, standard-user interactive
desktop, Defender and unowned product state. Candidate archive scripts are
never imported. The installed reviewed local harness drives only the exact
standard native Install/Finish pages, checks payload files, same-user
non-elevated visible app survival, requests normal WM_CLOSE and invokes only
the verified generated uninstaller/installation log at the owned path.
Unknown dialogs/security warnings, unexpected processes, app refusal to exit,
native mismatch and dirty/ambiguous state fail closed. No force killing.
Uninstall interaction is bounded to 120 seconds plus 15 seconds for removal
verification. Failures do not silently retry setup/uninstall.

User data is **never deleted**. Subsequent successful owned trials may preserve
earlier trial data and cannot claim clean-data equivalence. Unowned/preexisting
data or residual program files block testing; unresolved prior failures block
another run for review. No rollback of OS/account/server effects is promised.

Sanitized `supplemental-result.json` is uploaded to the private run even on
failure (when the harness starts). Local ownership path/SID stays local.
No screenshots/customer data are uploaded. Measured native wizard, app window
and product removal are not full customer or accessibility acceptance.

## Observed evidence and limits

Cloud real dispatch of the earlier published controller succeeded as run
`39019173776`, but hosted authorization FAILED on unauthenticated public API
rate exhaustion and the VM job skipped. It was not connection proof. The new
authenticated metadata fix requires a fresh hosted run after reviewed publication.

The Linux checks cover contracts, parser syntax, provenance/header routing,
package hashes and unchanged manual/protected-bootstrap guards. Windows
PowerShell 5.1 setup, actual local authentication/registration, Defender,
native UI automation/uninstaller and the live result handshake remain
**UNVERIFIED** until executed on the owner's VM under audited policy.
