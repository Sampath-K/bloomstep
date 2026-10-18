# Independent analytics review

## Baseline and verdict

- **Candidate:** `83fba1b30a483337760885d6fc34516c430faee0`
- **Source tree:** `5b2eb392aff651f15dfd3f34b987e1b1282dc098`
- **Role:** Analytics — success metrics, privacy-respecting measurement, experiment readiness.
- **Verdict: CHANGES_REQUIRED**
- **Findings:** 1 high, 2 medium, 1 low; all **OPEN**.

This is a source-review recommendation, **not a release sign-off**. No risk was accepted. No installer was executed; no merge, release, deployment, production collection, or remote-resource operation was performed.

## Scope and method

Read `docs/release-governance.md` and `release/roles.json`. Reviewed independently without reading other role reviews or shared drafts.

Inventoried the repository, then traced role-relevant paths:

1. Website consent → anonymous collection and separate receipt export.
2. App consent → SQLite event creation → authenticated outbox → API retention/deletion filtering.
3. Account events → funnel, retention, target-aligned goals and private presentation.
4. Website experiment consent → assignment, exposure, outcomes, withdrawal and worker decisions.
5. App experience assignment, actual-render observations, follow-up and explicitly unavailable analysis.
6. Tests and acceptance tooling, distinguishing synthetic source checks from live evidence.

This was a bounded, repository-wide **role review**, not a claim that every platform/generated file received line-by-line inspection.

### Actual files inspected

Ranges indicate partial inspection.

| Area | Files |
|---|---|
| Governance/contracts | `docs/release-governance.md`; `release/roles.json`; `api/package.json`; `api/src/contracts.mjs` |
| Measurement documentation | `docs/measurement.md`; `docs/experiments.md`; `docs/app-experiments.md`; targeted sections of `docs/funnel-telemetry.md` |
| App collection/store | `lib/core/garden_store.dart` — check-in, consent, event creation, receipt import, export and outbox sections; `lib/core/measurement_receipt.dart`; `lib/core/experience_store.dart` |
| App services/UI | `lib/services/session_events.dart`; `lib/services/session_diagnostics.dart`; `lib/services/installer_measurement.dart`; `lib/services/sync_service.dart:1–230`; `lib/services/analytics_sandbox.dart:1–220`; `lib/features/garden/measurement_controls.dart:1–167`; `lib/features/garden/garden_screen.dart:1080–1120` |
| API aggregation | `api/src/functions.mjs`; selected sections of `api/src/backend.mjs`, including ingestion, deletion filtering, bounded scans, metrics and snapshots; `api/src/dashboards.mjs`; `api/src/goals.mjs`; `api/src/aarrr.mjs`; `api/src/engagement.mjs`; `api/src/reminder-cohorts.mjs`; `api/src/experience-experiments.mjs` |
| Website/experiments | `site/customer.mjs`; `site/experiment-client.mjs`; `site/aarrr-panels.mjs`; `api/src/website-funnel.mjs:1–190,202–399`; `api/src/experiments.mjs:1–285`; `api/src/experiment-policy.mjs` — policy, assignment, statistics, evaluation and application sections |
| Tests | `api/test/goals.test.mjs`; `api/test/experiments.test.mjs:1–100`; `test/telemetry_test.dart:1–140,255–282`; `test/site_console_test.mjs:1–85`; `test/measurement_packaging_test.mjs`; import/initial sections of `test/analytics_sandbox_test.mjs` and `test/reminder_panels_test.mjs` |
| Tools/operations | `tool/funnel_acceptance.mjs:1–150`; `tool/experiment_acceptance.mjs:238–280` and withdrawal scenario search; `.github/workflows/aggregates.yml`; relevant sections of `tool/analytics_site_build.mjs`, `tool/analytics_config.mjs`, `tool/acquisition_snapshot.mjs`, `tool/analytics_ga4_staging_check.mjs` |
| Installer measurement boundary | `packaging/budlark.iss:106–122,178–219`, plus measurement-symbol search |

