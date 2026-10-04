# Consent-scoped observation contracts

This source is instrumentation, not proof of users, a complete funnel, a
crash-free population or a completed experiment. Verified `v0.1.0-preview.3`
contains these controls; preview.2 predates receipt import.

## Source of truth and explicit linkage

The website has no product-analytics upload endpoint. Optional local consent is
unchecked unless a valid prior consented receipt is present. The browser-owned
key `bloomstep.measurement-receipt.v1` stores at most32 actual post-consent page,
valid current invitation-view and download-click observations. No URL/referrer,
invitation code, fingerprint, account, architecture or private text is stored.
A click is not download completion, installation or referral redemption.
Exports are user-requested JSON receipts, never automatic account linkage.

The interactive Windows installer has a separate unchecked local observation
choice. Silent installers collect nothing. After selection it observes the
actual file-installation phase (`installer_started`, not earlier bootstrap)
and post-install completion. The owned local file is
`%LOCALAPPDATA%\Bloomstep\measurement\installer-receipt.json`. A random
`measurement-owner.txt` in the installed directory binds subsequent app
observations to that installation without exporting a path/device identifier.
Only a matching, completed, explicitly opted-in installation can add one
first owner-process launch and one actually displayed sign-in view. Portable
or different installs cannot append to another installation's receipt.
Every upgrade clears the old installation marker before copying files; a
silent/default-off upgrade cannot inherit prior installation observation
ownership. A previously consented local receipt can still be explicitly
cleared or linked by its owner, but is not automatically appended.
An installation failure can leave only the observed start, never a fabricated
completion. The matching installation's uninstaller removes its own receipt.

Both receipts contain only schema version, fixed source, consent UTC time and
event UUIDv4/name/original UTC time. They expire exactly seven days after
source consent; expired receipts are rejected and removed on next local access.
Browsers/apps that are not opened cannot run physical cleanup: clear storage
or use the app's receipt-clear control for immediate deletion. Storage is
bounded16KiB/32 observations; installer observations are at most four.
Exported copies must be deleted separately. Storage/clock/format/size failures
are explicit and never block ordinary download or sign-in.

App Settings requires independent current account product-event consent and
a second confirmation naming source/count/original time range. Only your own
receipt should be linked. Import preserves original IDs/times, rejects extras,
invalid sources, pre-consent/reversed/future/expired events, and atomically
rejects conflicting retries or IDs already owned by another local account.
Exact retries add no duplicates. Account/generation are rechecked after the
confirmation and within the transaction. IDs are observations, not unique
visitor or device identities.

Linked observations enter the existing private per-account SQLite `events`
table and durable authenticated sync path. They are indexed by event ID,
account and original UTC time; backend property/source validation and retention
apply. `measurementSource` distinguishes voluntary website/installer receipts.
Turning off account product events purges linked local events/queued event
sync and clears the local installer receipt; browser storage/exported copies
remain a separate user choice. Server event retention is13 months; receipt
time is preserved, never replaced with import time.

## Runtime errors and interpretation

Current consent/account/generation gates framework and unhandled Dart hooks.
The original presentation/return semantics remain; hooks detach before store
close. At most ten observed errors per session persist fixed source/category,
session UUID and platform. No messages, stacks, URLs, tokens, habits or feedback
are captured. Write failures show a fixed warning. Opt-out purges the queue.
These errors can be nonfatal. Native crashes/process deaths and full diagnostic
coverage are not observed; `crashFreeRate` intentionally remains null.

The funnel uses ordered original events in the same explicitly linked account.
This is a voluntary, self-selected sample, not authenticated install attestation
or automatic browser-to-broker attribution. Missing/unlinked/capped observations
are not zeros or proof of failed conversion. Minimum50 is a metric publication
threshold. Genuine reviewed cohort/guardrail evidence gates activation of the
bounded experiment, which remains OFF. The original experiment requirement is
not completed merely by instrumentation/config readiness.

## Verification boundary

Unit/SQLite/widget/browser/installer tests use explicitly synthetic observations,
never actual customers or cohort results. CI checks silent/default-off install,
the actual owned interactive checkbox, real installation and shown sign-in
events, UUID/privacy fields and matching uninstall. Genuine account sync,
operator readback, consent revoke/delete and cohort review remain separate
live acceptance gates; the implementation session owns component checks and
cleanup once trusted-browser sessions are available.
