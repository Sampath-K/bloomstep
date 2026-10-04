# Bounded backend telemetry and engagement contracts

Source and deterministic store tests only: this is **not** evidence of deployed
dashboards, successful live JWT sign-in, Cosmos transactions/indexes, native
reminder delivery, or an observed customer/team round trip. No cloud settings,
credentials, handwritten client, website, or workflow changes are made by this
workstream. The native event-registry file is generated for client-owner wiring.

## Authentication and client compatibility

Every registered route calls the existing real `jose` JWT verifier: HTTPS JWKS,
RS256, exact configured issuer/audience, required sub/iss/exp/iat, and
`Garden.ReadWrite` scope or explicit `Bloomstep.Admin` role. The separately pinned
resource-tenant aggregate verifier admits only the internal worker endpoint; a token with
that role but without Admin is explicitly denied garden/account operations,
even if it also has a garden scope. Account partition
keys remain SHA-256 of the exact validated `issuer|subject`, not email. Both
admin routes independently require that exact role; a garden scope is not an
operator role. Azure Functions `authLevel: anonymous` does not bypass JWT checks.
Missing provisioned identity/database configuration returns 503; invalid tokens
return 401 and missing privileges return 403. There is no fake identity path.
The handler factory injects stores/auth only for isolated tests; production
always supplies the strict verifier and configured Cosmos container.

