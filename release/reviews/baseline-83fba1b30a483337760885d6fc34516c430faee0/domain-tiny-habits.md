# Baseline review — domain-tiny-habits

## Review identity

| Field | Value |
|---|---|
| Role | `domain-tiny-habits` |
| Candidate | `83fba1b30a483337760885d6fc34516c430faee0` |
| Source tree | `5b2eb392aff651f15dfd3f34b987e1b1282dc098` |
| Required stage | `owner-test` |
| Verdict | **CHANGES_REQUIRED** |
| Evidence type | Independent, read-only source review |
| Installer/artifact binding | Not established by this review |

This is proposed baseline review markdown, not an artifact-bound release sign-off. No finding is accepted as risk.

## Scope and method

Reviewed method fidelity across recipe creation/editing, anchor/action/celebration guidance, check-in entry points, positive-only progression, reflection/graduation, reminder messaging, experiment wording and customer-facing learning-science claims.

Method:

1. Confirmed HEAD and clean worktree; read release governance and role responsibilities.
2. Inventoried the repository and searched role-relevant application, tests, documentation, API, shared policy, packaging and site sources.
3. Followed relevant implementation paths and compared them with the product contract and inspected regression tests.
4. Distinguished deterministic app criteria from evidence of actual behavior, automaticity or effectiveness.

No other role reviews or shared drafts were consulted. Historical copy-review drafts were not used. No files were edited; no tests, application, installer, deployment or release operations were executed. Worktree remained clean.

This is a bounded repository-wide role review, not a claim that every repository line was inspected.

## Actual files inspected

Ranges identify focused inspection where a file was not read completely.

### Governance and product documentation

- `docs/release-governance.md`
- `release/roles.json`
- `docs/product-spec.md` — entire file
- `docs/copy-guide.md`
- `docs/app-experiments.md:1–100`
- `docs/installer-onboarding.md:1–150`
- `README.md:1–85`

Targeted claim-search excerpts were also inspected in `CHANGELOG.md`, `docs/measurement.md`, `docs/acceptance.md`, `docs/experiments.md`, and `docs/website-launch.md`. These were not treated as complete-document reviews.

### Application and shared policy

- `lib/core/models.dart`
- `lib/core/rules.dart`
- `lib/core/garden_store.dart:413–645,690–930,1988–2035`
- `lib/features/garden/recipe_builder.dart` — entire file
- `lib/features/garden/garden_screen.dart:110–350,450–710,1870–2110`, plus targeted claim/search excerpts
- `lib/features/garden/experience_copy.dart`
- `lib/services/desktop_reminders.dart:292–450,480–588,748–803`
- `lib/services/remote_config.dart:1–190`
- `shared/experience-experiments.json`
- Targeted excerpts in `shared/event-registry.json` and `lib/features/garden/invitation_dialog.dart`

### API and website

- `api/src/contracts.mjs:1–53`
- `api/src/dashboards.mjs` — entire file
- `api/src/snapshot-contracts.mjs` — entire file
- Targeted excerpts in `api/src/goals.mjs`, `api/src/engagement.mjs`, and `api/src/aarrr.mjs`
- `site/index.html:1–226,260–309`
- `site/releases/index.html:122–151`
- Targeted excerpts in `site/customer.mjs` and `packaging/budlark.iss`

### Tests and supporting source

- `test/rules_test.dart`
- `test/garden_store_test.dart`
- `test/learning_test.dart`
- `test/garden_learning_test.dart`
- `test/recipe_builder_test.dart`
- `test/reminder_scheduler_test.dart:1–260,426–465`, plus targeted search excerpts
- `test/public_claims_test.mjs`
- `site/test/onboarding.test.mjs:1–175`
- `integration_test/budlark_windows_e2e_test.dart:120–295`
- Targeted excerpts in `site/test/launch.test.mjs` and `tool/installer_art_export_test.dart`

Test source inspection establishes intended assertions, **not passing execution results**.

## Findings

### TH-01 — Medium — Graduation copy overstates what the app’s evidence establishes

**Status: OPEN**

**Evidence**

- `lib/features/garden/garden_screen.dart:659` announces:  
  > “This one is part of you now. Welcome to your evergreen Grove!”
- `site/releases/index.html:141` states:  
  > “…automatic habits graduate to your Grove.”
- The actual rule is two recent scores ≥5.5 and ≥17 recorded practice days: `lib/core/rules.dart:64–67`, applied in `lib/core/garden_store.dart:785–820`.
- The reflection UI itself describes its questions as original and not a validated clinical instrument: `lib/features/garden/garden_screen.dart:611–613`.
- `docs/product-spec.md`, “Outcome and trust,” explicitly says the graduation metric is not proof that a habit became automatic.

**Defect and consequence**

The app deterministically awards a status using self-reported scores and recorded check-ins. The graduation message and release-page copy convert that status into an unqualified assertion about the person’s learned behavior. The existing nonclinical disclaimer does not establish automaticity or qualify these specific assertions.

**Required correction**

Describe graduation as an app milestone based on recorded practice and reported naturalness, not confirmed automaticity or permanent incorporation into the person. Align both application and release-page wording through the required editorial process.

**Verification needed**

Add focused claim tests covering graduation copy on both surfaces. Existing `test/public_claims_test.mjs` checks privacy/preview claims, not this automaticity overstatement.

---

### TH-02 — Medium — Notification and tray check-ins bypass personal celebration feedback