## Findings

### ANALYTICS-01 — High — Pending experiment enrollment survives consent withdrawal

**Evidence**

- `site/experiment-client.mjs:11–24`: `start()` awaits configuration, verification and assignment before installing `visit` and posting exposure.
- `site/experiment-client.mjs:35–36`: `stop()` returns immediately when `visit` is still null. It does not invalidate pending enrollment.
- `site/customer.mjs:116–120`: experiment requests use only a timeout, not the consent-change abort controller; the transport checks browser privacy signals but not the current consent checkbox.
- `site/customer.mjs:128–140`: withdrawal calls `stop()`, but the pending `start()` continuation remains valid.

**Reproduction**

Using the actual dependency-free client and a valid frozen definition:

1. Start enrollment with its configuration response deliberately pending.
2. Call `stop()`; it returns `false`.
3. Resolve the configuration.

Observed requests were configuration followed by **exposure**, with **no forget request**. Client state became active after withdrawal.

**Impact**

A consented visit can become a persisted experimental subject after the visitor has withdrawn consent. The ordinary account-event consent gates do not protect this separate website path.

The documented production-OFF boundary limits present exposure; this is a confirmed source defect, **not evidence that live visitors were affected**.

**Required correction:** invalidate pending starts on withdrawal, recheck the enrollment generation before applying variants and sending exposure, and ensure withdrawal handles any created subject.

**Confidence:** High — directly reproduced.

---

### ANALYTICS-02 — Medium — Analytics check-in ordering does not preserve the journal’s monotonic ordering

**Evidence**

- `lib/core/garden_store.dart:568–586`: successive check-in edits receive a monotonic saved timestamp, including when the clock is unchanged or regresses.
- `lib/core/garden_store.dart:624–626`: corresponding `checkin` and `first_checkin` events are emitted without passing that timestamp.
- `lib/core/garden_store.dart:1460–1465`: event timestamps instead come from a fresh `_clock()` call.
- `api/src/dashboards.mjs:29–30,33–40`: analytics orders equal timestamps by random event UUID and uses the last habit/local-day observation as effective truth.
- `api/src/goals.mjs:15–16,64–74`: target-aligned practice goals consume that effective event projection.

**Failure**

When event clock readings collide, a later undo can sort before an earlier positive observation. During clock regression, the later edit can likewise receive an earlier event timestamp despite the journal explicitly repairing its own timestamp.

The exact source reducer, exercised in memory with equal-timestamp observations and valid UUID ordering, retained the earlier positive result over the later undo.

**Impact**

Effective-practice numerators can disagree with the saved journal, affecting retention and D7/D30 goals.

`test/telemetry_test.dart:255–280` checks edit/undo event counts, but does not assert that event ordering matches the journal’s monotonic timestamps.

**Required correction:** carry the saved operation timestamp into telemetry and preserve alias ordering so `first_checkin` cannot resurrect an undone result.

**Confidence:** High for the source mismatch and reducer behavior; Flutter/SQLite reproduction was not executed.

---

### ANALYTICS-03 — Medium — Failed exposure leaves an active variant that cannot retry enrollment

**Evidence**

- `site/experiment-client.mjs:20–25`: applies the variant and saves `visit` before awaiting exposure persistence.
- `site/experiment-client.mjs:12`: later `start()` calls return immediately for that saved visit.
- `site/experiment-client.mjs:29–30`: outcomes are discarded while `exposed` remains false.
- `site/customer.mjs:134–135`: the rejection handler sets an error dataset value, without restoring control.
- `docs/experiments.md:36–37`: promises fallback to the standard page when caps/errors occur.

**Reproduction**

Selected a deterministic candidate assignment, then rejected exposure with a simulated service failure. Observed:

- Candidate copy remained visible.
- Client state remained active.
- Calling `start()` again made no second exposure attempt.
- A download outcome returned `false`.

**Impact**

The page can serve an experimental treatment outside the persisted exposure denominator, silently dropping subsequent outcomes. This contradicts the promised error fallback and compromises experiment readiness.