**Managed SWA transport:** every client, operator and worker must send its actual
customer-broker API access token as
`X-Bloomstep-Authorization: Bearer <token>`. The API reads **only** that header:
no fallback to `Authorization`, `X-MS-CLIENT-PRINCIPAL`, forwarded platform
claims or resource-tenant identity. Managed SWA can overwrite Authorization
([Azure team's confirmation](https://github.com/Azure/static-web-apps/issues/34));
an invalid platform token is not a reason to relax issuer/audience verification.
The custom header changes transport only; strict JWT signature/issuer/audience/
expiry/scope/role checks are unchanged. Missing/malformed custom bearer returns
401 when configured; unprovisioned service remains 503. Cross-origin callers
must explicitly permit this header in owner-controlled CORS configuration.

`GET /api/sync` retains `{habits,checkins,reflections,voice,settings}`.
`POST /api/sync` retains the strict existing six arrays and returns those five
arrays plus `acknowledgedEvents: [clientEventId,...]`. `settings` still defaults
to `[]` for old clients. Only reducedMotion, reminderMinute, quietStart, quietEnd,
fewerReminders, weeklyLast, and ratingPromptedAt can sync; consent, notification enablement, and startup cannot
be enabled remotely. Existing field validation and deterministic microsecond/
equal-version recipe and setting ties remain unchanged. Attained stage takes
the maximum independently of the winning recipe. Check-ins, reflections, voice
and telemetry are immutable by per-account client ID: altered retries cannot
overwrite records or increment account record counts.

Cadence settings weeklyLast/ratingPromptedAt accept strict UTC ISO timestamps
ending in `Z`, at most six fractional digits and at most five minutes ahead.
Setting values have a 40-character overall ceiling; boolean and minute settings
retain their key-specific validation, not generic long strings.

Incoming telemetry preserves `{id,name,ts}` and permits optional
`schemaVersion:1` and `properties:{...}`. All ten legacy event envelopes remain
accepted. The versioned 48-event registry is `shared/event-registry.json`, not
a free-text name/map contract (see foundation section below). Unknown fields/names and
private text are rejected, not stripped. Telemetry timestamps must also be
within the server's raw-retention window and no more than five minutes ahead.
Voice text is intentionally private feedback, not telemetry; client-supplied
account identity/status/replies remain invalid. JSON requests are capped at
512 KiB.
Rating voice records require an integer score 1–5 but permit an empty/whitespace
body after trimming; optional text is at most 2000 characters. All other feedback
kinds still require nonempty trimmed text. A private rating submission never
automatically creates a telemetry event or publishes its score in metrics.

## Metrics response

`GET /api/team/metrics?days=7`, with integer days 1–30 (default 7), returns:

```json
{
  "startDay": "2026-08-26",
  "endDay": "2026-09-01",
  "minimumCohort": 50,
  "daily": [{"day":"2026-08-26","suppressed":true,"users":null,"counts":null}],
  "categories": {
    "activationRetention": {
      "signins":null,"recipesCreated":null,"checkins":null,
      "graduations":null,"returningCheckinUsers":null
    },
    "reminderLearning": {"remindersSent":null,"reflections":null,"weeklyReflections":null},
    "voiceRatings": {"feedbackSubmitted":null,"ratingPrompts":null,"ratings":null},
    "sharingExperiment": {"sharesInitiated":null,"experiments":null}
  },
  "limitations": ["..."]
}
```

The example elides the other six daily rows, explanatory strings, and the new
`dashboards` object described below. Days are
UTC inclusive dates, including the current partial day. The endpoint computes
deterministic **daily aggregates on demand** from existing accepted event
envelopes, deduplicated by account/client ID. The explicit internal worker also
persists bounded daily snapshots, but metrics always recomputes from live,
deletion-filtered raw envelopes rather than serving a stale snapshot.
Malformed envelopes are excluded; conflicting duplicate envelopes for one key
are excluded rather than selecting a winner based on database result order.
Private garden, feedback text and rating records are never aggregation inputs.
Neither account hashes nor raw IDs/events are returned.

Each day needs at least 50 distinct opted-in contributing users. Within a
publishable day, each event count also needs 50 distinct contributors to
that event; absent/smaller/future-unobservable counts are null, never fabricated
zeroes. Category totals are null if any constituent daily
count is suppressed; they do not silently sum partial/suppressed periods.
Returning check-in users means distinct users with check-in events on at least
two UTC days inside the requested window; it is suppressed below 50. It is not
D7/D30 retention. The `ratings` compatibility category now counts registered
`rated` events only at the publishable threshold; it does not expose private
voice scores. Experiment summaries remain disabled/unavailable. The
ratingPrompts count measures prompts, not submissions or scores; weeklyReflections
counts the new typed weekly_reflection event. A reminder_sent event is not
proof of OS delivery, effectiveness or notification consent health.

Only the existing client opt-in outbox sends telemetry; the backend cannot prove
an envelope represents device consent because the current wire contract has no
consent receipt. It never reconstructs analytics from private synced activity,
enables consent remotely, or invents rating/experiment/acquisition outcomes.
Consent withdrawal/queued-event clearing still needs client integration
verification. All metrics depend on an opted-in sample, not the entire population.

The bounded event scan happens before the account/tombstone scan. Deleted or
missing account gates are excluded, including deletion that wins during the
event scan. There is no cross-partition atomic snapshot: deletion immediately
after the gate scan may affect the next read instead. Raw rows are deleted by
the account deletion drain. Deletion invalidates all persisted snapshots using
the generation gate, as described below.

## Private feedback loop and audits

- `GET /api/team/feedback?limit=20&cursor=...` returns
  `{feedback:[{userId,record}],nextCursor:string|null}`. Limit is 1–20, default
  20. A bounded keyset cursor encodes the last scanned account/document ID;
  it conveys no authorization and is strictly validated (maximum 256 chars).
  Sort order is account then document ID, not recency. Empty pages may still
  have a cursor when deleted/orphaned accounts were skipped. Keep following
  `nextCursor` until null. This is a live listing, not a snapshot; records
  inserted before the current cursor appear on a fresh listing.
- `POST /api/team/feedback/{userId}` accepts the existing strict
  `{id,status,reply}` and an optional UUID `requestId`. Statuses remain
  received, under review, planned, in progress, shipped, not planned. Reply
  text is required, trimmed, 1–2000 characters (including a reason when
  declining). It returns `{updated:true}`. Unknown fields are rejected.
- Status, appended private reply and reply audit are committed in one
  same-user-partition transactional batch together with an ETag-conditional
  account gate. A deletion winning before commit or a competing thread update
  returns 409 without a reply/audit side effect. An already deleted/missing
  gate returns 410; a missing thread under an active account returns 404.
- The reply history remains the client's JSON-encoded string array:
  `["ISO-UTC-time: private team reply", ...]`. There are at most 20 replies.
  Internal bounded request-ID/digest receipts are stored outside `record`,
  never surfaced in garden or operator responses. Repeating a requestId with
  the same payload is a no-op; changed payload with that ID returns 409.
  Legacy identical consecutive status/reply retries are coalesced, but cannot
  guarantee arbitrary delayed-retry idempotency after intervening replies.
  New operator integrations should retain one requestId across retries.
- Re-syncing the original customer feedback cannot reset team status/replies.
  The next customer sync returns the private updated thread.

Feedback and metrics **read attempts are audited before querying/disclosing
data**, failing closed if the budget or audit write fails. Read audit records
contain action, hashed actor and server UTC time, not tokens, query text, private
feedback, telemetry bodies or habit fields. They reside in the reserved
`__preview_budget` partition and expire after 30 days. They are security records,
not opted-in product analytics; retention/disclosure of hashed operator identity
needs owner privacy review. Read attempts do not log every returned target ID.
Reply audits contain hashed actor, target feedback ID/action/time (no reply
text), live in the target partition and are removed with account data deletion.
No admin audit is written to application logs with private request material.

## Finite preview ceilings and kill switches

Fixed, conservative source limits (not client- or request-configurable):

| Bound | Ceiling |
| --- | --- |
| Global reservations/day | 2,000 |
| Global lifetime reservations | 20,000 |
| New global lifetime document reservations | 10,000 |
| New global lifetime account gates | 200 |
| Metrics reads | 12/day, 120 lifetime |
| Feedback reads | 60/day, 600 lifetime |
| Feedback replies/attempts | 60/day, 600 lifetime |
| Aggregate worker attempts | 2/day, 60 lifetime |
| Per-account requests | 30/minute |
| Per-account stored habits/check-ins/reflections/voice/settings | 100 / 1,000 / 100 / 100 / 7 |
| Per-account lifetime telemetry records | 3,000 |
| Per-account new telemetry/day (server ingestion UTC day) | 30 |
| Replies/thread | 20 |
| Feedback page | 20 records |
| Garden read | 1,307 records, then fail closed |
| Metrics scan | 10,000 event rows and 200 account gates, then fail closed |
| Persisted aggregate snapshots | 30 daily documents, 30-day TTL |

Global budget reservations update a single non-expiring ETag-conditional ledger
at `__preview_budget/budget` before writes/read scans. Each admitted garden
request, mutation/account creation, read audit, and reply attempt/commit reserves
budget; one HTTP request may consume multiple reservations. Records reserved
include new account gates, garden/event documents and audits; the singleton
budget ledger and one permanent aggregate generation gate are not themselves
counted. Retries/no-op sync still consume request
volume but not immutable account record counts. Failed operations can consume
reservations; those are intentionally not refunded. Concurrent reservations
fail closed (429), rather than guessing or exceeding a bound.

Per-account count increments share the record-create transaction/account gate
ETag, preventing concurrent writes from exceeding record ceilings. Existing
garden arrays form a baseline for old gates; existing telemetry is bootstrapped
once with a bounded partition scan before its first new record. Oversized legacy
gardens/metrics fail explicitly, never silently return partial counts.

Raw events expire at event timestamp plus the existing 34,214,400-second window
(396 days, approximately 13 months), using the remaining TTL at ingestion.
Old queued envelopes beyond retention are rejected (400), not re-retained.
Audit/snapshot TTL is 30 days; private garden/tombstone/budget/generation
documents do not expire.
Neither TTL nor deletion resets lifetime budgets/counters, so a preview cannot
silently keep admitting new records forever. A source-reviewed operator change
is required once a lifetime cap is reached; never reset/delete the ledger merely
to make retries pass. The ledger starts with reservations from this version:
existing deployment usage is not automatically globally censused.

Environment controls (read by handlers, not supplied through API payloads):

- `BLOOMSTEP_ENGAGEMENT_DISABLED=true` (or `1`) returns 503 for both admin
  endpoints and sync payloads containing voice/events. Pure garden/settings
  sync and account deletion remain available. Mixed batches are rejected before
  any garden write, so engagement is not silently dropped/acknowledged.
- `BLOOMSTEP_API_DISABLED=true` (or `1`) returns 503 for all garden and admin
  work before database access, after strict authentication. Existing-account
  `DELETE /api/account` remains available with
  `x-confirm-delete: delete-my-garden`. Cleanup preserves the permanent tombstone
  and drains bounded partition pages; retries can finish a failed cleanup.
- `BLOOMSTEP_AGGREGATES_DISABLED=true` (or `1`) stops only the internal aggregate
  writer endpoint; metrics, garden and feedback behavior is unchanged.

All three switches default unset/off, with case-insensitive `true` or `1`
enabling the switch. **There are no quota environment override keys.** Limits
are reviewed source constants; the injected smaller limits in tests are not
production request/environment overrides.

Caps return 429; conflicts return 409 and are safe to retry with immutable IDs.
Partial multi-record sync may have committed earlier records before a later cap/
conflict; no whole-batch atomicity is claimed. Request retries must reuse IDs.
Audit/storage failure yields an error, never an unaudited successful read. Success
and errors carry `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`.

These are volume/growth controls, **not a hard Azure monetary or RU spending
cap**. Read queries, JWT/network traffic, failed writes, TTL cleanup and deletion
also cost resources. Existing host concurrency limits remain; the platform
throughput/free-tier configuration, abuse protection and ability to turn off the
app externally still require live owner verification.

## Required integration-owner wiring and evidence

**Runtime route correction:** Azure Functions
[`ScriptHost.ValidateHttpFunction`](https://github.com/Azure/azure-functions-host/blob/dev/src/WebJobs.Script/Host/ScriptHost.cs)
rejects custom route strings that, after trimming `/`, start with `admin` or
`runtime` (case-insensitive). This checks the trigger's route itself, regardless
of the host's `api` prefix. The old `admin/feedback` and `admin/metrics` templates
were therefore invalid and could fail indexing despite a green deployment.
They are replaced with **team/feedback** and **team/metrics**, retaining strict
Admin role checks and response schemas. No invalid admin aliases, proxy, health
bypass, or permissive auth endpoint is added.

Owner caller changes: GET `/api/team/metrics`; GET
`/api/team/feedback?limit=20&cursor=...`; POST
`/api/team/feedback/{userId}`. Update operator console references and deployment
smoke expectations outside this workstream. `/api/sync`, `/api/account` and
`/api/internal/aggregates` are unchanged. `registration.test.mjs` imports the real
ESM package entrypoint, captures actual app.http registrations, checks all five
route templates against the host reserved-prefix rule and exercises guarded
missing-configuration 503 responses. This is entrypoint/registration evidence,
**not** an actual Azure host, broker JWT or Cosmos test. Live owner redeployment
must observe a configured no-token 401 (not 404) on the new team paths and review
host indexing logs; actual role-protected access still requires a real token.
All caller token headers must simultaneously change to
`X-Bloomstep-Authorization`. Owner deployment CI smoke should independently
request served `/api/sync`, `/api/team/feedback`, `/api/team/metrics`, and POST
`/api/internal/aggregates` with no custom bearer and assert 401 rather than 404.
Also send only a synthetic Authorization/platform-principal header and confirm
it cannot authenticate; an invalid custom token must likewise return 401.
Never place real tokens in logs or treat these rejection smokes as successful
live customer/admin/worker JWT authorization evidence.

1. Deploy the API modules/registered `adminMetrics` route in the intended personal
   free-tier environment. Preserve strict identity settings and explicit operator
   role assignment; exercise real customer-denied/admin-allowed JWT requests.
2. Verify Cosmos partition key `/userId`, enabled item TTL (container default TTL
   `-1` allows the event/audit per-item TTLs), no automatic paid scaling, and
   transaction support. The feedback keyset query needs a composite index with
   `/userId` ascending, then `/id` ascending. No cloud/index configuration is
   changed here. Verify this query and 409/412 behavior on real Cosmos.
3. Review existing account/document volume and initialize a conservative ledger
   baseline including existing deployment usage if migrating. Inspect persisted
   budget counters; do not erase lifetime limits. Verify TTL expiry and the kill
   switches with real app settings/restart propagation, plus external stop/abuse
   controls and free-tier accounting.
4. The existing website can consume `{feedback}` and render the metrics JSON,
   but presently does not follow `nextCursor` or send `requestId`. Wire pagination
   and retained retry IDs in the owner's UI workstream. No four polished/live
   dashboards are delivered here; registered event taxonomy is not proof that
   website/install/OS/native events are actually collected. Experiment remains
   disabled pending meaningful observed guardrails, not schema bypasses.
5. Verify real customer submit → audited operator read → private status/reply →
   customer sync and deletion/reply races. Exercise older queued-event rejection,
   quota errors, offline retries and opt-out queue clearing on the actual client.
   Sparse previews intentionally display null metrics at the 50-user minimum.
6. Run `npm --prefix api run check` and `npm --prefix api test`. The suite retains
   the original eight tests and adds deterministic in-memory Cosmos-style
   ETag/batch, privacy, quota, pagination, kill-switch, feedback round-trip and
   sync-compatibility regressions. These tests are source-contract evidence,
   not a substitute for live identity/database/client verification.

## Versioned single-source telemetry foundation

`shared/event-registry.json` version 1 contains 48 event definitions and per-event
property associations. `node tool/generate_event_registry.mjs` deterministically
produces:

- `api/src/event_registry.g.mjs`: self-contained registry and draft-2020-12
  `eventJsonSchema`. The deployed API does **not** load a root/shared file.
- `api/src/event_registry.g.d.mts`: discriminated TypeScript `TelemetryEvent`,
  `EventName`, property rules and metadata types.
- `lib/core/event_registry.g.dart`: `eventRegistryVersion`, `eventNames`,
  validation data and `isValidEventProperties(name,properties)`.

`node tool/generate_event_registry.mjs --check` or
`npm --prefix api run registry:check` rejects drift without writing files.
The API test suite also executes this check; the integration owner wires it into
the existing CI workflow. Generated JSON Schema describes field shapes/formats;
the runtime Zod schema additionally enforces future skew and ingestion retention.
Numeric/UUID/date/enum bounds are authoritative in the shared file. Regeneration
is required for a registry change; never hand-edit generated outputs.

Registered names, grouped by source specification stage:

| Stage | Names |
| --- | --- |
| Acquisition/install | landing_view, invite_link_open, download_click, store_page_view, installer_started, install_completed, first_launch |
| Identity/activation | signin_view, signin_provider_selected, signin_succeeded, signin_failed, aspiration_selected, recipe_created, celebration_practiced, first_checkin |
| Habit/outcomes | checkin, comeback, recipe_doctor_applied, automaticity_score, reflection, weekly_reflection, habit_graduated |
| Referral/later revenue | share_initiated, invite_accepted, buddy_added, paywall_view, trial_start, purchase |
| Voice | feedback_submitted, rating_prompted, rating_prompt_shown, rated, review_responded |
| Reminders | reminder_sent, notif_sent, notif_delivered, notif_opened, notif_actioned, notif_dismissed, notif_disabled |
| Health | session_started, crash, app_hang, cold_start, sync_error, auth_error |
| Disabled experiment taxonomy | experiment_exposure |
| Explicit observed opt-in | analytics_consent |

Future Store, buddy, revenue and experiment entries have `observable:false`;
their presence never enables those features or publishes their measurements.
Every property is optional so old envelopes and honestly incomplete observations
remain representable; absent properties **do not** make property-dependent
metrics available.

Allowed property definitions (only the associated event's subset is accepted):

- `platform`: windows/macOS represented as `macos`/linux/android/ios/web;
  `channel`: website/invite/store/direct/unknown/link/email. Link/email denote
  actually observed share choices, not inferred acquisition attribution.
- `templateCategory`: calm/focus/health/learning/connection, only on
  recipe_created for an actually chosen fixed starter template; omit for custom
  text. weekly_reflection may include the actually selected recipe UUID habitId.
- `provider`: email/google/microsoft; signin failure `reason`:
  cancelled/network/provider/invalid_token/configuration/unknown.
- `habitId`, `sessionId`, `notificationId`, `feedbackId`: UUID only;
  `localDay`: valid ISO local date `YYYY-MM-DD`.
- `result`: did/didMore/notToday/undo; `latencyMs`: finite 0–86,400,000;
  `score`: finite 1–7; `rating`: integer 1–5.
- `kind`: existing six private-feedback kinds (enum only, not body text).
- Notification `action`: did/snooze/fewer/off/open.
- `errorKind`: network/authentication/conflict/quota/validation/unavailable/unknown.
- `experiment`: reminder_copy_v1; `variant`: control/gentle.

Example:

```json
{
  "id":"a41d0a72-2fb9-47ac-9b19-ffca7b50b4de",
  "name":"checkin",
  "ts":"2026-09-01T12:00:00.000001Z",
  "schemaVersion":1,
  "properties":{
    "habitId":"b78d1b89-2f18-438e-a378-5240ecba96ee",
    "localDay":"2026-09-01",
    "result":"did",
    "platform":"windows"
  }
}
```

There is no habit/aspiration/feedback/error text, email, URL, account ID, arbitrary
experiment name or arbitrary enum value. `latencyMs` is event-associated:
anchor-to-checkin when truly measured for checkin, cold-start/hang duration for
their health events; don't synthesize it from tap time or guessed anchors.
Health events in this optional telemetry pipeline do not implement a separate
required security/diagnostic consent channel or complete crash capture.
The explicitly coordinated analytics_consent event records only an observed
opt-in transition, with optional fixed platform enum. It is not a remotely
mutable setting, verified consent receipt, or evidence of consent for other
events. No enabled boolean/off event/private fields are accepted. Native owner
must atomically enqueue it only after explicit opt-in and clear all telemetry
on opt-out; backend cannot enforce device observation or retract in-flight HTTP.

## Actual dashboard summary contracts

The existing `categories`, `daily`, `minimumCohort`, dates and limitations remain
at the metrics root. New `dashboards` contains registryVersion, minimumCohort,
startDay, endDay, observedThrough and the following four actual computed objects,
plus explicitly incomplete appHealth and disabled experiment metadata:

The compatibility root `daily` still includes today's partial raw-event counts.
The new `dashboards` dates instead cover the requested number of **completed**
UTC days ending yesterday: for example `days=7` on September 1 has root August
26–September 1 but dashboards August 25–31, with observedThrough September 1.
This avoids presenting unfinished-day conversion denominators as complete.

1. **funnel**: `stages[eventName]:{users,suppressed}`,
   `visitToDownload`, `downloadToLaunch`, `launchToSignin`, `sameDayActivation`
   each `{eligibleUsers,convertedUsers,rate,suppressed}`; `breakdowns` contains
   publishable signin `channel`/`platform` cohorts with the same activation
   fields. Conversions join the **same authenticated account**, ordered event
   times (microseconds preserved), inside the requested window. Same-day first
   did/didMore checkin matches signin localDay (UTC date fallback when omitted).
   No anonymous website/download-to-broker linkage is invented. Missing source
   events yield null conversions, not a ready end-to-end acquisition funnel.
2. **retention**: `cohortStartDay` is dashboard startDay minus 30,
   `cohortEndDay` is dashboard endDay, and `cohorts[]` contains
   `{cohortDay,cohortUsers,suppressed,d1,d7,d30}`. Each offset contains
   `{targetDay,matured,eligibleUsers,practicingUsers,rate,suppressed}`.
   Cohort is the earliest observed explicit `first_checkin` with localDay and
   result did/didMore for that account; practice is an effective typed checkin did/didMore
   on **exact local date +1/+7/+30**, not rolling/window retention.
   `matured` means targetDay is earlier than the UTC `observedThrough` cutoff.
   Native timezone/delivery completeness cannot be proven by this rule:
   late/offline events revise results on backfill. No first-checkin/result/date
   yields no inferred cohort. Metrics scans an extra 30 lookback days; this is a
   bounded observed-event cohort, not an unlimited historical census. Including
   the earlier cohort dates makes matured D30 observable even for a short recent
   reporting window. The raw
   metrics scan includes one additional day to cover the completed-day window.
   Effective practice selects the latest microsecond/UUID-ordered result for
   account/habit/localDay, including undo/notToday corrections. Missing habit IDs
   form one unidentified account/day stream, not invented separate habits.
3. **outcomes**: `daily[]` contains
   `{day,suppressed,scoreUsers,medianAutomaticity,practicingUsers,
   graduatedUsers,graduationCount}`. Score is median latest numeric 1–7
   automaticity_score/reflection score **per contributing user per UTC day**;
   equal-time ties use immutable UUID ordering. Practicing users use effective
   explicit did/didMore results grouped by reported local day (not timestamp
   date); graduation counts require 50 distinct contributing
   users. These are optional-sample trends, not clinically validated scores or
   all-user north-star rates.
4. **reminderHealth**: `sentUsers`, `deliveredUsers`, `openedUsers`,
   `dismissedUsers`, `actionRate` and `disableRate` plus definition.
   Rate objects use `{eligibleUsers,convertedUsers,rate,suppressed}`.
   Action rate is user-level observed delivered→actioned matching the same
   account/notification UUID in temporal order. Disable rate is sent users with
   a notif_disabled observation in the window. Scheduling/sending does not prove
   OS delivery; do not emit delivered without real evidence.

All measured denominators **and numerators** need at least 50 distinct users.
Unobserved, sparse, future or immature measurements are null, not zero. This
intentionally suppresses zero-success/rare-negative rates; suppression is not
evidence of success. No private synced habits/ratings are substituted for missing
opted-in telemetry. AppHealth leaves `crashFreeRate:null` because absent crash
events cannot prove complete capture. `experiment.enabled:false` remains fixed.

## Dedicated persisted daily aggregate worker

`POST /api/internal/aggregates` requires either a primary customer-broker
**Bloomstep.Admin** token for manual runs or a separately validated personal
resource-tenant worker API token with **Bloomstep.AggregateWriter** role.
Worker tokens cannot sync/read/delete gardens, read/reply feedback or
read team metrics; those routes accept only the primary broker issuer and never
invoke the alternate verifier. Owner provisions the separate real worker app/service
principal/FIC and its resource API app-role assignment; resource-tenant ownership is not
authorization. No client secret, cloud mutation or workflow is supplied here.

Body is strict, bounded, with **no** unknown fields:

```json
{"endDay":"2026-09-01","days":7}
```

`endDay` defaults to yesterday UTC; `days` defaults to 1 and is integer 1–30.
Every requested date must be inside the previous 30 completed UTC days: current/
future dates and ranges older than that reject with 400. `{}` runs yesterday.
Response:

```json
{
  "registryVersion":1,
  "snapshots":[
    {"day":"2026-09-01","digest":"<SHA-256 of deterministic record>","updated":true}
  ],
  "experimentEnabled":false
}
```

Snapshots live in the **same** free `bloomstep/data` container, partition
`__daily_aggregates`, type `aggregate`, IDs `daily:YYYY-MM-DD`. Stored fields:
day, registryVersion, digest, record, TTL 30 days. Record contains that day's
compatibility aggregate plus that day's dashboards with retention cohorts from
day-30 through day, evaluated only through that completed day. No contributing account/event/habit/notification IDs
or private text are persisted. Maximum 30 daily documents; old dates are pruned.
This deliberately differs from indefinite historical aggregate retention:
storage/growth is bounded and extended retention needs a reviewed budget design.

The worker audits its attempt before scanning, reserves the existing global
budgets plus dedicated **2/day, 60-lifetime** aggregate action limits, and scans
at most 10,000 raw events/200 gates (up to 60 UTC days for a 30-day backfill plus
retention lookback). It rejects overflow instead of persisting partial results.
Identical raw data yields identical digests; unchanged retries do not rewrite
snapshot documents or consume new-snapshot record reservations, but still
consume attempt/audit/request budgets. Late envelopes change digests when
explicitly backfilled; no recurring job is created by this change.

A non-expiring `generation` document in that partition is an ETag gate captured
**before** raw scans. Snapshot writes/replaces/pruning and generation advancement
share one bounded transactional batch. Concurrent workers or deletion changes
return 409, never silently last-write-wins. Deletion first tombstones the customer
gate, then invalidates **all** snapshots with the aggregate generation gate,
then drains raw account data. It must succeed or return an error for retry;
budget caps/kill switches do not block this existing-account cleanup.
An in-flight pre-deletion writer loses its captured generation ETag; a later
writer excludes the tombstone. Global invalidation is intentionally coarse
rather than persisting private contributor lists. Worker can rebuild snapshots
from active accounts. No cross-partition instantaneous read snapshot is claimed.

### Owner integration and remaining gates

- Register enabled **application-member** API role `Bloomstep.AggregateWriter`
  on the **personal resource-tenant worker API app**, explicitly assign the
  dedicated worker service principal and configure its workload FIC. Never use
  a corporate tenant. Do not enable/request customer client_credentials: the
  [External ID M2M flow is a paid add-on](https://learn.microsoft.com/en-us/entra/external-id/external-identities-pricing),
  not the basic customer-user allowance.
  Pin all three optional worker settings:
  `AGGREGATE_OIDC_ISSUER` = exact personal resource-tenant discovery issuer,
  `AGGREGATE_OIDC_AUDIENCE` = worker resource API audience,
  `AGGREGATE_OIDC_JWKS_URI` = that tenant's HTTPS JWKS URI.
  The worker token must match these exact settings, RS256 and required
  sub/iss/exp/iat, plus explicit `roles:["Bloomstep.AggregateWriter"]`.
  Resource-tenant Admin/owner alone is rejected; arbitrary alternate issuer or
  audience is rejected. All three settings default absent: worker auth fails
  closed (503 if custom token supplied and primary verification fails), while
  a valid primary customer Admin still aggregates manually. Missing custom bearer
  always returns 401 on the internal route. No worker scope or role is accepted
  globally and there is no Authorization/platform-claim fallback.
  Human Admin role is separately assigned to the actual customer user object,
  not inferred through email or resource-subscription ownership.
- Customer/native/team use configured customer broker discovery's exact
  issuer/JWKS/token endpoint, never upstream Google/MSA or workforce common.
  Only the explicit internal worker uses pinned personal resource-tenant
  discovery/token endpoint; never `common` or an unconfigured tenant.
- Run generation drift check in existing CI; deploy the self-contained API,
  verify resource app-only token claims/RS256 and worker-denied garden/team endpoints.
- Preserve `/userId`, item TTL and existing default/composite index. No additional
  composite index is required for snapshot partition queries; verify actual
  worker batch operations, TTL, conflict behavior and deletion cleanup live.
- Existing ledger may lack `actions.aggregates_write`; runtime initializes this
  action's day/daily/lifetime lazily while preserving all existing counters.
  Retain the owner's conservative fresh baseline; no automatic migration/reset.
- Owner wires explicit scheduled POST through real FIC authentication, retries
  409 safely, observes 429/503 without resetting budgets, and handles optional
  bounded backfill. Existing console can continue using root categories and add
  new dashboards; no website/workflow edit is part of this workstream.
- Source registry is taxonomy/validation, not collection evidence. Anonymous
  landing/download/installer attribution cannot join broker accounts with this
  current authenticated-only pipeline. OS notification health and complete
  diagnostic capture remain evidence gates. Native serialization/instrumentation
  is coordinated separately; actual JWT/Cosmos/client round trips remain
  integration tests, not fabricated users or inferred production dashboards.
