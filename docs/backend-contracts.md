# Bounded backend telemetry and engagement contracts

## Private support receipts and response measurement (schema1)

This is service-operational metadata on existing private feedback/rating
documents, **not opt-in product-event analytics** or native crash collection.
No new route, role, public feedback feed or client-editable field is introduced.
New voice creation commits outer `support` metadata atomically with the account
gate and voice document:

```json
{"schemaVersion":1,"receivedAt":"2026-09-01T12:00:00.000Z","firstRespondedAt":null}
```

`receivedAt` is server UTC captured for the successfully committed creation,
not the client timestamp or exact Cosmos commit instant. The first actual,
nonempty operator reply stamps `firstRespondedAt` in the existing
account/voice/audit CAS batch. Retries and later replies preserve both first
times; failed CAS does not persist them. It proves a committed private reply,
not customer-read, email, push or message delivery. Clock regression, invalid
provenance and a known first response without a stored reply are errors, never
clamped or repaired. An older compatible writer that already appended a reply
without stamping the first time leaves it unavailable, not "unanswered".

Owner-only GET/POST `/api/sync` adds `voiceReceipts` outside the unchanged native
`voice` row shape:

```json
[{"id":"00000000-0000-4000-8000-000000000001","schemaVersion":1,"receivedAt":"2026-09-01T12:00:00.000Z","firstRespondedAt":null}]
```

Legacy metadata is not backfilled from now, client timestamps or reply prefixes:
both times are null with `reason:"legacy_receipt_unavailable"`. Known receipt
but lost first-response provenance uses `reason:"first_response_unavailable"`.
Account/owner-record deletion removes the same-document metadata and suppresses
it from readback; deletion markers retain no receipt times or private text.
Existing clients may ignore the additive sidecar without merging new columns.

Selected real Admin GET `/api/team/metrics` adds `supportMetrics`, privately.
The metadata-only query returns owner/document IDs, kind, rating, support times
and a response-existence boolean after parsing the stored JSON array; malformed
JSON, non-array values, non-string replies or replies over2100 Unicode code
points yield invalid provenance, **never body or reply text**. It shares the exact10,000 scanned-row
budget and200-account cap with raw event scans, including removed/inactive rows
in scan accounting; caps fail429 without partial counts. One final owner/
deletion filtering snapshot after both raw scans excludes removed owners/
records from both projections; this is not cross-partition transactional
snapshot isolation. No consent-off feedback is joined into an
opt-in event cohort.

Receipt windows are completed UTC dates, at most30 days. Answered elapsed
median/maximum are descriptive only. Ratings of3 or less mature only *after*
receipt+48h; exactly-at-deadline remains open, exactly48h reply is timely.
Mature unanswered and late records remain in the denominator; immature records
are separate. Fractions/counts/subsets need50 distinct contributing owners,
not50 rows from one owner; suppressed values are null, not zero. Malformed,
conflicting or future server facts, or a recorded reply with missing first time,
make timing unavailable rather than publish partial success. Legacy coverage is
over all retained scanned feedback because its receipt window is unknowable.
There is no invented100% response target. The original13-goal panel stays
separate: neither this partial receipt cohort nor an answered median proves its
full-coverage48h goal. The <=2-business-day goal remains
`calendar_not_configured` until an explicit timezone/holiday calendar exists.

Native Settings JSON export fetches this sidecar through authenticated
read-only GETsync, with no merge, acknowledgment, upload or lastSync change.
It validates shape/UTC provenance/duplicates, filters local owner tombstones
and rejects changed identity/account generation. `serverSupportReceipts`
identifies the source and includes explicit historical unknown reasons.
Offline/old-service/malformed/unavailable components produce a JSON warning and
visible local-export warning, not a complete-server-export claim. Account
changes cancel saving even when an optional component failed. This source
requires dual native CI/future compatible candidate and a separately approved
customer upgrade/readback; no current installed preview is represented as
having this new export contract.

## Optional app reminder-preference observation (disclosure version 1)

This is a separate, unchecked Settings choice, even when existing product-event
analytics is enabled. Both choices are required. It observes only an explicit
post-consent app preference false-to-true transition after gateway initialization
succeeds. Startup restoration, retry, repeated enable, opting in while already
enabled, disposal, sign-out and account erasure never enroll or count as an
explicit disable. It does not read Windows permission, delivery, contacts,
location, private habit text or a lifetime notification census.

