# Consent-scoped observation contracts

For the additive private AARRR overview, exact account-only denominators,
privacy/completeness boundaries and isolated HTTP/disk/render acceptance,
see [aarrr-dashboard.md](aarrr-dashboard.md). Anonymous acquisition remains
a separate event-count unit; no automatic browser-to-account journey is
inferred.

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

## Fresh app reminder-preference choice

The next native candidate adds disclosure version 1 as a separate unchecked
Settings choice. Existing product-event consent does not grant it. Local
`reminderObservationConsent` and `reminderObservationEpisode` settings in the
same owner SQLite store are the source of truth; they export with local records
but never sync as preferences or enable another device.

A genuine explicit post-consent app reminder enable after successful gateway
initialization starts an episode. Startup restore and repeated enable do not.
The three required-field events carry only random episode/consent UUIDs, fixed
Windows platform, version, local date and original UTC timestamp. Explicit
disable and a persisted same-epoch enabled preference after 30 days are linked,
idempotent observations, not Windows permission/delivery or lifetime history.
Missing followup remains unknown. General-purpose tracking cannot emit them.
Revoking either choice clears added local state/events/sync fingerprints;
new consent cannot bind old episodes. Already-sent facts use existing retention
and account deletion, not a promise to recall an in-flight HTTP request.

Private Admin metrics and a separately labeled console panel project bounded
observed episodes, suppress under 50 distinct owners/contributors and reject
conflicting facts. The original notification-disable <=10% goal remains
`not_observable`, with no comparison to this narrower sample. See
`backend-contracts.md` for schema, horizon, privacy and failure semantics.
Source tests do not prove real native preference/OS surfaces, customer sync or
actual 30-day cohorts. No new customer collection, OS change or native-health
collection is authorized by publishing the source.

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
| First launch to signed in85% | Authoritative original spec section20 says first launch, not attempts. Ordered distinct-account launch-to-sign-in measures the observed window only; initial broker/installer coverage is incomplete. An attempt-success85% claim would be a different requirement and is not inferred. |
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
proposed goals or achieved outcomes. Historical four-panel gaps above describe
the pre-goal baseline. Formula/SLA/north-star gaps are
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

## Version1 target-aligned goal contracts

Source now adds a separately versioned on-demand `goalMetrics` response and
goal/actual console card, preserving existing exact-day panels and strict daily
snapshot schemas. Release/deployment/readback is tracked in `docs/status.md`;
source validation is not current population evidence. Numeric targets, observed
actuals, numerator/denominator, reason, coverage and window are displayed.
Unavailable measurements never produce a pass/fail badge or substitute proxy.

Activation is the earliest observed explicit positive `first_checkin` with
habit UUID/localDay, an historical observation even if subsequently undone.
D7 counts at least3 latest-effective positive **habit/local-day** check-ins
in offsets1-7. D30 requires at least4 distinct positive **dates** in offsets23-30
inclusive, not four habits on one date. Cohorts are mature only when day+7/30
falls in the selected completed UTC window; immature cohorts are excluded, not
classified as failures. Graduation means at30/60/90 use distinct account/habit
UUIDs observed from activation through the inclusive horizon, with activated
users as denominator. D90 graduates count each graduating user once. No
numeric north-star target was specified, so it is tracking-only.

An extra90-day activation lookback replaces the previous30-day raw scan
lookback for this read, retaining the same10,000-event/200-account scan ceilings,
role/audit/budget gates and deletion filtering. Exceeded scans fail429 before
any partial values. Duplicate immutable envelopes converge; conflicting ones
are excluded independent of order, and later edits/undo revise effective
practice. Missing IDs/dates and absent opt-in history are not imputed. Both
denominator and contributing-user count must reach50; low-frequency goals can
remain suppressed within the200-account preview cap even with a mature cohort.
All source fixtures are synthetic, not a claimed launch population.

Notification30-day cohort start, verified invite delivery/K-factor, server
receipt/first-response SLA evidence/business calendar and complete native
session/fatal coverage are not supplied by the old events. Their original
numeric goals remain explicitly unavailable. Codeable collection gaps remain
developer work; a selected operator, genuine users and calendar/controller
decisions are separate gates.

Daily-worker availability now also exposes the committed02:20UTC cron,
latest-day due time, whether that time has passed and each valid snapshot's
signed generation offset in seconds. Early manual/backfill generation is not
a scheduled-run proof; a late generation is not a guaranteed scheduler SLA.
Missing/stale/invalidated records stay unavailable with no raw/old-day fallback.
Repair is explicit worker backfill of at most30 completed UTC days; unchanged
retries preserve original generation time.

## Native health feasibility evidence

An isolated headless ARM64 C++ fixture, compiled using the already approved
Visual Studio/Windows SDK, observed normal exit0 and a real unhandled native
exception. A deliberate `ExitProcess` with the same exception status produced
the identical `0xc0000005` exit code without the native-exception hook signal.
No customer process/GUI/data was touched and no dump was requested. This proves
exit codes or unclean-session markers alone cannot identify fatal crashes.
It does not prove fast-fail, kill, power-loss, hook replacement, transport,
consent or all-session coverage. A category-only native hook plus independent
lifecycle observation/recovery requires further design/implementation and
controller/canary interpretation. Original99.5% evidence remains incomplete;
unknown exits cannot be silently counted as healthy or crashed.
