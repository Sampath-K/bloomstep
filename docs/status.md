# MVP status and iteration ledger

**Engineering preview, not a completed or publicly usable MVP.** Identity,
cloud deployment and native background behavior require integration evidence.
This ledger is updated with verified outcomes, not inferred from source code.

## Finite launch backlog

**Nine open launch-readiness task packages, plus one separate elapsed-user
evidence/experiment workstream.** Counts are packages, not estimates of nine
small changes. All code/process readiness and independently authorized live
checks must finish; human-only decisions cannot silently be inferred. Planned
library/education/animation enhancements are frozen outside launch scope.

| # | Package / owner | Next action and definition of done | Dependency / class |
| --- | --- | --- | --- |
| 1 | Real single-account private loop — implementation session | Normal preview.5 upgrade/restored-session sync observed; repair native export automation in isolation before a coordinated interactive slot for labeled own recipe/check-in/edit/undo/reflection/feedback/rating/export readbacks, then delete ONLY exact owned fixtures and verify remote suppression/cleanup and preservation of customer content. Export locator failed; exact owned modal safely canceled, no save or fixtures. | Preview.5 installed; foreground testing paused for customer self-use. Engineering/live acceptance, not a new login-permission wait. |
| 2 | Target-aligned telemetry and goal/actual UI — implementation session | Contract-first original attempt-success, day0 activation, D7>=3 check-ins, D30 days23-30 frequency,30/60/90 graduated-habits/activated-user north star and D90 graduation,30-day disable/invitation and support/low-star SLA measures. Expose goal, numerator, denominator, window/maturity, coverage, evidence and suppression; never substitute current exact-day proxies. | 1 critical path first; resolve denominator/coverage/business-calendar definitions against original spec. Engineering; genuine results separately await cohorts. |
| 3 | Session/native health coverage — implementation session, privacy/controller review | Prove a $0 bounded privacy-safe session lifecycle/native-fatal capture/recovery approach with no habit text/message/stack/token capture; validate normal/fatal/uncertain exits, offline/retry/consent and coverage denominators. Unclean exits are not automatically crashes; opt-in sample is not all users. Establish original99.5% criterion/canary evidence and explicit launch interpretation, not an inferred passing rate. | Native feasibility spike, policy/coverage decision, then source/release and controlled/live observation. Engineering + decision; current bounded Dart categories insufficient. |
| 4 | Genuine identity/device/offline/recovery/isolation — implementation session, customer approves identities/destruction | Real approved second-account/device state, foreign-account denial, offline/restart/reconnect/idempotency/conflict/revocation/recovery and separately approved disposable-account deletion, with actual API readback/cleanup. Preserve current session; no forced sign-out/new identity/account erasure from launch urgency. | 1 and explicit additional identity/offline/destructive test decisions. Mixed acceptance. |
| 5 | Private operator/team/referral round trips — implementation session, customer selects operator and communication scope | Explicit customer operator before any Admin assignment; trusted-browser operator auth, private feedback/rating pagination/status/reply and owner deletion readback. Separately authorized invite/redemption/first-practice/cosmetic/retraction/cleanup acceptance with genuine participants, no automatic message sending. | 1, selected operator/Admin permission, approved participants/link/communication/cleanup boundaries. Mixed acceptance. |
| 6 | Windows surfaces — implementation session, customer approves OS/surface actions | Observe actual foreground/background/tray/snooze/cap/quiet-hours/default-silent reminder behavior, then authorized Share cancellation and keyboard/Narrator/reduced-motion usability. No success from a toast API acknowledgment alone; no global permission change or foreground-policy bypass. | 1; explicit notification/OS/Narrator/Share decisions. Mixed acceptance. |
| 7 | Worker freshness/cron/guard process — implementation session | Verify latest completed-day snapshots, missing/stale/invalidation/backfill labels and actual scheduled tick against the committed cron; guarded bounded worker/customer-role isolation and readback. Keep spend/billing unknown until authoritative review. | Deployed API/service actor already prepared; real scheduler clock/execution plus1 cleanup/invalidation. Engineering/process + elapsed tick. |
| 8 | Production trust/auth/legal/budget — customer/controller, implementation supplies exact checks | Review production scope/provider publishing/consent branding/email boundary, controller/contact/privacy/age/retention/processors/support/name claims, exact subscription/trial/free-SKU/billing and unsigned download/SmartScreen policy. No domain/paid upgrade, fake provider coverage or inferred controller/operator. | Source/evidence supplied; explicit human decisions. No paid change implied. |
| 9 | Release/deploy/rollback/security freeze — implementation session, customer final UX | Review exact source provenance/dependency/security/permission contracts, reproducible dual architecture builds/install/uninstall/storage/schema upgrade and compatible rollback/recovery; actual served assets/protected routes/config/OFF hashes; preserve data/session and reconcile all requirements/edge cases/evidence. Consolidated customer UX acceptance after developer work, not one test per increment. | 1-8 code/process decisions; current exact PR/main/tag/API/dual installer evidence is partial, not final launch sign-off. |