**Required correction:** restore control and clear failed enrollment, or implement an explicitly guarded retry lifecycle; test exposure rejection and recovery.

**Confidence:** High — directly reproduced with candidate copy.

---

### ANALYTICS-04 — Low — Measurement documentation still describes removed installer collection as current

**Evidence**

- `docs/measurement.md:28–36` describes an interactive installer opt-in, installation observations and owned launch collection.
- `docs/funnel-telemetry.md:14` calls that checkbox the actual installer source.
- `packaging/budlark.iss:186–195` initializes installation motion and records installation success, but contains no measurement choice or receipt creation.
- `packaging/budlark.iss:113–114` removes the old ownership marker.
- `test/measurement_packaging_test.mjs:15–19` explicitly asserts absence of `MeasurementCheckBox`, `SaveStringToFile` and `MeasurementEvent`.
- `docs/funnel-telemetry.md:148` separately states that installer receipts are withdrawn and install/first-launch time is unobservable.

**Impact**

The same measurement documentation presents incompatible coverage states. An analyst could incorrectly expect a fresh install/launch denominator.

**Required correction:** label the old installer contract historical and make the current unavailable coverage consistent throughout.

**Confidence:** High — source, tests and documentation directly disagree.

## Denominator and privacy assessment

The reviewed source correctly distinguishes:

- Anonymous website **event counts**, experimental **page visits**, app installation/account-scoped units, and distinct account metrics.
- Download intent from completed transfer, installation, delivery and attributable activation.
- Exact-day retention panels from the separately implemented frequency-based D7/D30 goals.
- Privacy suppression from statistical power.
- Unknown/unobservable values from zero or achieved targets.
- Persisted daily snapshots from on-demand rollups.

Account receipt import requires independent product-event consent and explicit confirmation. Local consent is not a synced preference. API scans have explicit ceilings and reject overflow rather than returning partial counts. Account and record deletion filtering exists; experience withdrawal has a replay marker. These are positive source controls, not proof of complete deployed operation.

## Validation performed

| Check | Result |
|---|---|
| Pending-start/withdrawal reproduction | Defect reproduced |
| Candidate-arm exposure-failure reproduction | Defect reproduced |
| Exact effective-check-in reducer with equal timestamps | Ordering failure reproduced; no Dart runtime claim |
| `node --test test/measurement_packaging_test.mjs test/public_claims_test.mjs` | **4 passed** |
| `node tool/generate_event_registry.mjs --check` | Passed |
| `node tool/generate_experience_policy.mjs --check` | Passed |
| `node --test api/test/goals.test.mjs` | Blocked: missing `zod`; not a demonstrated goal-test assertion failure |
| Flutter/native/browser acceptance | Not executed; Flutter and installed project dependencies unavailable |

No dependencies were installed and no files were edited. Final Git status was clean and HEAD remained the requested baseline.

## Unsupported capabilities and live-evidence gaps

These are **separate from confirmed bugs**:

- No independently verified live consent, customer sync, revocation/deletion, cohort coverage or aggregate freshness evidence was obtained.
- Installer/first-launch acquisition coverage is unavailable for fresh installations in this source.
- Complete native fatal/session coverage is absent; a 99.5% crash-free claim is unsupported.
- Verified invitation delivery, revenue and complete referral attribution are unsupported.
- Original notification-disable and support-response goals retain explicitly unavailable or partial evidence.
- Hosted GrowthBook ingestion, analysis and winner decisions remain unconnected; local SDK evaluation is not that evidence.
- Synthetic acceptance receipts do not establish customer efficacy, representative denominators, scheduler reliability or current production settings.

## Final disposition

**CHANGES_REQUIRED for analytics public-launch readiness.** Correct the enrollment consent race, exposure-failure lifecycle, event-ordering mismatch and contradictory coverage documentation; then rerun affected source-bound tests. Live evidence gaps remain independently unresolved. No owner risk acceptance or release authorization is implied.
