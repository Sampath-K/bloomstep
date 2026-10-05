# MVP exit matrix

**As of 2026-10-06.** This records observed acceptance against the approved
Flutter v0.4 scope and its 15-iteration plan. A green source test or published
preview is not treated as a green real-user journey. “Partial” means some
specified behavior has direct evidence but at least one required outcome is
still unverified; “blocked” means the next required evidence needs an action
outside the implementation session. No row below is inferred green from
fixtures, mocks, unauthenticated responses, or population data that was not
measured.

## Iteration exit conditions

| # | Original job | Status | Evidence already observed | Still required for green |
|---|---|---|---|---|
| 0 | Build, run and ship the Windows app | **GREEN (engineering)** | Preview.8 is published from main `d3b6adf315bc68520494f6c3d017c68411ac1150`; API, x64 and ARM64 CI, installer lifecycle, public installers and hashes passed. The verified ARM64 preview.8 installer upgraded the existing install and the app launched normally. | None for iteration 0's engineering definition. This does not make the product MVP complete. |
| 1 | Plant and persist a first tiny habit | **PARTIAL** | Builder, starter recipes, SQLite persistence and recovery are implemented and covered by source/CI. After upgrade, the existing account's garden tables were empty. | Create and read back a clearly labeled owner fixture in the running app; verify restart persistence and the under-90-second journey. |
| 2 | Check in and celebrate | **PARTIAL** | Did it / Did more / Not today, edit/undo and local-day/idempotency rules are implemented and covered by source tests. | Perform a live fixture check-in, edit/undo and read back its exact sync effects; verify the actual interaction timing and celebration in the app. |
| 3 | Grow a non-punitive garden | **PARTIAL** | Growth stages, positive return behavior and reduced-motion handling are implemented and covered by tests. | Observe real fixture-driven stages and a missed/rest day in the running app, including reduced motion/accessibility behavior. |
| 4 | Gentle Windows reminders | **BLOCKED** | Reminder scheduling and guardrail logic exist. The Windows notification setting was previously observed disabled; no toast delivery is inferred. | User-authorized per-app notification/foreground actions and real toast, quiet-hours, snooze, cap and withdrawal readbacks. No global setting change is authorized. |
| 5 | Sign in with an existing account | **PARTIAL** | A genuine existing session restored after upgrade and completed startup sync. The app remains sign-in-only; no fake login was used. | Record which provider actually completed the exchange and independently verify each required provider/OTP route and sign-out clearing; do not infer provider from session presence. |
| 6 | Keep the same garden across devices | **PARTIAL** | The running app wrote a fresh `lastSync` marker after authenticated sync GET, merge and session checks. This confirms startup session sync, not garden-record convergence. | Live owner fixture create/edit, API readback, second approved device/account isolation, offline/reconnect and conflict/idempotency checks. |
| 7 | Conversion funnel and dashboards | **PARTIAL** | Bounded opt-in acquisition/install instrumentation and privacy contracts are published; default-off experiment/config and protected routes were read back. | Complete the canonical funnel, consented population flow, daily aggregation and all four dashboards; verify with genuinely consented data and approved operator access. |
| 8 | Feedback and team response | **PARTIAL** | Feedback/status/reply contracts and support receipt/first-response source are implemented; no private customer feedback was queried. | Submit a clearly labeled owner fixture, verify actual user-visible status/reply and authorized team response/readback, then clean up only that fixture. |
| 9 | Invite and attribute a friend | **PARTIAL** | Link/QR and invitation flows are implemented. No invite was sent and no participant was contacted. | Verify copy/share/QR and invite redemption/attribution with an explicitly approved test participant; no communication or new identity without approval. |
| 10 | Learn, adjust and graduate habits | **PARTIAL** | Weekly reflection, deterministic Recipe Doctor, automaticity and graduation logic are implemented and source-tested. | Exercise the full live owner fixture journey over its actual time windows; no automaticity or graduation outcome is fabricated. |
| 11 | Kind reconnect nudge | **PARTIAL** | Reconnect logic and backoff contracts exist. A narrower, fresh-consent reminder-preference observation is published; it is not the full reconnect/notification loop. | Observe a genuine scheduled/reconnect nudge, delivery and unsubscribe with the necessary app/OS state; do not equate a plugin acknowledgement or preference observation with delivery. |
| 12 | Find, trust and install from the web | **PARTIAL** | Public website links to preview.8 ARM64/x64 installers with verified sidecars; changelog, trust disclosure, download and in-app update source are present. Preview.8 installation and launch were observed. | Observe the actual unsigned-download/SmartScreen experience and record it; finish the user-facing discover/install journey. No device-policy bypass or Store signing is claimed. |
| 13 | Rate, respond, export and delete | **PARTIAL** | A private JSON export and authenticated sync were previously observed on the preserved session; owner-scoped deletion contracts and tombstones are implemented. | Live rating/response plus fixture-only edit/export/API readback/deletion propagation and exact cleanup. No account deletion or existing-record mutation is authorized. |
| 14 | Safely run an experiment | **BLOCKED** | Remote-config schema/config is live and read back; the experiment is deliberately OFF. Sparse outcome suppression and activation thresholds are implemented. | Reviewed genuine cohort/guardrail evidence and explicit reviewed activation of the bounded experiment; verify actual assignment and outcome readback. |

