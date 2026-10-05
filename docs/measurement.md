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
## Current operator visibility and original goal gaps

The deployed console is at
<https://brave-plant-02c10e800.5.azurestaticapps.net/>: expand **Product team
console (deployment verification)** near the footer, use its real operator
sign-in, select the bounded day window and **Load private preview measurements**.
It is first-party static UI plus private Functions/Cosmos APIs, not an
AppInsights/PostHog dashboard. The API requires an explicitly selected/assigned
customer `Bloomstep.Admin`; repo/subscription ownership or asking to view metrics
is not permission to grant that role. No current population counts are claimed
without that separately authorized channel.

Four shipped typed panels show ordered opt-in funnel, exact-day practice
retention, daily habit outcomes and observed reminder health. Typed windows end
on the last completed UTC day; separately labeled compatibility counts include
today. Retention includes a30-day first-practice lookback and closes target UTC
dates before reporting maturity. Counts/rates below50 contributing accounts
are unavailable: both rate denominator and intersected numerator must reach50.
Null/suppressed is not zero. These are observed independently opted-in,
self-selected observations, not all downloads/installs/customers.

| Original spec hypothesis/goal | Current measure and explicit gap |
| --- | --- |
| Sign-in success85% of attempts | Ordered distinct-account launch-to-sign-in rate is not an attempt-success rate; initial unauthenticated broker coverage is incomplete. |
| Day0 activation60% | Same-local-day positive first-check-in after observed sign-in, divided by observed signed-in accounts; opt-in coverage is not an all-user denominator. |
| D7 at least3 check-ins40% | Current D7 measures effective positive practice on exactly cohort day+7, not at least3 check-ins in a seven-day interval. |
| D30 practice on at least50% of days23-30,25% | Current D30 measures exactly day+30, not the day23-30 frequency criterion. |
| At least1 graduate byD90,15% of activated users | Daily graduation events/unique graduated users exist; activated-user90-day cohort KPI does not. |
| North star: graduated habits per activated user at30/60/90 days | Daily score medians, practice/graduation users/counts are not this cohort denominator/window metric. |
| Notification disable within30 days at most10% | Current sent users with a disable event in the selected window divided by sent users is not a matured30-day cohort rate. |
| Feedback response within2 business days; low-star response within48h | Private status/reply workflow exists; business-calendar SLA and low-rating response KPI are not implemented. |
| Invitations at least0.3/user in30 days | Share/accept observations are not verified invitation delivery or a30-day per-user metric. |
| Crash-free sessions at least99.5% | Deliberately null: bounded opt-in Dart/Flutter error categories may be nonfatal; complete all-session/native/process-death census is absent. |

These original targets are hypotheses/acceptance requirements, not newly
proposed goals or achieved outcomes. The console does not yet display
goal-versus-actual target comparisons. Formula/SLA/north-star gaps above are
implementation work, not merely blocked on population; record their owner and
sequence separately from live cohort/permission gates. No automatic all-user
attribution or native-death coverage is inferred from a registered event name.

Website/installer receipts remain local/default-off with original times/IDs and
seven-day expiry; account linkage is explicit under independent product-event
consent, never automatic visitor-to-installer-to-broker tracking. An observed
notification request is not proof of OS delivery. Persisted daily-worker history
and latest-completed-day panels remain distinct from on-demand rollups; absent/
stale/invalidated snapshots are unavailable, not silently replaced. Scheduled
aggregate37288175463 succeeded on October5 at09:09UTC, acknowledged one
prior-day snapshot and verified real worker denial on garden/team routes.
The committed daily02:20UTC cron ran late; this proves one scheduled execution,
not punctuality, metric values, completeness or all freshness/backfill cases.
The bounded experiment stays OFF pending genuinely reviewed exposure/
guardrail/cohort evidence; this is not an invented minimum-install preview
release threshold. Financial/billing status remains a separate unknown.
