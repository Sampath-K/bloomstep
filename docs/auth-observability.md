# Account-consented authentication observations

This is **partial authentication coverage, not a complete production sign-in
funnel**. Fresh pre-auth discovery, browser, callback, provider failures and
abandoned attempts are **UNKNOWN / NOT covered**. No signup inference, Google
or Microsoft attribution, all-user denominator, or global conversion is
available. The configured CIAM flow does not expose authoritative provider
choice; the only source is `external_unattributed`.

## Source of truth and runtime seams

`shared/event-registry.json` defines `auth_observation`. Generate the Dart/API
allowlists with `node tool/generate_event_registry.mjs`; CI checks drift.
`AuthObservations` is attached only after a verified account's `GardenStore`
has opened. Existing `analytics == 'true'` is required atomically for every
write; no existing account gains consent. The observed stages are:

| Stage | Actual seam | What success establishes |
| --- | --- | --- |
| `session_entry` | `HabitHome._showGarden`, authenticated session diagnostics initialization | Account-local session diagnostics initialized, including restored sessions; not fresh provider authentication or successful Garden UI rendering. Device-only guests have no auth observations or analytics. |
| `api_token` | `IdentityService.accessToken`, all production callers in this session | API token obtained and session checkpoint saved, not token acceptance by the API or provider sign-in |

Fresh `signin_succeeded` retains its existing account-consented behavior;
restored sessions never manufacture that event. A fresh initial sign-in without
known consent emits nothing. Enabling consent later does not backfill attempts,
failures or session-entry observations. No unchecked pre-auth opt-in or anonymous
collector was added: those require a separate consent, abuse-budget and deletion
architecture review.

## Bounds and privacy

At most ten attempted observations per account-session scope, each with one
`started` and at most one `succeeded`/`failed` observation. Attempts have a fresh
random UUID, a closed stage/outcome/error-kind/source, Windows platform, and
integer monotonic elapsed milliseconds (0–180000). Beyond three minutes the
terminal is discarded, not reported as timeout. A real `TimeoutException` is
`timeout`, a `SocketException` is `network`, `FormatException` is `validation`,
explicit known failures can be `unavailable`; otherwise `unknown`. No inferred
cancellation. Raw exceptions are not telemetry; optional storage failures
surface a fixed warning and do not prevent the underlying auth operation.

No URLs, query strings, referrers, token/code/state/nonce/PKCE, issuer, email,
subject, error text or stacks are recorded. Observations use existing account
ownership only after verification. They do not link failed pre-auth activity to
a profile. Withdrawal purges local queued events via existing analytics
withdrawal, invalidates in-flight attempts even across reconsent, and leaves
existing remote deletion workflow unchanged. Account switch/generation/closed
scope invalidate pending completions. No durable pre-consent attempt state.

## Ingestion, private operations and limitations

Existing JWT-authenticated sync ingests the strict allowlist; the server does
not prove human consent or trustworthy client execution. There is no new
endpoint, bypass, resource, permission or cost. Token failures can remain
offline/local until a later successful sync; permanently failing tokens cannot
deliver their own failure evidence. User-uploaded telemetry is not broker logs.

The existing on-demand dashboard and daily worker include `authentication`.
Pairs require the same account/attempt/stage, exactly one start and terminal,
ordered UTC timestamps in the requested window, at most three minutes, and
wall-clock/monotonic duration agreement within two seconds. Duplicate uploads
of identical event IDs are idempotent; conflicting IDs and multiple terminals
invalidate completion evidence. Clock corrections, missing/expired evidence and
cross-window pairs remain unknown, not success-shaped defaults.

The private operator console labels this partial coverage and shows user counts
only for cohorts of at least 50, also suppressing subtractable small
success-only/failure-only/both/no-terminal subsets. Fixed failure categories
publish only when their non-subtractable user-membership partitions also reach
50. No provider breakdown or
failure percentage is inferred. Zero events yields unavailable counts, never an
accurate all-user zero. Historical stored snapshots can omit this new section
and explicitly display instrumentation unavailable.

Automated tests use in-memory accounts, simulated operation outcomes and strict
server contracts. They are **not real Microsoft/Google login evidence**.
Provider authentication stays out of routine E2E; isolated nonprovider test
login is owned by the separate synthetic acceptance workstream, not a production
authenticator bypass.

Deploy the API/console first, then publish a native preview built from the merged
commit. A merged PR or green synthetic test alone is not released runtime proof.
Coordinate preview publication separately from any customer upgrade.
