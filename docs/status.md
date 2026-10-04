# MVP status and iteration ledger

**Engineering preview, not a completed or publicly usable MVP.** Identity,
cloud deployment and native background behavior require integration evidence.
This ledger is updated with verified outcomes, not inferred from source code.

| Iteration | Job | Current evidence / remaining gate |
| --- | --- | --- |
| 0 | Build, run, ship | Public unsigned `v0.1.0-preview.3` engineering installers from merged green `df085e3`; both public downloads/hash checks pass. Actual local ARM64 preview.2 -> preview.3 upgrade, version/PE/protocol ownership/default-off receipt+marker absence/normal+repeat launch/app-only sign-in capture pass. Versioned dual jobs pass actual interactive consent/install/entry/owned-uninstall. SmartScreen/customer acceptance remain gates. |
| 1 | Plant first habit | SQLite tests and real widget journey pass: five starters, four recipe fields, three species, practiced celebration, restart-safe storage. |
| 2 | Check in | Tests pass for did/more/rest, idempotency, append edits/undo, local midnight. Actual MSAA Did-it action in the newer synthetic native garden exposed celebration in67ms (<=300ms); not a customer-use measurement. |
| 3 | Visual garden | True ARM64 synthetic profile captures inspected: readable banner and reserved Plant bar fixes observed. Responsive/200%-text regressions pass. Actual Flutter child HWND exposes38 MSAA nodes including labeled action buttons; UIA is empty, not evidence of no MSAA support. Narrator interaction remains unobserved. |
| 4 | Local reminders | Real runtime probe observed tray bounds/hidden window and clean teardown. It exposed the dependency's unpackaged Win32 history/individual-cancel limitation. Native explicit-AUMID/grouped WinRT request/history/removal now replaces that path, with OS permission preflight and surfaced errors. This machine reports NotificationSetting2 (DisabledForUser); no OS settings changed or delivery claimed. New adapter full native/link/removal and popup/Focus/restart observations remain pending. |
| 5 | Sign in | Email OTP, Google and Microsoft personal-account providers are now created AND enabled on the actual native/console user flow. MSA issuer/discovery/client/scope/auth type and both callbacks verified; real PKCE sign-in page HTTP200 includes all three options. Actual provider login/token exchanges remain unobserved, not inferred from setup. No fake login. |
| 6 | Sync | Personal SWA Free/Cosmos free tier provisioned; live unauthenticated sync API returns 401. SQLite v4 preserves durable fingerprints and adds typed event properties; partial upload/concurrent edits, consent purge and account isolation tested. Live probes exposed SWA replacing Authorization and reserved admin routes: dedicated client-token header and team routes fixed in source, deployment smoke gate added. Actual authenticated two-account/device/offline round trips remain pending. |
| 7 | Funnel | Versioned48-event registry and strict metadata, four typed dashboards/minimum50. Default-off browser/installer local receipts and independently consented explicit account linkage preserve original times/IDs; strict privacy/expiry/retry/account tests and actual browser+dual installer observations pass. Bounded opt-in Dart categories are not a native-death census; crash-free remains null. Actual main worker37222477262 wrote one snapshot; worker rejected by garden/team. Scheduled tick/customer population/OS-delivery remain unobserved. |
| 8 | Feedback | Private queue/status/replies; audited pagination/retry/deletion protections tested. Real browser PKCE operator source and separately registered SPA/consent/flow binding now prepared; credentials memory-only, no pasted token. Actual selected customer Admin and feedback/rating round trip still pending. |
| 9 | Invite | Authenticated opaque invitations, server-owned attribution, first-positive-practice mutual cosmetic saga and owner-only receipts implemented/tested. Native copy/email/QR/Windows Share UI, opt-in recipe card, accept/decline, cached retry IDs and export integrated. Per-user protocol and private IPC/inbox preserve intent across install/sign-in; web handoff/storage is explicit. Live customer reward and OS-share observations remain pending. |
| 10 | Reflection | Weekly deterministic Doctor works independently of fortnight naturalness sliders; cooldown checked before collecting scores. Real SQLite graduation/spacing tests pass. Not a validated SRBAI instrument. Native learning interaction still pending. |
| 11 | Reconnect | Three/seven-day rule, max two/absence, activity reset and scheduler shared quiet-hour/day caps implemented; rules tested. Windows delivery and closed-app behavior not observed. |
| 12 | Website/update | Main consent-safe site/API deployment37230838798 passed/served HTTP200; public preview.3 ARM64/x64 installers/hash checks and local2->3 upgrade observed. Updated preview.3 landing links/changelog are source-validated; final live-link deployment readback pending. Manual trusted version/channel checks, never auto-execute; silent QA is not SmartScreen proof. |
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

