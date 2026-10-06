# Synthetic acceptance automation

This is an engineering test path, not another sign-in option or an MVP release
claim. Microsoft/Google federation, provider consent, MFA, customer accounts,
production Cosmos, Windows notifications/share UI, and population measurements
are not exercised by it.

**Verification state:** API/authentication tests and Flutter static analysis
pass locally. The full Windows widget/API journey is pending hosted x64 and
ARM64 CI; this OneDrive worktree cannot execute Flutter tests because its
generated Windows symlink/reparse-point directories are not writable. Do not
count the journey as green until both hosted receipts report `success` and
`cleanupVerified: true`.

## Isolation and release boundary

- `integration_test/support/test_only_app.dart` and the local API harness under
  `api/test/support/` are imported/launched by tests only. The normal
  `lib/main.dart` entry point does not import them, and `api/.funcignore`
  excludes the entire API test tree from Azure Functions deployment.
- Windows CI generates a new 256-bit key in the acceptance step, masks it, and
  injects it through that process's environment. It is not a Dart define,
  command-line argument, `GITHUB_ENV` value, source constant, log field, or
  artifact field. The Node child receives only the key, a new temporary
  database path, the requested ephemeral port, the fresh/reopen mode and the
  minimal OS variables needed to start Node. It does not inherit
  repository/provider credentials or production endpoints.
- The test app requires the compile-time `BLOOMSTEP_TEST_BUILD` flag, a valid
  per-run 32-byte hexadecimal key, a `synthetic-*` username, and a newly
  created disposable temp directory. It creates no local profile for a
  missing/wrong key or a real
  account-shaped username. Its short-lived HS256 token grants only
  `Garden.ReadWrite`; neither the test API nor the production authenticator
  accepts caller-supplied roles.
- Test clock, export-path and API-origin overrides fail closed unless the
  compile-time test define is enabled; the test API-origin override additionally
  accepts only uncredentialed `http://127.0.0.1:<ephemeral-port>`. CI separately
  runs the release-mode gate tests without the define, and the production
  release build does not receive it.
- The test API binds to `127.0.0.1` on an OS-assigned port and exposes only
  `/api/sync` plus a content-free readiness route. Its test issuer and audience
  are distinct from production. It calls the production `createHandlers` sync
  and owner-record deletion handlers with a file-backed Cosmos-compatible
  adapter. This adapter covers the tested query, partition, ETag, batch,
  persistence, and tombstone contract; it is **not** the Cosmos Emulator and
  is not evidence of an Azure Cosmos deployment or its consistency behavior.
- The synthetic build and key never enter the existing `Release`/installer
  artifact paths. Preview publication continues to use only the normal
  sign-in-gated x64/ARM64 release installers. Production API authentication
  remains RS256-only with HTTPS JWKS, configured issuer/audience, required
  identity claims and the existing scope/admin checks.
- CI emits a sanitized per-architecture evidence receipt. It contains test
  result, synthetic owner partition hashes, owned fixture IDs and cleanup
  status only—not keys, tokens, user-provided habit text, provider details or
  screenshots. A failed or skipped run is not a passing receipt.

## Automated journey

The Windows x64 and ARM64 CI jobs run the Flutter application through its real
desktop widget tree with a disposable SQLite profile, then call the app's
`SyncService` against the loopback API. The journey is designed to prove:

1. Missing/wrong test keys and email-shaped identities fail closed before a
   profile is opened.
2. A synthetic owner can plant and edit a recipe; record Did more, Not today,
   Did it and undo; complete weekly reflection/Recipe Doctor; and reach
   graduation through two UI naturalness reflections and 17+ distinct local
   practice days in the moving 28-day window.
3. Feedback can be saved, included in the app's JSON export, and deleted. The
   recipe can be deleted. Sync returns owner-scoped tombstones; a fresh local
   store reads those deletions back from the persistent API adapter.
4. Closing/reopening the app preserves the local test profile. A second
   synthetic owner sees neither the first owner's garden nor feedback.
5. The API process can be closed and restarted with the same disposable store,
   preserving owner records and deletion tombstones, while wrong-key, expired,
   role-bearing, wrong-scope and real-account-shaped test tokens are rejected.
6. The production authenticator accepts a valid RS256 token and rejects HS256
   test tokens, unsigned tokens, wrong issuer/audience, expired tokens and
   unprovisioned service configuration.

The naturalness test uses an injected clock through the same UI and storage
methods to exercise the long-window graduation branch quickly. It verifies
deterministic product behavior; it does not advance a real user's calendar or
establish an automaticity/population outcome.

Persistence assertions inspect the durable habit/check-in/deletion inventory,
not `syncPayload()`, which is only the pending upload outbox. Successful sync
leaves acknowledged outbox entries empty while retaining durable records.
Fresh same-owner SQLite stores download the planted recipe, Did-more check-in,
and deletion ledger through the real backend GET path, independently of the
original profile's local records.

The test login emits no sign-in/acquisition telemetry and does not opt the
synthetic profile into analytics. Habit/feedback fixtures use the existing
default-off telemetry consent behavior; synthetic records and receipts are not
population inputs.

## Manual paths and unattended alternatives