Separate **workstream10: genuine elapsed-user evidence** keeps D7/D30/D90
targets, native crash-free quality measurement and a reviewed bounded experiment
honestly pending. Targets are not fabricated or waived; capture/formulas and
operational readiness must be completed before collecting outcomes. This does
not assert every launch must wait90 days: product hypotheses mature afterward,
while true safety/quality launch gates need their explicit approved canary/
production interpretation. Experiment remains OFF until genuine reviewed
cohort/exposure/guardrail evidence, not an invented install-count release gate.

**Timing:** observed dual native build/test/package/lifecycle checks take
roughly8-13 minutes per version once code is ready, followed by deployment/
upgrade/readback. Total coding/acceptance ETA is not grounded yet: metric
definitions, native coverage feasibility and human decisions remain unresolved.
No same-day completion guarantee. Implementation continues independently safe
work; original feature gaps are not reassigned to the user as population gaps.

## Current evidence

**Latest genuine integration observation:** After the preview.5 deletion upgrade, the
normal installed app restored an available session and opened its garden.
Fresh startup displayed "Saved on this device and synced", not "Sync needs
attention". That outcome is set only after the actual sync request returns
HTTP200 and completes the account-scoped merge, not from a cached last-sync
setting. This establishes one real restored-session/API readback, not a freshly
observed provider exchange, two-account isolation or full private-loop
acceptance. Verification inspected only fixed public status/action labels;
no account text, credential store, token, payload or garden screenshot was
recorded. Reversible test approval was subsequently received; fixture writes
are not yet run: export automation failed and foreground testing is paused.
The owned Save As dialog was safely canceled and the app remained responsive.
Operator roles, real account deletion and OS changes still
require their separate authorization.

**Historical preview.4 authorized read-only acceptance:** After explicit signed-account reversible
test approval, the implementation session invoked the normal app's Sync now and
Settings/Export my data (JSON), saved an actual export through its owned native
dialog, and verified schema1, single-account row ownership, fresh lastSync and
included live server invitation export without an offline warning. Customer
content remains private; no fixture record or existing-customer edit was made.
Mutation testing exposed a cleanup gap before creating records: this candidate
has no individual habit/feedback removal or sync deletion tombstones. Only
whole-local-garden/account wipes exist, and check-in Undo preserves append-only
history. Those are not reversible fixture cleanup. Controlled habit/feedback
writes remained gated before the user explicitly selected **owner-only
individual habit/feedback deletion with cross-device handling**. That feature
subsequently shipped in preview.5 through PR5 merge `e844fea`. No
fixture has been created, and no customer-existing content/session, Admin,
account deletion, identity switching, OS permission or invite sending is
authorized by this feature approval.

| Workstream | Owner / next action | Definition of done / current evidence |
| --- | --- | --- |
| Owner-record deletion | Implementation session: finish isolated export automation and coordinated live fixture checks | PR5 merge `e844fea`, API-first deploy37286713837, main37286714078 and tag/release37286791882 all SUCCESS. Dual public unsigned hashes verified; normal ARM644->5 upgrade and genuine restored-session sync observed.156 Flutter/99 API tests include migration, canonical-ID convergence, races, exact10000-row cleanup retry,1000-marker caps, dependencies and notification withdrawal. No live customer deletion acceptance yet; fixtures0. |
| Reversible signed-account acceptance | Implementation session: create only explicitly labeled own fixtures after deployed cleanup is available, then remove them | Normal app sync/check-in/edit/undo/reflection/feedback/rating/export, relational/API round-trip/readback and only own fixture cleanup; preserve existing customer content. Genuine sync/schema/account-consistent export already observed. |
| Skill/confidence learning enhancements | Product/content review, then separately sequenced implementation | Planned only in product-spec addendum; original versioned catalog/citations, optional short self-selected education, privacy/accessibility/performance acceptance. No new feature readiness claim. |