Three immutable event envelopes use required `disclosureVersion:1`,
random UUID `cohortId` and `consentEpoch`, `platform:"windows"` and `localDay`:
`reminder_preference_started`, `reminder_preference_disabled` and
`reminder_preference_followup`. Generated native/wire/type contracts share
required fields and the fixed Windows platform. General-purpose tracking cannot
manufacture these events. Local preference/state/event writes are transactional
and owner/generation guarded. An explicit true-to-false transition records one
linked disable; a still-enabled same-epoch persisted preference may record one
followup after exactly 30 elapsed days. Clock regression fails explicitly.
Missing followup, lost state or non-preference shutdown is unknown, never
inferred continued enablement.

Consent/episode settings remain device-local and appear in owner JSON export;
they cannot sync or opt another device in. Revoking either consent purges added
local state, queued observations and their sync fingerprints. Re-consent starts
a fresh epoch with no backfill. Already-sent requests cannot be recalled; synced
facts retain existing 13-month raw event retention/account deletion behavior.
No unconsented lifetime identifier or historical enablement marker is added.

Selected Admin `/api/team/metrics` adds `reminderPreferenceCohorts`, using the
existing shared 10,000-row scan/200-account caps and final account/deletion
filter. It selects the first observed episode per owner within retained bounded
input, not a lifetime-first claim. UTC windows select the dates when 30-day
horizons close; microseconds are preserved at boundaries. Duplicates coalesce;
conflicting or malformed observations make results unavailable. Missing
same-epoch followup makes the disable fraction unavailable. Counts and
contributing subsets require 50 distinct owners; a nonempty sub-50 outcome also
suppresses its parent total to prevent subtraction inference. The fraction
requires both disabled and confirmed-followup contributor groups of at least
50 owners and no unknown outcomes. Suppressed values stay null, never zero.
The private console labels this separately from the original goal.
Original full-coverage notification-disable <=10% stays `not_observable`;
this narrower sample supplies no OS-delivery or original-goal pass/fail claim.
Source readiness does not prove actual native/customer observation or genuine
30-day populations. Experiment remains OFF.

## Operational spending guard: isolated one-way pause

`POST /api/internal/operational-pause` uses **only** a separately pinned normal
resource-directory app token: `SPEND_GUARD_OIDC_ISSUER`,
`SPEND_GUARD_OIDC_AUDIENCE` (guard app GUID), `SPEND_GUARD_OIDC_JWKS_URI`.
RS256, issuer, audience, signature and sub/iat/exp are required; delegated `scp`
is forbidden and the sole app role must be `Bloomstep.SpendGuard`. There is no
customer/Admin or AggregateWriter alternate-verifier fallback. Customer/team/
garden routes still exclusively use primary customer JWT authentication.

Body exactly `{requestId:<UUID>,reason:<enum>}`; reason is
`paid_sku|spending_limit_off|positive_cost|configuration_unknown`. Response200:
`{paused:true,requestId,reason,pausedAt:<UTC ISO>}`. The single preview-budget ledger
row retains the first current pause and guard actor, conditional on its ETag.
Same request/reason is idempotent, changed reason under the same current request
ID409; already-paused new requests return the original receipt without growing
records. No arbitrary text/cost/error payload, disable:false or unpause action
is accepted. Pause intentionally bypasses exhausted normal counters so a safety
stop still works at the cap; it does not allocate new audit rows per run.

Paused ledger blocks new POST sync writes, team feedback/metrics, invitations
and referral reconciliation, while authenticated existing garden GET/export and
account deletion remain available. Existing environment kill-switch semantics
are independent. Internal aggregation and internal guard pause remain available
subject to existing worker quotas; application pause does not secretly elevate
machine access or disable privacy deletion. There is a cross-partition/in-flight
write race: checks at entry and before each sync batch reject observed pause,
but this is **not** an Azure spending hard cap or atomic global write barrier.

`POST /api/team/operational-resume` requires a **selected real customer**
Bloomstep.Admin plus Garden.ReadWrite, never SpendGuard/AggregateWriter.
Body exactly
`{requestId:<UUID>,reviewedPauseRequestId:<current pause UUID>,
confirmation:"reviewed-free-tier-and-spending-limit"}`. Response `{paused:false}`.
It conditionally clears only the reviewed current pause, records the authenticated
customer reviewer/time in the same ledger and allows at most10 lifetime resumes.
Wrong/stale review409, missing role403, incomplete confirmation400. Matching
retry is idempotent only while no newer pause exists. Guard workflow never calls
resume; this assertion is human review, not machine verification or blanket
authorization to spend. A future pause requires another explicit human review.