| Surface | Unattended strategy | Explicit residual |
|---|---|---|
| Routine recipe/check-in/reflection/feedback/export/record-delete UI | Synthetic desktop-widget journey plus real app SQLite, loopback `SyncService`, production API handlers and owner-partition readback | Does not prove a real customer's session or production Cosmos. Account wipe is deliberately excluded. |
| Second-account isolation | Two separately keyed synthetic subjects and owner hashes in the same disposable API store | No second human/provider identity or second real device is invented. |
| Production identity/provider/MFA | RS256/JWKS/auth-claim contract tests, plus the existing provider-specific source/callback suites | Genuine provider pages, consent, MFA and which provider completed a live exchange remain provider acceptance, not synthetic passes. |
| Operator/Admin access | API role/scope denial and handler authorization tests | No Admin role is granted and no live operator identity is selected. |
| Feedback/referrals | Synthetic private feedback create/export/delete and API contract tests; invitation business logic remains isolated in its existing tests | No live team reply, real invitation, email, external participant, reward attribution or referral population is claimed. |
| Windows notifications, tray, Share, keyboard/Narrator | Deterministic service/widget and adapter contracts where available | No actual toast delivery, OS popup, Share target, permission/Focus behavior or human accessibility assessment. User-authorized visible OS acceptance remains separate. |
| Controller/legal/privacy/contact/calendar/billing facts | Keep factual approval manual and record only decisions from an authorized source | Automation cannot invent controller identity, legal text, calendar facts, subscription/billing status or spending approval. |
| Acquisition, crash-free rates and cohort timing | Tests can validate consent gates and deterministic event schemas; synthetic clock can exercise code paths | No customer installs, real consented cohort, crash-free denominator or D7/D30/D90 outcome is fabricated. |

## Security review ownership

The implementation owner maintains the test-only boundary and its negative
tests: no reusable secret in source/build defines/production artifacts, no
test route in Azure deployment, loopback-only API, disposable storage, no
synthetic role escalation, and unchanged RS256/JWKS production authentication.
A repository security reviewer should independently inspect the boundary
before treating the harness as a trusted release control. Any future test
backend must have a separate isolated resource, identity, key rotation and
spend approval; it must not reuse customer Cosmos or production credentials.
The automation receipt is engineering evidence, not a security certification.

## Remaining work ownership

| Workstream | Owner / next action | Definition of done |
|---|---|---|
| Synthetic automation increment | Implementation session: finish contract tests, publish a PR, resolve x64/ARM64 CI failures, merge only green checks and capture both sanitized receipts. | Each architecture shows the desktop UI/API journey, separate production release build, test-artifact isolation, stopped API process, closed profile and deleted temp root. |
| Cosmos-specific integration | Platform/service owner: provision or designate an isolated, no-cost test resource and narrow test identity; implementation session: wire a separately approved isolated CI check only if available. | Actual Cosmos round-trip/restart/partition/tombstone evidence. Current file adapter is not a substitute. No billing change is authorized. |
| Provider and MFA acceptance | User/operator: complete Microsoft/Google provider flows in the trusted browser when needed; implementation session: verify only sanitized callback/exchange outcomes without retaining credentials. | Real provider-specific exchange, MFA/consent and session lifecycle evidence. Synthetic JWT acceptance does not satisfy it. |
| Live operator, customer and referral loops | User: choose an authorized operator and any genuine test identity/participant; implementation session: perform least-privilege access, feedback response, referral and cleanup checks only within the approved scope. | Live ownership/role, readback, attribution and exact cleanup. No Admin grant, outbound message or extra identity is inferred. |
| Windows native surfaces/accessibility | User: authorize the per-app notification setting and ordinary foreground interactions; implementation session: observe toast/share/cancel/keyboard results and retain sanitized evidence. | Actual delivery and user-visible behavior. Adapter/API acknowledgements alone do not pass this row. |
| Public legal and financial facts | Product controller/user: provide accurate controller/contact/privacy/provider/age/retention/calendar and billing decisions; implementation session: implement only the reviewed facts. | Published, reviewed disclosures and verified spend/trial status. Billing remains unknown and no spend is approved. |
| Cohort and experiment | Product owner/operator: review a real consented cohort when available and explicitly approve a bounded experiment; implementation session: run/read back only that reviewed assignment. | Experiment activation, guardrails and outcome evidence. It remains OFF; population evidence gates experiment activation, not publication of an engineering preview. |

Acquisition/cohort evidence is not a synthetic release prerequisite. Under the
approved product contract, reviewed genuine cohort and guardrail evidence gates
**experiment activation/publication**, not the ability to publish an engineering
preview. The experiment remains OFF and the full MVP remains incomplete until
its real review/activation/result loop is completed.

## Running

Use the ordinary test-only define for widget/unit tests; never add a test key to
`--dart-define`. The full authenticated loopback journey is provisioned and
executed by the supported Windows CI matrix, which creates and injects its
own per-job key. The production release command remains a separate step and
does not receive the test define or key.

The desktop journey waits for durable model transitions and the garden's
enabled Plant control after SQLite work and UI reload complete. Frame settling
alone does not await filesystem I/O. Undo after a rest checks that today's
entry becomes absent, not the already-zero positive practice count. Graduated
recipes no longer show Did-it controls; weekly reflection checks its persisted
cadence and its own UI instead.
