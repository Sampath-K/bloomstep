# MVP status and iteration ledger

**Engineering preview, not a completed or publicly usable MVP.** Identity,
cloud deployment and native background behavior require integration evidence.
This ledger is updated with verified outcomes, not inferred from source code.

| Iteration | Job | Current evidence / remaining gate |
| --- | --- | --- |
| 0 | Build, run, ship | Public unsigned `v0.1.0-preview.2` engineering installers published from green `b48bd73`; both architectures/download hashes verified. Actual local ARM64 install preview.1 -> preview.2 upgrade, normal launch, repeat launch, registered URI handoff and ownership-aware uninstall passed. Normal candidate reinstalled per-user; SmartScreen/customer acceptance remain gates. |
| 1 | Plant first habit | SQLite tests and real widget journey pass: five starters, four recipe fields, three species, practiced celebration, restart-safe storage. |
| 2 | Check in | Tests pass for did/more/rest, idempotency, append edits/undo, local midnight. Actual MSAA Did-it action in the newer synthetic native garden exposed celebration in67ms (<=300ms); not a customer-use measurement. |
| 3 | Visual garden | True ARM64 synthetic profile captures inspected: readable banner and reserved Plant bar fixes observed. Responsive/200%-text regressions pass. Actual Flutter child HWND exposes38 MSAA nodes including labeled action buttons; UIA is empty, not evidence of no MSAA support. Narrator interaction remains unobserved. |
| 4 | Local reminders | Real runtime probe observed tray bounds/hidden window and clean teardown. It exposed the dependency's unpackaged Win32 history/individual-cancel limitation. Native explicit-AUMID/grouped WinRT request/history/removal now replaces that path, with OS permission preflight and surfaced errors. This machine reports NotificationSetting2 (DisabledForUser); no OS settings changed or delivery claimed. New adapter full native/link/removal and popup/Focus/restart observations remain pending. |
| 5 | Sign in | Email OTP, Google and Microsoft personal-account providers are now created AND enabled on the actual native/console user flow. MSA issuer/discovery/client/scope/auth type and both callbacks verified; real PKCE sign-in page HTTP200 includes all three options. Actual provider login/token exchanges remain unobserved, not inferred from setup. No fake login. |
| 6 | Sync | Personal SWA Free/Cosmos free tier provisioned; live unauthenticated sync API returns 401. SQLite v4 preserves durable fingerprints and adds typed event properties; partial upload/concurrent edits, consent purge and account isolation tested. Live probes exposed SWA replacing Authorization and reserved admin routes: dedicated client-token header and team routes fixed in source, deployment smoke gate added. Actual authenticated two-account/device/offline round trips remain pending. |
| 7 | Funnel | Versioned48-event registry and strict optional metadata; four typed dashboards with minimum50 contributors. Persisted snapshots remain distinct from on-demand windows with deletion validation and no median/user-count summation. Actual main worker run37222477262 wrote one snapshot; its token was rejected by garden/team routes. Consent-bound session/fresh sign-in events are wired; no inferred install/provider history. Source merged to main, workflow definitions active; scheduled tick not yet observed. Acquisition/install/OS-delivery measurements remain incomplete. |
| 8 | Feedback | Private queue/status/replies; audited pagination/retry/deletion protections tested. Real browser PKCE operator source and separately registered SPA/consent/flow binding now prepared; credentials memory-only, no pasted token. Actual selected customer Admin and feedback/rating round trip still pending. |
| 9 | Invite | Authenticated opaque invitations, server-owned attribution, first-positive-practice mutual cosmetic saga and owner-only receipts implemented/tested. Native copy/email/QR/Windows Share UI, opt-in recipe card, accept/decline, cached retry IDs and export integrated. Per-user protocol and private IPC/inbox preserve intent across install/sign-in; web handoff/storage is explicit. Live customer reward and OS-share observations remain pending. |
| 10 | Reflection | Weekly deterministic Doctor works independently of fortnight naturalness sliders; cooldown checked before collecting scores. Real SQLite graduation/spacing tests pass. Not a validated SRBAI instrument. Native learning interaction still pending. |
| 11 | Reconnect | Three/seven-day rule, max two/absence, activity reset and scheduler shared quiet-hour/day caps implemented; rules tested. Windows delivery and closed-app behavior not observed. |
| 12 | Website/update | Live SWA landing/config HTTP200 and public preview.2 ARM64/x64 installers/checksums. Manual trusted version/channel checks tested, never auto-execute. Actual local versioned upgrade/protocol/uninstall observed; silent QA is not evidence of browser SmartScreen experience. |
| 13 | Rating/privacy | Positive-moment prompts wait for celebration and persist a 120-day cadence even when dismissed; rating text optional. Export/account isolation/cleanup tested. Cloud deletion tombstone/races tested against backend fixtures, not live Cosmos user deletion. |
| 14 | Experiment | Strict schema2/checksum, monotonic version, account cache, seven-day expiry and explicit control-mode warnings tested; compiled API origin, device timing toggle and actual-callback-only exposure. Bounded copy experiment remains OFF until genuine reviewed cohort/guardrail evidence, not fabricated data. |

