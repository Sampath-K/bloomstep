# UX, Content & Accessibility Baseline Review

**Candidate:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Source tree:** `5b2eb392aff651f15dfd3f34b987e1b1282dc098`  
**Role:** `ux-content-accessibility`  
**Working tree at review:** clean; review was read-only. No other role review or sign-off drafts were inspected.

## Scope and method

Read the release governance and role definitions, then traced the first-habit, practice, reflection, invitation, profile/settings, and website preview/download paths. Reviewed relevant source for copy, semantics, focus behavior, responsive layouts, and color tokens; checked the associated widget and website test contracts.

**Inspected:** `docs/release-governance.md`, `release/roles.json`, `docs/copy-guide.md`, `docs/visual-quality-review.md`, `docs/visual-quality-scorecard.json`, `docs/release/preview15-handoff.md` (opening section); `lib/app/{theme,budlark_app,session_boundary}.dart`; `lib/features/garden/{experience_copy,garden_screen,garden_canopy,invitation_dialog,measurement_controls,profile_section,recipe_builder,reminder_observation_controls}.dart`; `site/index.html`, `site/releases/index.html`, `site/invitation-landing.mjs`; and relevant tests including `session_boundary_test.dart`, `measurement_controls_test.dart`, `garden_chrome_visual_test.dart`, `invitation_visual_test.dart`, `recipe_builder_visual_test.dart`, `surface_review_visual_test.dart`, `visual_quality_contract_test.dart`, and copy/profile tests.

**Validation:** `node --test site/test/*.test.mjs` passed **66/66**. The targeted Flutter tests could not run because `flutter` was unavailable in the review environment. No native Windows/Narrator run or installer trial was performed.

## Findings

### UXA-1 — Raw exception details are rendered as user-facing error copy
**Severity:** Medium · **Confidence:** High  
`lib/features/garden/measurement_controls.dart:40–41` appends `$error` to “Receipt action failed.” `lib/app/session_boundary.dart:66–69, 89–92` likewise interpolates exception text into session errors; `test/session_boundary_test.dart:27–40` deliberately injects a storage exception in this flow. This conflicts with the copy guide’s instruction not to show raw exceptions or implementation details (`docs/copy-guide.md:28–30`). Show an actionable, user-safe message and keep diagnostics separate.

### UXA-2 — Consent explanation is technically dense
**Severity:** Medium · **Confidence:** High for the copy; heuristic assessment  
The product-event consent subtitle uses terms such as “fixed-category error,” “account-session attempts,” and “queued events” (`lib/features/garden/garden_screen.dart:1079–1083`), followed by more implementation-specific detail (`1114–1115`). The copy guide calls for familiar language and avoids internal jargon (`docs/copy-guide.md:11–14, 31–34`). The scorecard records this surface below its target and leaves it open (`docs/visual-quality-scorecard.json:152–156`).

### UXA-3 — “Invitation receipts” is internal terminology in the garden UI
**Severity:** Low · **Confidence:** High  
The user-facing action says “Refresh invitation receipts,” and the expandable section is titled “Private invitation receipts” (`lib/features/garden/garden_screen.dart:1726–1752`). The copy guide specifically lists “receipt” among terms not to expose in ordinary UI (`docs/copy-guide.md:31–34`). A user-oriented label such as invitation status would be clearer.

## Accessibility and acceptance gates

Some code-level keyboard and semantics contracts are present: tests cover garden focus order and the primary action, invitation Escape/Enter behavior, labeled controls, and invitation contrast checks. The website defines visible focus styling and its declared light/dark palette token pairs calculate above 4.5:1. These checks do **not** establish full app contrast or native accessibility acceptance.

Native Narrator, high contrast, mixed-monitor DPI, and installed-app behavior remain **unverified**, not defects inferred from source. The repository’s scorecard also records open below-target heuristic results on several flows; its policy says every applicable dimension must meet 4 and `NOT_OBSERVED` is not a pass (`docs/visual-quality-review.md:22–33`). Owner verification of the exact installer remains **PENDING**; this review does not substitute for it.

## Verdict

**CHANGES_REQUIRED — not a release sign-off.** The exception-copy issue and terminology need correction. Native accessibility and owner installer verification remain separate open gates; no risk is accepted here.
