# Bounded backend engagement preview

Source and deterministic store tests only: this is **not** evidence of deployed
dashboards, successful live JWT sign-in, Cosmos transactions/indexes, native
reminder delivery, or an observed customer/team round trip. No cloud settings,
credentials, client, website, or workflow changes are made by this workstream.

## Authentication and client compatibility

Every registered route calls the existing real `jose` JWT verifier: HTTPS JWKS,
RS256, exact configured issuer/audience, required sub/iss/exp/iat, and
`Garden.ReadWrite` scope or explicit `Bloomstep.Admin` role. Account partition
keys remain SHA-256 of the exact validated `issuer|subject`, not email. Both
admin routes independently require that exact role; a garden scope is not an
operator role. Azure Functions `authLevel: anonymous` does not bypass JWT checks.
Missing provisioned identity/database configuration returns 503; invalid tokens
return 401 and missing privileges return 403. There is no fake identity path.
The handler factory injects stores/auth only for isolated tests; production
always supplies the strict verifier and configured Cosmos container.

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

Incoming telemetry is still exactly `{id,name,ts}`, using the existing registry:
recipe_created, checkin, reflection, habit_graduated, feedback_submitted,
share_initiated, reminder_sent, signin_succeeded, weekly_reflection, rating_prompted. Unknown fields/names and
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

`GET /api/admin/metrics?days=7`, with integer days 1–30 (default 7), returns:

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

The example elides the other six daily rows and explanatory strings. Days are
UTC inclusive dates, including the current partial day. The endpoint computes
deterministic **daily aggregates on demand** from existing accepted event
envelopes, deduplicated by account/client ID. There is no persisted aggregate
copy or recurring aggregation job, so no new analytic store/schedule can grow.
Malformed envelopes are excluded; conflicting duplicate envelopes for one key
are excluded rather than selecting a winner based on database result order.
Private garden, feedback text and rating records are never aggregation inputs.
Neither account hashes nor raw IDs/events are returned.

Each day needs at least 50 distinct opted-in contributing users. Within a
publishable day, a nonzero event count also needs 50 distinct contributors to
that event; smaller counts are null. True zero counts may be returned only
inside a publishable day. Category totals are null if any constituent daily
count is suppressed; they do not silently sum partial/suppressed periods.
Returning check-in users means distinct users with check-in events on at least
two UTC days inside the requested window; it is suppressed below 50. It is not
D7/D30 retention. Ratings/experiments are explicitly unavailable because the
current telemetry allowlist has no rating-value or experiment events. The
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
the account deletion drain; no aggregate copy needs separate erasure.

## Private feedback loop and audits

- `GET /api/admin/feedback?limit=20&cursor=...` returns
  `{feedback:[{userId,record}],nextCursor:string|null}`. Limit is 1–20, default
  20. A bounded keyset cursor encodes the last scanned account/document ID;
  it conveys no authorization and is strictly validated (maximum 256 chars).
  Sort order is account then document ID, not recency. Empty pages may still
  have a cursor when deleted/orphaned accounts were skipped. Keep following
  `nextCursor` until null. This is a live listing, not a snapshot; records
  inserted before the current cursor appear on a fresh listing.
- `POST /api/admin/feedback/{userId}` accepts the existing strict
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
| Per-account requests | 30/minute |
| Per-account stored habits/check-ins/reflections/voice/settings | 100 / 1,000 / 100 / 100 / 7 |
| Per-account lifetime telemetry records | 3,000 |
| Per-account new telemetry/day (server ingestion UTC day) | 30 |
| Replies/thread | 20 |
| Feedback page | 20 records |
| Garden read | 1,307 records, then fail closed |
| Metrics scan | 10,000 event rows and 200 account gates, then fail closed |

Global budget reservations update a single non-expiring ETag-conditional ledger
at `__preview_budget/budget` before writes/read scans. Each admitted garden
request, mutation/account creation, read audit, and reply attempt/commit reserves
budget; one HTTP request may consume multiple reservations. Records reserved
include new account gates, garden/event documents and audits; the singleton
budget ledger is not itself counted. Retries/no-op sync still consume request
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
Audit TTL is 30 days; private garden/tombstone/budget documents do not expire.
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
   dashboards are delivered here; rating-value/experiment telemetry requires a
   separately reviewed strict registry and consent contract, not schema bypasses.
5. Verify real customer submit → audited operator read → private status/reply →
   customer sync and deletion/reply races. Exercise older queued-event rejection,
   quota errors, offline retries and opt-out queue clearing on the actual client.
   Sparse previews intentionally display null metrics at the 50-user minimum.
6. Run `npm --prefix api run check` and `npm --prefix api test`. The suite retains
   the original eight tests and adds deterministic in-memory Cosmos-style
   ETag/batch, privacy, quota, pagination, kill-switch, feedback round-trip and
   sync-compatibility regressions. These tests are source-contract evidence,
   not a substitute for live identity/database/client verification.