Latest developer-owned workflow recheck: scheduled spending guard37271400930
(October 5) completed successfully. This is workflow history, not a new billing
or cost-zero proof. Scheduled aggregate37288175463 completed successfully on
October5 at09:09UTC: one prior-UTC-day snapshot acknowledged, real worker
token rejected by garden/team routes. Committed cron is02:20UTC daily; this
observed scheduled run was delayed, so exact firing time/freshness is not
guaranteed. Private metric values were not fetched; snapshot completeness,
late-event invalidation/backfill and customer-role readback remain separate.

Product-owned branding shipped in PR4 merge `5b675a5` and unsigned
`v0.1.0-preview.4`. Exact source PR/push, merged-main and versioned release
`37265253407` API/ARM64/x64 pass, including142 Flutter tests per architecture and
real dual native installer lifecycle/consent/storage-upgrade proofs. Review caught
metadata-derived storage relocation before distribution: startup pins the
existing namespace before instance/session/garden, and disables unpublished
pre-v4 migration. Actual isolated Windows v4 DPAPI synthetic upgrade readback
preserves its encrypted file. Production branding deployment `37265236789`,
actual served text/three exact asset hashes/render, dual public downloads/hashes,
normal ARM64 preview.3->4 upgrade/title/icon/sign-in/native metadata/protocol/
repeat-launch and unchanged namespace are verified. No customer store was read.
Final preview.4 website-link deployment `37266324082` passed with actual dual
links/downloads/changelog HTTP200, schema2/OFF/unexpired configuration and nine
protected routes401 readback. Acceptance and
Google verified/published OAuth branding remain genuine gates.