## Authenticated invitations and mutual cosmetic rewards (§8.2)

New routes all validate the **primary customer** broker JWT via
`X-Bloomstep-Authorization: Bearer <customer API access token>`, including exact
issuer/audience/signature/expiry, and specifically require delegated
`Garden.ReadWrite`. An Admin-only token without that scope is insufficient;
resource-directory AggregateWriter authentication is never used on these routes.
No staff privileges, email/name, SWA principal or subscription ownership confer
access. Responses are no-store. No anonymous invitation preview/identity lookup
or contact/email sending endpoint exists.

### Exact HTTP/native contracts

`POST /api/invitations`:

```json
{"requestId":"<UUID>","channel":"link"}
```

`channel` is exactly `link|email|qr|native`, merely the user's explicit sharing choice,
not a contact address or evidence that any message was sent. Response HTTP200:

```json
{
  "invitationId":"<same request UUID>",
  "token":"<43-character base64url cryptorandom 32-byte code>",
  "channel":"link",
  "expiresAt":"<server UTC ISO, creation +7 days>",
  "recipeCard":null
}
```

Default sharing includes **no habit text**. Optional `recipeCard` must be exactly:

```json
{
  "explicitChoice":true,
  "templateCategory":"calm",
  "aspiration":"Feel calmer",
  "anchor":"After tea",
  "behavior":"Take one breath",
  "celebration":"Smile",
  "species":"Fern"
}
```

All fields are required for a card. Taxonomy is
`calm|focus|health|learning|connection`; species `Cosmos|Sunflower|Fern`.
The four recipe strings are trimmed, nonempty and max200 characters each.
No habit IDs, progress, names, email, visibility, account fields or unknown
fields are accepted. This card is deliberately shared private recipe content,
not anonymous analytics: the UI must present the entire card for explicit
approval, and must not infer approval from a general sharing/analytics setting.
It does not create a friend's habit automatically.

`POST /api/invitations/redeem`:

```json
{"requestId":"<new persisted UUID>","token":"<opaque code>"}
```

Response HTTP200:

```json
{
  "invitationId":"<opaque invitation UUID>",
  "channel":"link",
  "acceptedAt":"<server UTC ISO>",
  "expiresAt":"<acceptance +30 days>",
  "recipeCard":null,
  "status":"accepted"
}
```

An explicitly shared card replaces null only while its original7-day code
window remains open. `status` can become `rewarded` on a later identical retry;
attribution/request/time never change. Inviter/recipient account IDs and existing
inviter identity are never returned. Each code accepts one friend; each account
can accept only one invitation lifetime, before prior observed positive practice.
Self invitation is rejected. Server-owned code reservation and receipts derive
inviter/channel/acceptance; callers cannot set them.

`GET /api/invitations/status` returns only the currently authenticated owner:

```json
{
  "invitations":[
    {
      "invitationId":"<opaque UUID>",
      "direction":"incoming",
      "channel":"link",
      "acceptedAt":"<server UTC ISO or null>",
      "expiresAt":"<UTC ISO>",
      "status":"accepted"
    }
  ],
  "rewards":[
    {"id":"<opaque owner-specific grant digest>","cosmetic":"rare_flower","grantedAt":"<server UTC ISO>"}
  ],
  "definition":"<cosmetic-only, two-partition durable-saga explanation>"
}
```

Invitation statuses are `created|accepted|rewarded|expired`; expired unaccepted
codes remain metadata only while the bounded receipt exists. Pending reward
preparation is not returned as an earned cosmetic. No account selector/cursor
query is accepted. `?export=true` additionally returns
`sharedRecipes:[{invitationId,expiresAt,recipeCard}]` for the owner's own explicitly
shared, still-valid cards; never someone else's code/recipe or raw token.
Native export should combine the unchanged `GET /api/sync` garden and this
owner-only referral export. It should not turn internal attribution into a
public contact list.