## Current external gates

- Personal subscription is now available. Never use the corporate development
  subscription. Only free SKUs/allowances, explicit subscription targeting.
- External ID customer tenant is separate from the Azure resource directory.
  Email OTP, Google and Microsoft personal flow bindings/page options are
  verified. Actual provider exchange and work-school support remain gates.
- Developer Mode stays off by user choice; CI supplies native builds.
- Legal/privacy/name review and exact provider production settings remain launch
  gates. A compiled, sign-in-gated preview is not the signed-in MVP.
- Fresh live Cosmos census was empty; required feedback composite index and a
  conservative reserved preview-volume ledger were then provisioned. Finite
  quotas and API/engagement kill switches are source-tested, not monetary hard
  caps. Dedicated free resource-tenant guard/FIC and least-reader roles are now
  provisioned; one-way operational pause and reviewed Admin resume source tested.
  Actual main audit run37222479302 passed with `warning_cost_unknown`, no pause.
  Current Cost Management query is unavailable
  for this new subscription, not zero cost. Trial spending limit On/free SKUs are
  verified; billing/trial expiration approval remains a launch gate.

## Latest verification

Engineering source `b48bd73` passed full dual-architecture run37221239921 and
versioned release run37222046474; merged main is `54298a0`.
Public preview.2 downloads were independently verified:
ARM64 `8adbf9eadd2f457cd5f6a4606d1cca5c337decfb38cdcca539d72ab97a1a83bb`,
x64 `71b42f7de0324344defcf13e64fe484b103e4be732ae6ab2d7991b074bd8d9e8`.
Native normal sign-in is rendered, enabled and contains no synthetic banner.
Actual background Share invocation is rejected with `share_foreground_required`;
the covered-window input preflight sent no foreign input. No visible OS Share
pane/transmission is claimed. Customer/OS/launch gates are consolidated in
`docs/acceptance.md`, not requested incrementally.

121-test full serial Flutter suite passes, including Win32 notification
permission/transport, observed session/sign-in
consent, invitation retries/export,
opaque intent IPC, capped reminders and active-session clock boundaries.
Full analyzer is clean. API suite passes90; site/operator/deployment contracts
pass17; spend-guard
policy suite passes8. Native Share bridge compiles with the existing ARM64 SDK.
Live popup/API proof is
pending. No test fixture is represented as a real user login.
The offline window expires at exactly 30 days and checks a secure-storage
last-observed watermark. In-memory session access hides immediately at expiry or
resume failure; serialized credential writes cannot resurrect a signed-out cache.
Native screenshot timeline is kept privately, never copied with user account data.
Deployment run37217202261 passed at `5a28346`. Both native jobs in run37217202495
failed on Visual Studio's deprecated experimental coroutine headers. C++20
replacement runs37217695852 and37217961254 subsequently passed, including both
installer/protocol lifecycles and release-forbidden profiles. The newer native
toast adapter compiles locally with production warning/exception settings;
its replacement run37219658483 subsequently passed both full native
installer/protocol/profile jobs. Actual native permission preflight reported
NotificationSetting2 and clean teardown; notification history/removal/delivery
are still blocked by that OS gate.
Live Edge invite handoff, optional storage save/restore/remove and invalid-code
handling passed with no page errors; no app launch, customer login or referral
redemption was inferred.
The first main release-link deployment37223371502 exposed the SWA resource still
bound to the feature branch. The existing Free resource is now bound to main;
main-only, explicit-production, serialized deployment and all protected-route
smoke gates repair that integration.
Replacement run37223995243 subsequently passed from `0535358`; Azure reports
the default environment main/Ready/Free. Independent served-content checks
verified both preview.2 links, schema2 config checksum/version/expiry with the
experiment OFF, and all nine protected routes401 using actual methods.
Full final-main run37223995427 also passed, including both native architectures.

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
The separate runtime profile accepts `BLOOMSTEP_RUNTIME_REPORT` for a private
report and `BLOOMSTEP_RUNTIME_SHARE=1` to request the actual Share surface with
an example.com synthetic link. It never sends an invitation; inspect and cancel
the OS surface independently. A returned request is not evidence of transmission.
Use its synthetic Share button only while this app is foreground; background
requests are explicitly rejected. No other app or provider window is captured.

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