| Iteration | Job | Current evidence / remaining gate |
| --- | --- | --- |
| 0 | Build, run, ship | Public unsigned `v0.1.0-preview.5` owner-deletion installers from merged green `e844fea`; both public download/hash checks pass. Actual normal ARM644->5 upgrade/version/PE/protocol/stable namespace and restored-session sync observed. Prior preview.4 branding/installer lifecycle evidence retained below; SmartScreen/customer acceptance and live deletion remain gates. |
| 1 | Plant first habit | SQLite tests and real widget journey pass: five starters, four recipe fields, three species, practiced celebration, restart-safe storage. |
| 2 | Check in | Tests pass for did/more/rest, idempotency, append edits/undo, local midnight. Actual MSAA Did-it action in the newer synthetic native garden exposed celebration in67ms (<=300ms); not a customer-use measurement. |
| 3 | Visual garden | True ARM64 synthetic profile captures inspected: readable banner and reserved Plant bar fixes observed. Responsive/200%-text regressions pass. Actual Flutter child HWND exposes38 MSAA nodes including labeled action buttons; UIA is empty, not evidence of no MSAA support. Narrator interaction remains unobserved. |
| 4 | Local reminders | Real runtime probe observed tray bounds/hidden window and clean teardown. It exposed the dependency's unpackaged Win32 history/individual-cancel limitation. Native explicit-AUMID/grouped WinRT request/history/removal now replaces that path, with OS permission preflight and surfaced errors. This machine reports NotificationSetting2 (DisabledForUser); no OS settings changed or delivery claimed. New adapter full native/link/removal and popup/Focus/restart observations remain pending. |
| 5 | Sign in | Real Google/MSA callback mismatches corrected: operator saved exact Google Authorized redirect URI; MSA narrowly added with authorized Graph/preserved entries/readback. Fresh isolated expected clients/callbacks reach BOTH credential forms without mismatch. Genuine exchanges remain unverified. Actual default/en-US hosted Bloomstep wordmark, favicon and product text applied; English/French-browser fallback verified. Google published/verified consent branding remains an operator gate. |
| 6 | Sync | Personal SWA Free/Cosmos free tier provisioned; live unauthenticated sync API returns 401. SQLite v4 preserves durable fingerprints and adds typed event properties; partial upload/concurrent edits, consent purge and account isolation tested. Live probes exposed SWA replacing Authorization and reserved admin routes: dedicated client-token header and team routes fixed in source, deployment smoke gate added. Actual authenticated two-account/device/offline round trips remain pending. |
| 7 | Funnel | Versioned48-event registry and strict metadata, four typed dashboards/minimum50. Default-off browser/installer local receipts and independently consented explicit account linkage preserve original times/IDs; strict privacy/expiry/retry/account tests and actual browser+dual installer observations pass. Bounded opt-in Dart categories are not a native-death census; crash-free remains null. Actual main worker37222477262 wrote one snapshot; worker rejected by garden/team. Scheduled tick/customer population/OS-delivery remain unobserved. |
| 8 | Feedback | Private queue/status/replies; audited pagination/retry/deletion protections tested. Real browser PKCE operator source and separately registered SPA/consent/flow binding now prepared; credentials memory-only, no pasted token. Actual selected customer Admin and feedback/rating round trip still pending. |
| 9 | Invite | Authenticated opaque invitations, server-owned attribution, first-positive-practice mutual cosmetic saga and owner-only receipts implemented/tested. Native copy/email/QR/Windows Share UI, opt-in recipe card, accept/decline, cached retry IDs and export integrated. Per-user protocol and private IPC/inbox preserve intent across install/sign-in; web handoff/storage is explicit. Live customer reward and OS-share observations remain pending. |
| 10 | Reflection | Weekly deterministic Doctor works independently of fortnight naturalness sliders; cooldown checked before collecting scores. Real SQLite graduation/spacing tests pass. Not a validated SRBAI instrument. Native learning interaction still pending. |
| 11 | Reconnect | Three/seven-day rule, max two/absence, activity reset and scheduler shared quiet-hour/day caps implemented; rules tested. Windows delivery and closed-app behavior not observed. |
| 12 | Website/update | Final preview.4-link deployment37266324082 from `2dd1250` passed. Actual live dual links/downloads/changelog HTTP200, schema2/OFF/unexpired config and all nine method-correct protected endpoints401. Isolated Edge branding/favicon/operator render observed; earlier consent checkbox/click/clear proofs retained. Public installer hashes/local3->4 upgrade pass. Manual trusted updates, never auto-execute; silent QA is not SmartScreen proof. |
| 13 | Rating/privacy | Positive-moment prompts wait for celebration and persist a 120-day cadence even when dismissed; rating text optional. Export/account isolation/cleanup tested. Cloud deletion tombstone/races tested against backend fixtures, not live Cosmos user deletion. |
| 14 | Experiment | Strict schema2/checksum, monotonic version, account cache, seven-day expiry and explicit control-mode warnings tested; compiled API origin, device timing toggle and actual-callback-only exposure. Bounded copy experiment remains OFF until genuine reviewed cohort/guardrail evidence, not fabricated data. |

## Current external gates

- Personal subscription is now available. Never use the corporate development
  subscription. Only free SKUs/allowances, explicit subscription targeting.
- External ID customer tenant is separate from the Azure resource directory.
  Email OTP, Google and Microsoft personal flow bindings/page options are
  verified, but actual Google/MSA acceptance failed callback registration.
  Both registrations corrected and isolated credential entry verified; genuine
  provider exchanges remain gates. Work-school support is separate.
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
Final site-link source `ba0af16` passed deployment37231886402; actual served
preview.3 dual links/consent/changelog and all nine protected routes401 verified.
Final main dual-native/API run37231886710 also passed at that exact source.
Isolated Edge observed real live default-off/consent/download gesture/clear;
navigation was prevented only for QA, so no download completion was inferred.
Current live config schema2/version2/checksum/not-expired/experimentOFF was
independently read back. Acceptance recheck observed actual scheduled guard
run37238140888 passing with `warning_cost_unknown`, cost null and no pause.
An aggregate scheduled tick remains unobserved.
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
| Acquisition/install observation | Implementation session | Independent implementation/release/live-link work verified; next genuine signed-account readback after authorization | Default-off receipt/link/privacy/expiry/retry/account contracts, real dual installer/local entry, fresh release/public hashes and deployed surface pass; live linked-account roundtrip/revocation requires trusted session |
| Runtime error observation | Implementation session | Coverage ready within stated limits; population/native-death quality target remains unproved | Bounded consent-scoped hooks and strict server allowlist verified; never claim full crash census or >=99.5% crash-free |
| Customer integration | Implementation session, after trusted-browser customer authorization | Real provider exchange, account/device/offline API round trips and readback/cleanup | Actual two-account isolation, feedback/rating/reply/referral/delete results; no fixtures substituted |
| Operator/OS/launch decisions | Customer/controller | Select customer Admin; authorize OS permission; approve legal/provider/billing/unsigned trust | One consolidated final acceptance batch; agent owns subsequent component checks |
| Experiment/population | Product operator | Review genuine consented cohort and guardrails | Real bounded experiment activated/evaluated only after review; remains OFF until then |