Exact instrumentation head `e1a1c6e` passed dual native37230015869 and PR checks;
PR2 merged as `df085e3`. Actual main deployment37230838798 and main native
37230838888 passed; versioned release37230846408 published preview.3.
Both actual interactive wizards exposed unchecked consent, explicit owned
synthetic selection, real installation/installed first-launch/shown-signin
observations, matching ownership marker and owned receipt/uninstall cleanup.
Silent/default-off install/upgrade/entry tests pass. Earlier Inno parser and
QA Next-caption failures were diagnosed/repaired, never waived.
Public preview.3 downloads independently verified:
ARM64 `adea0a098777d4e5b6522832cb687beb8c9feac276748dbdcdcb79599e14582c`,
x64 `1548643d48f078b287dbb35ec50d22db8def2f0488dd11576df1941bbee7854c`.
Actual local per-user preview.2 -> preview.3 upgrade verified changed executable,
installed version/PE ARM64/protocol, absent default-off receipt/marker,
responsive normal/repeat launch and inspected app-only sign-in capture with
new receipt-clear control, enabled real sign-in and no synthetic banner.
Actual background Share invocation is rejected with `share_foreground_required`;
the covered-window input preflight sent no foreign input. No visible OS Share
pane/transmission is claimed. Customer/OS/launch gates are consolidated in
`docs/acceptance.md`, not requested incrementally.

138-test full serial Flutter suite passes, including strict receipt linking,
installer ownership, consent-scoped error hooks
and Win32 notification
permission/transport, observed session/sign-in
consent, invitation retries/export,
opaque intent IPC, capped reminders and active-session clock boundaries.
Full analyzer is clean. API suite passes91; site/operator/deployment/packaging contracts
pass23; spend-guard
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

## Instrumentation continuation (not population evidence)

Runtime diagnostics now require current account consent, preserve original
framework presentation/unhandled semantics, detach on scope close, and cap
observations at ten per session. Only fixed category/source/session metadata
is stored; no error text, stacks or native/process-death census. Opt-out purges
events and queued event sync. The health dashboard deliberately retains a null
crash-free rate. New acquisition/install local receipt and explicit account-link
source passes synthetic privacy/consent/expiry/retry/surface tests. Actual isolated
Edge checkbox/gesture/export/opt-out/expiry observations also pass, with external
download navigation prevented for QA. Dual native/interactive installer,
release and actual local installed entry verification now pass; no users, completed
funnel or measured cohort are inferred. Contract details are in `measurement.md`.

| Workstream | Owner | Next action | Definition of done |
| --- | --- | --- | --- |
| Acquisition/install observation | Implementation session | Source/native/release/browser/local-install verified; finish final preview.3 live link readback | Default-off receipt/link/privacy/expiry/retry/account contracts and real dual installer+local normal entry pass; subsequent genuine signed-account roundtrip requires trusted session |
| Runtime error observation | Implementation session | Coverage ready within stated limits; population/native-death quality target remains unproved | Bounded consent-scoped hooks and strict server allowlist verified; never claim full crash census or >=99.5% crash-free |
| Customer integration | Implementation session, after trusted-browser customer authorization | Real provider exchange, account/device/offline API round trips and readback/cleanup | Actual two-account isolation, feedback/rating/reply/referral/delete results; no fixtures substituted |
| Operator/OS/launch decisions | Customer/controller | Select customer Admin; authorize OS permission; approve legal/provider/billing/unsigned trust | One consolidated final acceptance batch; agent owns subsequent component checks |
| Experiment/population | Product operator | Review genuine consented cohort and guardrails | Real bounded experiment activated/evaluated only after review; remains OFF until then |

Minimum50 is a dashboard publication/suppression threshold, not an excuse to
omit instrumentation or an independent minimum-user download requirement.
Genuine cohort/guardrail review gates experiment activation. The original
spec includes one bounded experiment; OFF/config-ready is not completion of
that requirement, and no scope deferral has been assumed.

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
