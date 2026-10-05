# Synthetic native input verification

The existing true Windows ARM64 CI build produces `tool/preview.dart` as an
explicit **synthetic profile**, not the normal sign-in release. Its store is
`synthetic-preview-only`; no identity or cloud client is supplied. Source
contracts run on ordinary CI. Native interactive verification is separately
opted into with the `ci` workflow's `verify_native_input=true` dispatch input,
default false. It runs after the current synthetic profile build, without
changing a candidate version, installing tools or changing OS permissions.

`tool/verify_synthetic_input.ps1` refuses local/non-ARM64 hosts, arbitrary binary
paths, wrong PE architecture, another synthetic owner, and pre-existing database
or result files. It verifies the synthetic banner and exact process/view,
requires the actual foreground owner, and never overrides Windows focus policy.
The text setter's HRESULT is recorded; any fallback uses only targeted messages
to the owned Flutter view after semantic focus and safe field bounds are proved.
Queued input is not success: the exact synthetic text must read back.

The bounded sequence opens the real fourth-recipe confirmation, selects a
starter, edits a synthetic aspiration, saves, enters and cancels another recipe,
and restarts to check saved/canceled state. It then invokes only the uniquely
scoped synthetic recipe's check-in, undo and individual delete, followed by
restart/deletion readback. No account wipe, sign-in, operator role, invitation,
notification permission or native-health collection is involved.

Readiness and state waits are bounded, and the CI step has a three-minute
deadline. `finally` closes only the exact launched synthetic process and removes
only the exact new synthetic SQLite files. Existing data is never overwritten.
The result file is created exclusively and contains fixed phase/outcome flags,
tooling HRESULTs and errors, not account data. Cleanup failures are explicit.
CI preserves available synthetic results even when the step fails.

If the runner lacks an interactive foreground, the dispatch **fails** with that
specific host limitation before typing. It does not fabricate a successful
native interaction or make widget/source checks a substitute. Ordinary CI and
release dispatches do not implicitly enable this tooling experiment.

Even a passing dispatch proves only this synthetic current-source native
journey on that host. It does not validate the installed customer's foreground,
provider exchange, authenticated API round trips, cross-account isolation,
reminder delivery or cleanup of real account records. Those require their
separately coordinated acceptance surfaces and permissions.
