# Private supplemental controller source — NOT an established VM connection

These are reviewed controller building blocks, not a final connection ZIP.
`validate.yml` is intended for `.github/workflows/validate.yml` in the private
`Sampath-K/bloomstep-vm-controller`; the JSON policy and PowerShell verifier
belong under `controller/`. There is no public PR trigger or arbitrary URL,
shell, branch or script dispatch input.

The hosted authorization job verifies the exact reviewed Bloomstep source,
upstream workflow run/artifact, successful native hosted build/packaging jobs,
and immutable package digest. Protected upstream jobs may still be queued:
these are **not** treated as passed. The VM job is inactive until owner-audited
setup sets `DEVBOX_CONNECTION_AUDITED=true` AND a correctly scoped interactive
runner/local pinned harness actually exists. That variable is an activation
interlock, not security against trusted controller writers.

**No local pinned autonomous harness/setup/listener has been delivered or
registered.** `Invoke-ControllerTrial.ps1` is the future installed interface,
not a claim a file exists on the VM. Current trial ZIPs are manual/supplemental.
Neither hosted authorization success nor a skipped VM job proves connection,
installer behavior, cleanup or protected acceptance.

## Observed publication blockers

Cloud attempts using the approved real files returned:

- Workflow Contents PUT: HTTP403 `Resource not accessible by integration`.
- Candidate-policy Contents PUT: HTTP409 `Cannot create ref due to creations
  being restricted` in the currently empty repository.

No remote controller files or ref were created. Owner-authenticated setup must
initialize the intended `main` ref in accordance with the existing creation rule,
then publish the reviewed files with an authorized workflow-writing identity.
Do not disable rules wholesale or paste credentials into chat. For an installed
app, selected-repository access cannot add permissions absent from its immutable
app permission manifest. An app needs Contents/Workflows write to publish these;
actual Actions write/read must be tested for subsequent dispatch/results.
The current API evidence does not expose the integration's app slug.

Owner-side trust audit remains necessary before registration: true private repo,
effective collaborators and installed apps, trusted writer/admin identities and
approved Actions policy. Personal-account repository runners have no enforced
selected-workflow group boundary: all controller writers/admins must be trusted
with execution as the Dev Box user. Labels/ephemeral mode do not create one.
No runner/service, persistent credentials, policy changes or public CI gate
changes are made by these source files.