Native must persist request UUIDs before sending and retry the identical payload
after connection/409/500 failures. Create retries return the original valid code;
changed payload reuse returns409, expired/TTL-removed code retries cannot allocate
replacement tokens (410/409). Redemption retries resume the same acceptance;
different request/code or a previously used account returns409. Unknown JSON,
noncanonical tokens and self invitation return400; invalid/expired/deleted code
or participant returns410; missing scope403; real JWT failure401; preview caps429;
disabled service503. No registration/source test is a live identity acceptance
claim.

### First-practice qualification and durable saga

Only a schema-validated, owned **garden check-in** stored through normal sync with
`result:did|didMore` can qualify—not `first_checkin` telemetry, rest (`notToday`),
undo (`null`), client preferences, stages or forged cosmetics/proof fields.
The server attaches immutable `receivedAt/referralEligible` metadata internally;
client schemas reject those fields and sync responses retain the legacy lists.
Future-day check-ins never become qualifying merely as time passes. Earliest
effective positive check-in is selected with microsecond/UUID ordering, latest
result per habit/day winning. A positive followed by undo/rest in the same sync
does not trigger a grant. Already earned cosmetics are not punitive streaks and
are not revoked by a later ordinary undo.

An account-gated server first-practice marker and positive-seen latch prevent
retroactive attribution/racing acceptance after practice; conservative legacy
history with any prior positive also denies redemption. Qualifying check-in's
server receipt and client timestamp must not precede acceptance, and first
server-observed practice must occur inside the30-day acceptance window.
“Actual” here means the authenticated user's actual garden check-in record,
not proof/sensors verifying their real-world behavior or resistance to Sybil
accounts. The existing system is self-reported; no production anti-fraud claim.

Acceptance reserves the hashed code conditionally, then commits the invitee
receipt under the invitee's account ETag, then mirrors the inviter receipt under
their account ETag. Every retry checks both live account gates. The two cosmetic
grant IDs are deterministic but **owner-specific** (not a shared lifetime join
key), first prepared pending then settled under each owner gate after both
preparations exist. Repeated sync/status/redemption repairs interrupted work
without duplicate grants. Pending grants are not displayed as earned.
This is a durable **bounded retry saga**, not a cross-partition transaction.
One side can settle before an interruption; native must retry and show failure/
pending rather than promise instantaneous mutual completion. Recovery must occur
while the30-day receipts exist; there is no unprovisioned background reconciler
or guarantee of convergence after all recovery metadata expires.

### Quotas, privacy TTL, deletion and UX

- Max10 created invitations lifetime/account, max2/day/account; one accepted
  invitation lifetime/account. UUID/digest immutability markers are bounded10.
- Max11 owner receipts/reward records (ten inviter grants plus one invited grant).
  Existing global200 accounts,10000 lifetime records,2000 daily/20000 lifetime
  operations and30 requests/minute/account apply. Expiry/deletion do not recycle
  lifetime grant/invitation/global allocations.
- Codes and optional card secrets expire at7 days; lookup stores only token hash,
  bounded attribution and absolute expiry, never card/text/raw bearer token.
  Unaccepted metadata lasts30 days; accepted reciprocal identity/attribution
  receipts expire30 days after acceptance. Updates use remaining TTL, not rolling
  extension. Pending grants expire with receipt recovery window.
  The existing Cosmos container must have item TTL enabled (for example,
  `defaultTtl:-1`); per-document `ttl` does not enable container TTL by itself.
  Owner must verify this existing-container setting and deletion/expiry behavior.
  Absolute `expiresAt` checks enforce API expiry even before asynchronous Cosmos
  TTL cleanup, but source tests are not evidence of deployed physical erasure.
- Settled owner-only cosmetic records last until account deletion and contain
  neither counterpart IDs nor shared invitation hashes/IDs; public grant IDs
  are opaque owner-specific digests. First-practice marker holds only the owner's
  check-in ID. There is no referral text/token/identity analytics or new telemetry
  registry field, web/install linkage, contacts discovery or email service.
- Account deletion first tombstones the owner, clears gate metadata, then removes
  hashed code lookups and still-retained reciprocal receipts/related grants using
  conditional peer-account gates, then drains all owner data. Partial deletion
  is retryable; concurrent grants fail their gates or are purged on reconciliation.
  Bounded privacy cleanup bypasses exhausted engagement ledger, like account
  deletion, so the cap does not block removal. Counterpart cosmetics linked by
  current receipts are removed conservatively; after attribution TTL expires,
  unlinked earned cosmetics carry no recoverable counterpart relation.