Minimum50 is a dashboard publication/suppression threshold, not an excuse to
omit instrumentation or an independent minimum-user download requirement.
Genuine cohort/guardrail review gates experiment activation. The original
spec includes one bounded experiment; OFF/config-ready is not completion of
that requirement, and no scope deferral has been assumed.

No safe independent implementation/distribution work remains for this
instrumentation increment. Full MVP remains incomplete: real provider and
two-account/device/offline/private-loop readbacks, selected operator, authorized
OS delivery/Share/Narrator and launch approvals remain genuine gates. The
original native/process-death/full-session crash-free>=99.5% quality evidence
and live bounded experiment/cohort are not supplied by optional diagnostic
categories or configured OFF controls. Billing remains unknown. As of the
acceptance recheck, scheduled guard37238140888 is observed; an aggregate
scheduled tick is not. The implementation session owns all component/API
readbacks and cleanup once the consolidated human-only gates are supplied.

## Acceptance callback defect (October 5)

The customer's real Google and Microsoft personal-account attempts both failed.
Fresh isolated unauthenticated traversal captured only public upstream client
identifiers and the exact shared callback
`https://<tenant-id>.ciamlogin.com/<tenant-id>/federation/oauth2`.
The native loopback is downstream and must not be registered at Google.
MSA's two registered subdomain callbacks did not include the actual canonical
host. The implementation session added only that exact callback using existing
authorized Graph access and verified all prior entries remained. Fresh isolated
MSA navigation then reached credential entry without redirect mismatch;
no credentials were entered and no successful exchange is inferred.
The Google operator subsequently saved the exact Authorized redirect URI.
Fresh isolated traversal now verifies expected clients/canonical callbacks and
credential entry without mismatch for BOTH providers. No credentials were
entered, and no successful exchange is inferred. A fresh app-start Sign in
securely attempt is required; the failed tab's old state cannot be reused.
The implementation session owns actual callback/integration/readback after
trusted-browser customer authentication.
Provider acceptance and full MVP remain incomplete. The registration-only repair
did not require a native release; the later authorized branding increment ships
the new preview.4 candidate described below.

## Authorized branding increment

The real hosted broker page formerly showed "BLOOMSTEP CUSTOMERS"; Google's
own page actually showed "continue to ciamlogin.com". Authorized no-cost Graph
branding now supplies Bloomstep's original wordmark/favicon, product headings,
signup/account/OTP-page strings and truthful credential/domain explanation.
Actual default locale0 and en-US writes/readbacks succeeded; fresh isolated
English and French-browser fallback both load the245-by-36 wordmark and show
"Sign in to Bloomstep", without the previous Customers fallback.
No auth screenshot, credentials, issuer/callback/secret/contact/license change.
The platform's generic localized browser-tab title remains unchanged.

Native window/file/product scaffold defaults, original flower icon, native
domain explanation/callback error, invitation email subject and site/operator
labels shipped as one coherent tested branding increment. Installed normal
preview.4 title/original flower icon/native metadata/service-domain explanation
and sign-in-only screenshot are observed, without initiating login or reading
customer stores. Actual previous Windows support namespace and repeat-launch
ownership are preserved. Public unsigned installer SHA-256:

- ARM64: `db371308664a27d70f5944ea4f8f6b190ca1398522f8345bff5e7aaee8bf7b3a`
- x64: `dc7c431323cf04329b57eac34fa28e743a662858d3c96ff3166537f9e0017c01`

Exact head PR `37264394120`, push `37264391076`, merged-main `37265236894`
and tagged release `37265253407` API/ARM64/x64 jobs pass. Production branding
deployment `37265236789` and actual HTTP/render/asset hashes pass; final download
links are updated only after published artifacts and checksums were verified.
Google verified/published
consent name and actual Microsoft-hosted OTP email remain external branding
gates, not fixed by Entra display text. No paid custom domain/Front Door/relay
or fabricated legal contact is created. See `deployment.md` for exact controls.

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
