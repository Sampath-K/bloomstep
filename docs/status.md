# MVP status and iteration ledger

**Engineering preview, not a completed or publicly usable MVP.** Identity,
cloud deployment and native background behavior require integration evidence.
This ledger is updated with verified outcomes, not inferred from source code.

| Iteration | Job | Current evidence / remaining gate |
| --- | --- | --- |
| 0 | Build, run, ship | Baseline shell CI green. Native plugin build requires Windows Developer Mode. New ARM64/x64 installer lifecycle matrix added; not yet observed green. |
| 1 | Plant first habit | SQLite tests and real widget journey pass: five starters, four recipe fields, three species, practiced celebration, restart-safe storage. |
| 2 | Check in | Tests pass for did/more/rest, idempotency, append edits/undo, local midnight. Widget tap/celebration/undo pass. Native measured latency pending. |
| 3 | Visual garden | Original vector plants and five stages, permanent attained growth, reduced-motion flag and semantics. Render/accessibility evidence being generated. |
| 4 | Local reminders | Windows plugin APIs verified in installed packages; toast/tray/autostart opt-in wired. Quiet-hour/cap/backoff rules tested. Real minimized/closed/restarted delivery and OS Focus observation pending; no success claim yet. |
| 5 | Sign in | Browser PKCE/state/nonce/JWT validation and Windows secure credentials implemented. Personal subscription approved; customer tenant/provider setup and real login pending. No fake login. |
| 6 | Sync | JWT Functions/Cosmos contract, issuer-subject partitioning, private responses, idempotent union, recipe LWW implemented. Client merge tests pass; live two-device integration pending. Settings sync and incremental scalability remain gaps. |
| 7 | Funnel | Explicit opt-in allowlisted event queue and API validation; no private text allowed. Full acquisition/install funnel, daily aggregates and four dashboards pending. |
| 8 | Feedback | Private local queue, status/replies UI, role-protected admin API/console implemented; real round trip, audited read access and deployment pending. |
| 9 | Invite | Copy/email/QR and safe static invitation link. Native OS share/deep-link install attribution and mutual reward pending. |
| 10 | Reflection | Four original questions, fortnight gate, deterministic Doctor, criteria-based graduation implemented. Not marketed as a validated SRBAI instrument. Graduation integration and weekly cadence pending. |
| 11 | Reconnect | Not yet implemented/observed. Must cap two nudges/absence and reset on return. |
| 12 | Website/update | Static landing/trust/invite/changelog and release-page link. Actual SWA deployment/download and update version detection pending. |
| 13 | Rating/privacy | Manual private rating queue, JSON export, local deletion, authenticated cloud deletion endpoint with race-resistant tombstone. Positive-moment prompt cadence, live deletion/response evidence pending. |
| 14 | Experiment | Bounded static config authored, intentionally disabled. Fetch/cache/experiment telemetry/guardrails and deployed live A/B pending. |

## Current external gates

- Personal subscription is now available. Never use the corporate development
  subscription. Only free SKUs/allowances, explicit subscription targeting.
- External ID customer tenant is separate from the Azure resource directory.
  Microsoft personal/work-school federation and Google OAuth credentials must
  be verified; email OTP is supported by customer user flows.
- Windows Developer Mode/plugin symlink permission is not yet confirmed.
- Legal/privacy/name review and exact provider production settings remain launch
  gates. A compiled, sign-in-gated preview is not the signed-in MVP.

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

Run `flutter analyze` and `flutter test --reporter expanded`. API:
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
| Duplicate remote events | Union by immutable client ID | Sync unit test |
| Invalid future/oversized API records | Reject, don't silently truncate | Schema tests; timestamp-skew integration pending |
| Cross-account API input | No client account field accepted | Strict schema tests; live adversarial API test pending |
| Telemetry free-text | Reject unregistered events/unknown fields | API contract tests |
| Client forged team status | Server owns received/status/replies | API contract tests |
| Deleted account + concurrent sync | Conditional account gate in same-partition transactional batch | Source implemented; Cosmos integration pending |
| Auth unavailable/offline | Local changes preserved, error explicit, no mocked identity | Sign-in gate widget test; real offline login pending |
| Quiet hours across midnight/caps | No delivery, <=3/day and <=1/habit/day | Rule tests; OS observation pending |
| Seven ignored prompts | Pause, explain opt-out | Source implemented; scheduler tests/OS observation pending |
| Large text/small screen/keyboard | Scrollable forms, labeled targets, no clipping | Widget checks in progress |
| Unsigned installer | Unknown publisher disclosed, hashes downloadable | Installer matrix pending |