- `BLOOMSTEP_INVITATIONS_DISABLED=true|1` pauses create/redeem/status and grant
  reconciliation during sync. Existing API/engagement switches also apply;
  garden-only sync and account deletion retain their existing availability rules.
  The first-practice eligibility latch can still record garden practice while
  rewards are paused, preventing retroactive attribution after re-enablement.

Required native privacy copy:
“Share a tiny invitation—not your name, email or habit. We do not contact anyone.”
For optional cards: “Share this recipe card? Your friend will see the aspiration,
anchor, behavior and celebration shown here. Nothing is shared unless you choose.”
Reward copy: “After your friend's first completed tiny practice, you both earn a
rare flower. It is cosmetic only: no money, progress multiplier or streak pressure.”
Codes are bearer capabilities. The owner-selected native link contract is
`https://<API_ORIGIN-host>/?invite=<code>&channel=<link|email|qr|native>` and
`bloomstep://invite?code=<code>&channel=<link|email|qr|native>`. The native inbox
preserves only this opaque intent across sign-in/restart; no account/habit text
is included by default. Query-string codes can appear in browser history,
hosting/access logs and referrers; the owner must redact/exclude them, use
no-referrer on invitation landing pages and remove the query after safely
capturing the intent. Never put codes into analytics or send them to third-party
origins. Send code only in authenticated redemption JSON, and never automatically
opt anyone into analytics or upload contacts. Native invitation screens/deep links/import/rendering
are owner follow-up work, not implemented by this backend job.

## Persisted daily worker → operator dashboard

`GET /api/team/metrics?days=1..30` retains strict customer `Bloomstep.Admin`,
audit-before-disclosure, lifetime/daily read budgets and engagement/API kill
switches. Existing top-level `daily`, `categories` and `dashboards` remain bounded
**on-demand raw-event** calculations: compatibility includes today; typed
dashboards use completed days. The console labels these separately.

The additive `goalMetrics` has schemaVersion1 and source
`on_demand_target_aligned`, separate from persisted snapshot records. It
publishes original goals and privacy-suppressed observed values, numerator,
denominator, unit/comparison, reason, completed window and opt-in coverage.
Target-aligned D7/D30 frequency and30/60/90 graduation definitions are in
`docs/measurement.md`; raw history includes an additional90 days without
raising the10,000-row/200-account ceilings. Over-cap reads fail429, never
silently truncate. No account/habit/event IDs escape this projection.
Unobservable notification-start/delivery/SLA/native-census goals stay null,
not replaced with current approximate panels. Legacy daily worker records
and their strict schema remain unchanged.

The daily-series envelope additionally reports `schedule` with declared cron
`20 2 * * *`, UTC latest-day due timestamp, `latestTickDue`, backfillMaxDays30
and explicit non-SLA definition. Entries expose `scheduledAt` plus
`generationOffsetSeconds` (signed; null if unavailable). Offset describes
stored generation versus declared due time, not invocation event type or
the availability of a freshly complete population.

The additive `dailySnapshots` is the actual persisted daily-worker read path:
`{source:"persisted_daily_worker",startDay,endDay,definition,days:[...]}`. It
enumerates requested completed UTC days through yesterday, ascending, maximum30.
Each available entry has `day`, `status:"available"`, `reason:null`, `generatedAt`
(UTC ISO), `registryVersion:1`,
`suppression:{minimumCohort:50,dailySuppressed:boolean}`, and `record`.
`record` contains single-day `startDay/endDay/minimumCohort/daily/categories/
limitations` plus typed `dashboards` (funnel, retention, outcomes, reminderHealth,
appHealth, disabled experiment). No window cohort is derived by combining days.

`snapshot-contracts.mjs` strictly validates every nested object, fixed registry
event names/breakdown enums, literal approved definitions, UTC-day alignment,
bounded arrays, null-or-publishable counts (minimum50), bounded rates/scores and
unavailable diagnostics. Unknown/private fields fail validation and are never
echoed. No account/event IDs or internal generation/digest/ETag are returned.

Unavailable entries have `status:"unavailable"`, a reason, and
`record/generatedAt/registryVersion/suppression:null`:
- `not_generated`: missing run/day; never zero or raw-data fallback.
- `stale_generation`: missing/mismatched current deletion-generation gate.
- `generation_changed`: gate ETag changed during reading; suppress the series.
- `invalid_snapshot`: missing/legacy metadata, future/same-day generation time,
  invalid registry/schema/day, duplicate daily keys or deterministic digest.