**Status: OPEN**

**Evidence**

- Main-screen positive check-ins explicitly show the saved personal celebration: `lib/features/garden/garden_screen.dart:481–489`.
- Notification `did` handling directly saves the check-in, calls `practiced`, and refreshes: `lib/services/desktop_reminders.dart:420–430`. It supplies no personal celebration feedback.
- Tray `did:<habitId>` handling likewise saves, refreshes and focuses the window without dispatching celebration feedback: `lib/services/desktop_reminders.dart:777–784`.
- The service’s `changed` callback is wired to `_load`, which refreshes state rather than invoking `_check`: `lib/features/garden/garden_screen.dart:151–154,314–340`.
- `docs/product-spec.md`, required “Check-in” loop, requires personal celebration within 300ms.

**Defect and consequence**

Two supported positive check-in routes omit the app’s explicit personal-celebration step. Merely refreshing or opening the garden is not equivalent to the immediate feedback implemented on the main route. This creates inconsistent fidelity to the anchor → tiny behavior → celebration loop.

This finding does **not** establish that the person failed to celebrate independently.

**Required correction**

Provide a shared, nonblocking, accessible celebration-feedback path for positive check-ins from each supported entry point. Preserve quiet operation, reduced-motion behavior, user control, account isolation and duplicate-action handling; do not solve this by adding unsolicited notification volume.

**Verification needed**

Extend notification/tray tests to assert the chosen celebration is dispatched once for a genuine positive check-in and not for rest, duplicate or rejected actions. Native visibility and the 300ms target require separate measured evidence.

---

### TH-03 — Medium — Material recipe edits reuse the previous behavior’s graduation evidence

**Status: OPEN**

**Evidence**

- `lib/core/garden_store.dart:477–501` allows anchor and behavior replacement under the same habit ID, updating only recipe fields and timestamp.
- Graduation selects reflections solely by account and habit ID: `lib/core/garden_store.dart:785–790`.
- Its practice count similarly consumes that habit ID’s effective historical check-ins: `lib/core/garden_store.dart:792–809`.
- Reflection and check-in contracts contain no recipe revision binding: `api/src/contracts.mjs:17–29`.

**Source-derived reproduction**

1. Record 17 practice days and one qualifying reflection for recipe A.
2. After the reflection interval, replace its anchor and behavior with substantially different recipe B.
3. Save one qualifying reflection for B.

The graduation calculation combines A’s practice and earlier score with B’s new score. B can therefore graduate without recorded practice of B or two naturalness assessments of B.

**Defect and consequence**

Historical reports about one behavior/context can qualify a different behavior/context. That undermines the interpretation of the app’s own naturalness and graduation criteria, independently of whether those criteria are scientifically validated.

**Required correction**

Define and implement evidence continuity for material anchor/behavior changes. For example, bind eligibility evidence to a recipe revision, preserving historical records and already-earned decorative growth. Distinguish substantive replacement from a small refinement; do not introduce punitive plant regression or silently delete history.

**Verification needed**

Add store tests for unrelated behavior replacement, anchor replacement, minor refinement and sync/reopen behavior. Inspected edit tests verify saving and timestamp ordering, not evidence attribution across recipe changes.

## Positive observations

- Starter recipes contain recognizable routine anchors, small actions and personal celebration examples.
- Creation supports custom choices, cancellation and optional celebration rehearsal; inspected tests explicitly exercise planting without rehearsal.
- Main-screen “Not today” offers “No reason needed.” Growth calculations preserve existing stages after rest or undo.
- Weekly Recipe Doctor recommendations offer smaller steps, more reliable anchors and personally suitable celebration without compulsory changes.
- The reflection UI discloses original/nonvalidated wording and numerical graduation criteria.
- The main website attributes method inspiration, disclaims affiliation and avoids medical-treatment promises in inspected sections.
- Experiment documentation distinguishes proposed metrics and hypotheses from demonstrated outcomes. Reminder configuration is source-gated against unreviewed activation.

These are source observations, not proof of effectiveness or native runtime acceptance.

## Limitations and owner gates

The following remain distinct from actionable source defects:

- **Effectiveness:** No prospective or longitudinal customer evidence was established here. Check-ins, garden growth, graduation and optional telemetry are not independently observed behavior change.
- **Scientific validation:** This review does not validate the four-item instrument, graduation thresholds or causal effectiveness of the product. Numerical rules must remain operational definitions.
- **Content rights:** Attribution/disclaimers are present, but instrument licensing, originality and trademark clearance are not established by this review.
- **Native acceptance:** Installer behavior, Windows notification delivery, accessibility, reduced motion and celebration latency were not observed.
- **Planned education:** The library, curated research and adaptive education in the product contract are explicitly planned; their absence is not classified here as a shipped-feature defect.
- **Release identity:** Installer SHA-256 and producing CI run/artifact identity were not inspected. Historical or different-preview evidence cannot approve this candidate.
- **Owner authority:** Scope choices, editorial approval, research authorization, risk acceptance and launch remain owner decisions. No risk acceptance is supplied or inferred.

## Verdict

**CHANGES_REQUIRED**

Three medium-severity findings remain open: unsupported graduation claims, celebration-feedback omissions on secondary check-in routes, and graduation evidence crossing material recipe changes.

Resolve these findings and re-review affected sources at the new candidate SHA. This baseline grants no owner-test sign-off, merge, release, deployment or public-launch approval.