## Canonical outcome targets

The v0.4 §20 targets are labeled initial hypotheses to recalibrate after four
weeks of data. They are **unmeasured**, not passed and not a separate
minimum-install-count release gate. In particular, no D7/D30/D90, conversion,
notification-disable, response-time, invite, rating, or crash-free percentage
is asserted from the small acceptance session.

| Spec target | Current evidence state |
|---|---|
| First launch → signed in ≥85%; signed in → first check-in same day ≥60% | **Unmeasured**; one restored session is not a population denominator, and no fixture check-in was made. |
| D7 practice ≥40%; D30 practice ≥25%; ≥15% of activated users graduate by D90 | **Unmeasured/not elapsed**; no cohort result or graduation claim. |
| Notification disable rate ≤10% over 30 days | **Unmeasured**; the new consented preference observation is not the original notification delivery/disable outcome. |
| Feedback first response ≤2 business days; ≤3★ review response ≤48 hours | **Unmeasured**; source support receipts/response metadata are readiness, not observed service-level results. |
| ≥0.3 invites per activated user at 30 days | **Unmeasured**; no invite population or participant actions. |
| Crash-free sessions ≥99.5% | **Unmeasured**; bounded opt-in categories do not constitute a complete native/process-death session census. |

The minimum contributor thresholds and reviewed cohort/guardrail evidence gate
**experiment activation/publication**, not a fabricated count of users required
to publish a preview. The original MVP still requires an experiment loop; it
remains incomplete while the experiment is OFF. No specification deferral is
implied.

## Current acceptance evidence and boundaries

- The installed app is Windows ARM64, registered as `0.1.0-preview.8`, and is
  open in the normal window. Preview.8 is unsigned; this is not a Store-signed
  product.
- Both existing support files matched their pre-upgrade SHA-256 values
  immediately after installation. A subsequent normal startup sync updated the
  SQLite database, as expected. The pre-fixture baseline was captured read-only:
  habits, check-ins, reflections, feedback, events, sync-state and deletion
  queues were empty; six settings rows existed. No fixture was written.
- The fresh `lastSync` marker was written after launch. `SyncService` writes it
  only after the authenticated request/merge sequence completes. This proves
  this session's startup sync, not any record-level or second-device sync.
- UI Automation exposed only a generic pane with no controls; no UI fixture
  action was attempted. The user was unavailable for the exact Plant action.
  Do not seed SQLite directly or report a fixture as created.
- The private evidence record is
  `preview8-pre-fixture-acceptance.json` in the implementation session's
  persistent session files. It contains hashed support-file fingerprints and
  no account IDs or habit text.

## Remaining workstreams, owner and definition of done

| Workstream | Owner / next action | Definition of done |
|---|---|---|
| Existing-session habit loop | User: create the specifically labeled disposable recipe through the open app when available; implementation session: resume checks afterward. | Actual app UI create/check-in/edit/undo/reflection/feedback/export/API round trips; delete only the exact new owner-scoped IDs and verify local/server cleanup. |
| Private support/Admin acceptance | User: identify the intended operator account; implementation session: perform authorized role/readback checks in app-managed channels. | Real least-privilege Admin access, feedback/reply/receipt import-readback and denial tests; exact test records cleaned up. |
| Second identity/device and referrals | User: select a genuine disposable second identity/device and participant scope; implementation session: own the protocol tests. | Account isolation, offline/reconnect/conflict, invite redemption and attribution verified with exact cleanup; no current account erasure. |
| Native Windows surfaces | User: bring Bloomstep forward and authorize only desired per-app notification and Share/Narrator interactions; implementation session: observe actual results. | Toast/actions, caps/quiet hours/snooze/unsubscribe and Share cancellation/keyboard/accessibility verified without global policy changes or sent messages. |
| Population measurement and experiment | Product controller/operator: approve the intended cohort review and activation; implementation session: run only the reviewed bounded experiment and read back outcomes. | Genuine consented cohort/guardrails reviewed, the OFF-by-default experiment explicitly activated and its result measured. No proxy or synthetic population. |
| Public launch trust and quality | Controller/user: supply accurate legal/contact/provider/age/retention and billing/unsigned-policy decisions; implementation session: implement and verify those exact choices. | Reviewed public disclosures/provider setup, spend-safe deployment, SmartScreen decision and measurable crash-free evidence meeting the unchanged spec target. |

## Overall decision

**Full MVP exit: NOT GREEN.** The release and upgrade loop is green as
engineering evidence; normal app restore and startup authenticated sync are
green for this one existing session. The end-user habit loop, live platform
surfaces, complete telemetry/feedback/referral/learning/experiment loops and
original population quality targets are not all green. The immediate next
manual blocker is a single disposable recipe created through the running app;
without it, record-level acceptance and safe exact-ID cleanup cannot proceed.