An available sparse snapshot has real generation metadata but null suppressed
counts/rates/medians, distinctly different from an unscheduled day. Older dates
are independent historical records, not substitutes for a missing latest day.
Late/offline arrivals require explicit bounded worker backfill; console reads
never pretend the stored day was freshly recomputed.

Worker writes now persist `generatedAt`, registryVersion, stable generation and
digest. Unchanged retries preserve generation time and consume no new snapshot
records. Ordinary worker runs change transaction revision/ETag, not deletion
generation, so earlier valid days survive. Deletion atomically rotates generation
and deletes snapshots; in-flight worker writes conflict and changed-generation
metrics reads suppress stored data. Reads do not create a missing gate. Existing
pre-metadata snapshots stay unavailable until owner runs worker/backfill again;
there is no implicit fake run/migration. Existing30-record/30-day retention and
worker/lifetime quotas remain unchanged.

The console renders actual persisted latest-completed-day four typed panels,
per-day availability/generated-time history and stored records, separately from
on-demand and raw compatibility windows. It never sums daily unique users,
averages medians or combines retention cohorts to invent a window metric.
Integration fixtures prove persisted-value consumption independent of raw counts,
absence/range/stale generation, private/malformed rejection, sparse deterministic
nulls and actual account-deletion read races. Source tests are not live worker
evidence: owner must deploy API/site and execute the real provisioned worker
token workflow to verify job→stored snapshot→served dashboard.

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
## Owner-scoped individual deletion (approved increment, verification pending)

`sync` additionally accepts optional `deletions` (default empty for existing
clients), at most100 per request. Each strict row is `{id,type,recordId,ts}`:
stable UUID request ID, `habits` or `voice`, UUID target and UTC timestamp.
No account key or text is accepted. Identity is derived exclusively from the
verified issuer/subject with customer Garden.ReadWrite scope; no Admin needed.
Target IDs from another account cannot access/delete that account's partition.

SQLite v5 adds account-scoped minimal deletion markers without changing existing
records/session paths. Confirmed local removal atomically purges the selected
habit plus check-ins/reflections/linked pending events, or the selected private
feedback/rating plus its replies; no other recipe/account is wiped. Markers
and unsynced deletes survive restart. Deletions upload before surviving records.
Local and remote merge suppress stale deleted IDs regardless of edit timestamp,
so an old offline device cannot resurrect a removed parent/dependent/thread.

Server authority is an account-gate deletion ledger. The marker and gate revision
commit atomically; every record/reply writer CASes that same gate. Content
cleanup runs in bounded paginated batches, resuming from marker metadata on
retry/reconnect if interrupted. GET/reply/team pagination never expose suppressed
content; readback cannot acknowledge unfinished cleanup. Retry request ID reuse
with changed target/timestamp is a409; repeated same deletion is idempotent.
Snapshot generations are invalidated, deleted linked raw events excluded, and
reply audits for deleted feedback removed without auditing any body/reply text.

Minimal type/UUID/request UUID/time markers persist for the account lifetime
(`ttl=-1`), because no maximum offline-device age/rejoin guarantee is enforced.
Expiring a marker would permit resurrection. At most1000 markers per account;
no silent pruning, and exhaustion returns an explicit error. Preview lifetime
write/record budgets remain conservative and are not reset by deleting content.
Whole-account deletion separately removes markers/content under its existing
explicit confirmation. Export includes ID-only markers so deletion state is
transparent; it does not contain deleted private text. This is suppression
metadata, not archival of removed records.

Deploy the backward-compatible API before the new client; an old client
ignores the additional response field but its stale writes are server-suppressed.
Only the new client applies remote markers to local records. A client cannot
claim remote deletion merely from local disappearance: pending requests/errors
remain retryable and sync success requires HTTP200 after server cleanup.
Deletion-only sync remains available under API/engagement/operational pause;
mixed normal writes still obey those controls.

The device withdraws only the removed recipe's toast when reminders were already
enabled; deletion never enables notifications or changes OS permission. A toast
request that overlaps deletion is withdrawn, and a stale action cannot recreate
a check-in. ID-only42-day reminder/cap history is retained so deletion cannot
reset daily notification budgets. Earlier user-exported files or downloaded
copies are outside this active-store removal; processor backup retention remains
a separate disclosed operational/privacy obligation, not an instantaneous purge
claim.
