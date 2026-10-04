# MVP status and iteration ledger

**Engineering preview, not a completed or publicly usable MVP.** Identity,
cloud deployment and native background behavior require integration evidence.
This ledger is updated with verified outcomes, not inferred from source code.

| Iteration | Job | Current evidence / remaining gate |
| --- | --- | --- |
| 0 | Build, run, ship | Public unsigned `v0.1.0-preview.1` engineering installers published; ARM64/x64 install-launch-second-launch-uninstall CI passed. Both public downloads independently hash-verified. Local upgrade/SmartScreen and authenticated acceptance remain gates. |
| 1 | Plant first habit | SQLite tests and real widget journey pass: five starters, four recipe fields, three species, practiced celebration, restart-safe storage. |
| 2 | Check in | Tests pass for did/more/rest, idempotency, append edits/undo, local midnight. Widget tap/celebration/undo pass. Native measured latency pending. |
| 3 | Visual garden | Newer true ARM64 synthetic profile `f92473d` launched and app-only capture inspected: readable banner and reserved Plant bar fixes observed. Responsive/200%-text regressions pass. Native screen-reader evidence remains pending; UIAutomation did not expose button controls in the current OS mode. |
| 4 | Local reminders | Real Windows plugin/tray wiring plus durable targeted Later, account-scoped IDs, Off/focus recovery, seven-unanswered pause/reset and personalized-timing control are source-tested. Separate release-forbidden runtime probe checks real OS history/tray/hide/caps/cleanup; actual run and popup/Focus/restart evidence remain pending. |
| 5 | Sign in | Email OTP, Google and Microsoft personal-account providers are now created AND enabled on the actual native/console user flow. MSA issuer/discovery/client/scope/auth type and both callbacks verified; real PKCE sign-in page HTTP200 includes all three options. Actual provider login/token exchanges remain unobserved, not inferred from setup. No fake login. |
| 6 | Sync | Personal SWA Free/Cosmos free tier provisioned; live unauthenticated sync API returns 401. SQLite v4 preserves durable fingerprints and adds typed event properties; partial upload/concurrent edits, consent purge and account isolation tested. Live probes exposed SWA replacing Authorization and reserved admin routes: dedicated client-token header and team routes fixed in source, deployment smoke gate added. Actual authenticated two-account/device/offline round trips remain pending. |
| 7 | Funnel | Versioned48-event registry and strict optional metadata; four typed dashboards with minimum50 contributors. Persisted completed-day snapshots are consumed distinctly from on-demand windows, with generation/deletion validation and no median/user-count summation. Real worker run37214984889 wrote a snapshot and its token was rejected by customer/team routes. Observed consent-bound session and fresh sign-in events are wired; restore never fabricates sign-in/install/provider history. Acquisition/install/OS-delivery observations remain incomplete; cron needs default-branch merge. |
| 8 | Feedback | Private queue/status/replies; audited pagination/retry/deletion protections tested. Real browser PKCE operator source and separately registered SPA/consent/flow binding now prepared; credentials memory-only, no pasted token. Actual selected customer Admin and feedback/rating round trip still pending. |
| 9 | Invite | Authenticated opaque invitations, server-owned attribution, first-positive-practice mutual cosmetic saga and owner-only receipts implemented/tested. Native copy/email/QR/Windows Share UI, opt-in recipe card, accept/decline, cached retry IDs and export integrated. Per-user protocol and private IPC/inbox preserve intent across install/sign-in; web handoff/storage is explicit. Live customer reward and OS-share observations remain pending. |
| 10 | Reflection | Weekly deterministic Doctor works independently of fortnight naturalness sliders; cooldown checked before collecting scores. Real SQLite graduation/spacing tests pass. Not a validated SRBAI instrument. Native learning interaction still pending. |
| 11 | Reconnect | Three/seven-day rule, max two/absence, activity reset and scheduler shared quiet-hour/day caps implemented; rules tested. Windows delivery and closed-app behavior not observed. |
| 12 | Website/update | Live SWA landing/config HTTP200 and public engineering prerelease with ARM64/x64 installers/checksums. Manual trusted version/channel checks tested, never auto-execute. Actual local upgrade/SmartScreen observation pending. |
| 13 | Rating/privacy | Positive-moment prompts wait for celebration and persist a 120-day cadence even when dismissed; rating text optional. Export/account isolation/cleanup tested. Cloud deletion tombstone/races tested against backend fixtures, not live Cosmos user deletion. |
| 14 | Experiment | Strict schema2/checksum, monotonic version, account cache, seven-day expiry and explicit control-mode warnings tested; compiled API origin, device timing toggle and actual-callback-only exposure. Bounded copy experiment remains OFF until genuine reviewed cohort/guardrail evidence, not fabricated data. |

## Current external gates

- Personal subscription is now available. Never use the corporate development
  subscription. Only free SKUs/allowances, explicit subscription targeting.
- External ID customer tenant is separate from the Azure resource directory.
  Microsoft personal/work-school federation and Google OAuth credentials must
  be verified; email OTP is supported by customer user flows.
- Developer Mode stays off by user choice; CI supplies native builds.
- Legal/privacy/name review and exact provider production settings remain launch
  gates. A compiled, sign-in-gated preview is not the signed-in MVP.
- Fresh live Cosmos census was empty; required feedback composite index and a
  conservative reserved preview-volume ledger were then provisioned. Finite
  quotas and API/engagement kill switches are source-tested, not monetary hard
  caps. Dedicated free resource-tenant guard/FIC and least-reader roles are now
  provisioned; one-way operational pause and reviewed Admin resume source tested.
  Actual audit run37217476414 passed with `warning_cost_unknown`, no pause.
  Current Cost Management query is unavailable
  for this new subscription, not zero cost. Trial spending limit On/free SKUs are
  verified; billing/trial expiration approval remains a launch gate.

