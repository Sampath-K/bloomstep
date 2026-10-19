# Anonymous feedback (opt-in, disabled by default)

`POST /api/feedback/anonymous` is public and does not require sign-in, bearer
tokens, account IDs, habits, or profile data. Existing authenticated support
feedback is unchanged. Use normal API deployment; this change does not deploy.

Enable only with all of:

- Existing `COSMOS_CONNECTION_STRING` and `storageTarget` database/container
  configuration (`COSMOS_DATABASE_NAME` and `COSMOS_CONTAINER_NAME` together if
  overriding defaults).
- `BUDLARK_ANONYMOUS_FEEDBACK=enabled`.
- `ANONYMOUS_FEEDBACK_HASH_SECRET`: dedicated random secret, at least 32 UTF-8
  bytes, identical across instances. Generate securely; never log it. Keep stable
  through the seven-day retention window: rotation resets quota/idempotency hashes.
- `ANONYMOUS_FEEDBACK_TRUSTED_IP_HEADER=x-azure-clientip` or `x-forwarded-for`.
  **The deployment owner must ensure the trusted ingress overwrites this header,
  removes caller-supplied copies, and prevents direct origin bypass.** Exactly one
  plain IP is accepted; forwarded chains/ports are rejected. Do not enable behind
  an ingress that merely appends untrusted values. Missing/invalid IP fails closed.
- Cosmos partition key `/userId` and container TTL enabled (`defaultTtl=-1` or
  positive). Handler checks metadata and refuses to save without these. Item TTL
  performs bounded retention cleanup; existing shared-container TTL policies are
  not changed here.

`BUDLARK_API_DISABLED=true` or `1` also disables this endpoint. Missing feature,
secret, ingress, storage, or TTL configuration returns 503 without a receipt.
Configure platform/APIM/Application Insights to **exclude request/response bodies,
IP addresses and authorization headers** from diagnostic/access logging for this
route. Application code never logs those values. No authenticated session headers
should be added by a caller.

## Exact request/response contract

JSON content type (`application/json`, optionally `charset=utf-8`), max **8192
UTF-8 bytes**, including all JSON encoding overhead. Unknown keys are rejected.

```json
{"consent":true,"deviceId":"random UUID v4","requestId":"random UUID v4","text":"Optional feedback","rating":5}
```

Both IDs must actually be UUID v4 strings (placeholders above are explanatory).
`deviceId` is a random installation-local feedback identifier, not an account,
hardware, advertising, or authenticated identifier. `requestId` is a new random
idempotency key per explicit submission, reused verbatim on retry. At least one
of `text` (nonblank, **1–2000 Unicode code points**) and `rating` (integer **1–5**)
is required. Text is not trimmed or silently truncated. Do not include personal
details or secrets in free text. No arbitrary metadata is accepted.

201 for a new durable save; 200 only for an identical previously saved request:

```json
{"status":"received","receiptId":"server UUID v4","receivedAt":"2026-10-19T01:00:00.000Z"}
```

No receipt is issued until the Cosmos transactional batch succeeds. Lost network
responses are safe to retry with the same key/payload. Different content/device
with the same key is 409. Receipt and key deduplication last **7 days**, not
forever. Generic 200 responses are not delivery acknowledgements. Errors: 400
shape/JSON, 413 bytes, 415 content type, 409 conflict, 410 expired surviving
receipt, 429 quota/contention, 503 unavailable/unconfigured. Do not auto-retry
conflicts with a new key.

## Bounds and durable atomicity

UTC-day limits: **3/device AND 10/IP AND 100 globally**. All three counter changes
and receipt/content creation commit in one Cosmos transactional batch within
`__anonymous_feedback`; ETag compare-and-swap plus bounded contention retries
prevents cross-instance overspend. Duplicates consume no additional quota and
remain retrievable after a quota is exhausted. Random device IDs are not proof of
physical device identity; IP and global limits bound identity resets. IPv6 textual
variants are canonicalized before hashing. Budgets expire **2 days after their last
write**, receipts/content after **7 days**. Only keyed HMACs are stored for
device/IP/request and canonical payload fingerprints, never raw device/IP IDs.
The single partition and low global cap intentionally favor safety over scale.
These quotas bound saved content, not hostile network/read traffic; retain ingress
body/connection/rate controls and the existing API host concurrency bounds.

## Dart integration

`AnonymousFeedback(applicationSupportDirectory, origin: '${IdentityService.apiOrigin}/api')`
is account independent; pass the same configured API origin used by existing app
services with `/api` appended (`IdentityService.apiOrigin` itself excludes `/api`),
with no token provider or authenticated client.
`enqueue(consent: true, text: ..., rating: ...)` durably queues an explicitly
requested submission and returns a **queue key**, not a receipt. Show “queued”
until `submitNext(requestId: queueKey)` returns `AnonymousFeedbackReceipt` for that
same key. This selects the exact explicit opt-in, not an older queued message.
Missing/expired keys throw `AnonymousFeedbackFailureReason.notQueued` without
sending another entry. Omitting `requestId` deliberately drains the oldest entry;
null means only that the queue is empty. Offline/timeouts, invalid configuration,
non-200/201 statuses, oversized or malformed receipts throw bounded
`AnonymousFeedbackFailure` reasons (`httpStatus` is available for rejected responses).
No raw response/error details are exposed. Content stays queued on delivery
failures; unexpected/programming and local storage exceptions propagate rather
than becoming false acknowledgements. UI must retain “queued” status on errors,
and should not call an absent/expired item queued. Retry on a later
user/network opportunity, not a tight loop. HTTPS only, no redirects or bearer
headers; receipt shape/UUID/time are validated and response bytes/time bounded.

The dedicated disk outbox is atomic, flushed, serialized within the process,
limited to **10 entries**, and expires entries after **7 days** on next access.
It is not account/profile storage; do not construct multiple app processes for
the same outbox (the existing app single-instance guard applies). Local file
permissions follow the application-support directory. `clearPending()` withdraws
unsent content; it cannot revoke already received submissions. The directory
owner may remove the outbox during app-data removal. No UI wiring is included.