## Latest verification

116-test full serial Flutter suite passes, including observed session/sign-in
consent, invitation retries/export,
opaque intent IPC, capped reminders and active-session clock boundaries.
Full analyzer is clean. API suite passes90; browser suite passes16; spend-guard
policy suite passes8. Native Share bridge compiles with the existing ARM64 SDK.
Live popup/API proof is
pending. No test fixture is represented as a real user login.
The offline window expires at exactly 30 days and checks a secure-storage
last-observed watermark. In-memory session access hides immediately at expiry or
resume failure; serialized credential writes cannot resurrect a signed-out cache.
Native screenshot timeline is kept privately, never copied with user account data.
Deployment run37217202261 passed at `5a28346`. Both native jobs in run37217202495
failed on Visual Studio's deprecated experimental coroutine headers. The runner
now requests C++20 instead of suppressing that error; replacement full native
builds and installer lifecycle evidence are pending.

## Verification and demo jobs

Every usable milestone must launch the **newer** native ARM64 build and capture
only its app surface, with synthetic data where needed. Maintain a chronological
local screenshot index: IST timestamp, iteration, version, exact commit, observed
surface and limits. Never invent retrospective screenshots, capture another app,
or publish user habit data/tokens. Prefer one tracked app window; close only
identified PIDs gracefully, never kill a process name.

Developer Mode stays **off by user choice**. Use GitHub CI ARM64 builds, download
artifacts and launch locally. A separate CI-only `tool/preview.dart` profile target
is labeled synthetic, uses its own temporary SQLite store and never authenticates,
syncs, or enters release installers. Normal `lib/main.dart` is always sign-in gated.
The preview rejects release mode. Native captures use its Flutter repaint boundary,
not desktop capture, so other applications and login screens cannot leak.

Run `flutter analyze` and `flutter test --reporter expanded --concurrency 1 --timeout 60s`.
Desktop FFI/widget harnesses are run serially; parallel Windows runs have stalled
on the rating dialog test. API:
`cd api; npm ci; npm run check; npm test`. CI builds both Windows architectures,
produces Inno Setup installers and checks install-launch-uninstall in an isolated
runner directory. Tag workflow publishes **prereleases**, never production.

Core UI test: choose Plant; Calm; practice celebration; Plant this seed; Did it;
Undo today. A test-only injected SQLite account drives the widget harness; there
is no anonymous release entry point. `BLOOMSTEP_SCREENSHOTS` optionally writes
rendered images to an explicit local artifact directory (not committed).

## Edge matrix

| Edge | Expected contract | Evidence |
| --- | --- | --- |
| Double tap / retry | One effective day, same result doesn't add an event | SQLite unit test |
| Same-clock edit then undo | UTC microsecond ordering, fixed-width timestamp | SQLite regression test |
| Local midnight | New calendar date, not UTC date | SQLite test |
| Miss/undo after sprout | Attained stage persists | SQLite test |
| Account switch | Cannot read or mutate old account IDs | SQLite test |
| Stale remote recipe | Does not replace newer local recipe | Sync unit test |
| Equal-version edits | Canonical recipe field tie-break, maximum attained stage, microsecond timestamp ordering | Flutter and API regression tests |
| Remote preferences | Quiet hours/visual preferences sync; consent, reminder enablement and startup never remotely enabled | Flutter/API tests |
| Duplicate remote events | Union by immutable client ID | Sync unit test |
| Failed upload / restart / edit while uploading | Durable snapshot acknowledgment, changed versions remain pending | SQLite outbox tests |
| Analytics disabled while upload queued | Atomic queue purge and pre-chunk consent recheck | Store/service tests; already-sent requests cannot be recalled |
| Weekly review during naturalness cooldown | Weekly loop available, no wasted slider entry | Widget/store regression |
| Rating dismiss/snooze | <=one prompted invitation per 120 days, after celebration | Store/widget regressions |
| Invalid future/oversized API records | Reject, don't silently truncate | Schema tests; timestamp-skew integration pending |
| Cross-account API input | No client account field accepted | Strict schema tests; live adversarial API test pending |
| Telemetry free-text | Reject unregistered events/unknown fields | API contract tests |
| Managed SWA proxy authentication | Never trust overwritten Authorization/proxy principal; require dedicated validated customer JWT header | Native/API/console tests; live authenticated proof pending |
| Internal daily worker | Separate pinned resource issuer and explicit aggregate-only role; never garden/team access | API signed-token tests and real run37214984889 |
| Second native launch | Activate existing window, no duplicate reminder process | Windows socket/file-lock tests; dual-architecture installer CI gate added |
| Damaged instance descriptor | Report corruption and always release owner lock | Windows regression test |
| Client forged team status | Server owns received/status/replies | API contract tests |
| Deleted account + concurrent sync | Conditional account gate in same-partition transactional batch | Source implemented; Cosmos integration pending |
| Auth unavailable/offline | Local changes preserved, error explicit, no mocked identity | Sign-in gate widget test; real offline login pending |
| Quiet hours across midnight/caps | No delivery, <=3/day and <=1/habit/day | Rule tests; OS observation pending |
| Seven ignored prompts | Pause, explain opt-out | Source implemented; scheduler tests/OS observation pending |
| Large text/small screen/keyboard | Scrollable forms, labeled targets, no clipping | Widget checks in progress |
| Unsigned installer | Unknown publisher disclosed, hashes downloadable | Installer matrix pending |
