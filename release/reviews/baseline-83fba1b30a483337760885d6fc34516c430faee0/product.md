# Product review — baseline 83fba1b30a483337760885d6fc34516c430faee0

**Role:** Product — outcome, scope, go/no-go recommendation  
**Stage:** Owner-test only  
**Reviewed commit:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Source tree:** `5b2eb392aff651f15dfd3f34b987e1b1282dc098`  
**Verdict:** **CHANGES_REQUIRED — no-go for an owner-test handoff bound to this HEAD.** Reassess after the product defect below is fixed and exact-HEAD candidate bits and evidence are available. This is not a public-launch review or approval.

## Scope and method

Reviewed the product’s intended outcome and release boundary, the owner-test evidence recorded in the repository, and relevant source for planting, check-ins, and reminder behavior. This is a read-only source and documentation review. I did not build or run the app, execute tests, download or install an artifact, or interact with an account, provider, or device. No shared drafts or other role reviews were read. This review does not establish full runtime coverage.

## Files inspected

- `docs/release-governance.md`; `release/roles.json`; `release/evidence/README.md`; `release/reviews/README.md`; `release/signoffs/README.md`
- `README.md`; `CHANGELOG.md`
- `docs/product-spec.md`; `docs/status.md`; `docs/mvp-exit-matrix.md`; `docs/visual-quality-review.md`; `docs/visual-quality-scorecard.json`; `docs/website-launch.md`; `docs/installer-onboarding.md`
- `.github/workflows/ci.yml` (including its release-job changes)
- `lib/features/garden/recipe_builder.dart`; `lib/features/garden/garden_screen.dart`; `lib/core/garden_store.dart`; `lib/core/rules.dart`; `lib/services/desktop_reminders.dart`
- `test/garden_learning_test.dart`; `test/first_habit_invitation_test.dart`; `test/release_signoffs_test.mjs`

## Findings

### PROD-1 — HIGH — No exact-HEAD owner-test artifact is evidenced here  
**Resolution: OPEN**

`docs/status.md:9–18` identifies the recorded installer (SHA-256 `8bac5279fc24db9a0e00ef423d650b02b4298f02ade0200b60110e5506abe6f6`) and run `39100447327` as built from candidate `083f2def66c1e084c56653238b85802ff260c3c3`, tree `9964db478645d3c04e41f481aaf6d9818e0eec7d`. This review is for HEAD `83fba1b30a483337760885d6fc34516c430faee0`, tree `5b2eb392aff651f15dfd3f34b987e1b1282dc098`. The post-candidate changes include release workflow/governance changes; even though they do not change Flutter or installer source, the new governance explicitly binds review and sign-off to the exact candidate commit, tree, and artifact (`docs/release-governance.md`, “What is bound” and “Workflow per candidate”). The earlier artifact therefore does not evidence an artifact bound to this HEAD.

**Impact:** Product cannot give the required exact-candidate owner-test recommendation for these bits. This is an evidence/release-boundary blocker, not a demonstrated user-facing defect. Obtain exact-HEAD hosted candidate evidence before binding the owner-test sign-off.

### PROD-2 — MEDIUM — A failed check-in can still suppress its reminder  
**Resolution: OPEN**

In `lib/features/garden/garden_screen.dart:359–374`, `_act` catches action errors and displays “Couldn't complete that action. Try again.” In `_check` (`:491–496`), `saved` becomes true only after `store.checkIn` succeeds, but `reminders?.practiced(habit.id)` runs unconditionally afterward. `lib/services/desktop_reminders.dart:668–672` shows that `practiced` resets the ignored-reminder counter and cancels that habit’s scheduled notification.

**Impact:** If persistence fails, the user sees an error but the reminder can still be treated as practiced and withdrawn. This contradicts the product’s practice/reminder contract. Call the reminder update only after a successful save; add a regression test for the failed-save path. This is a source-level finding; I did not execute or reproduce it at runtime.

### PROD-3 — MEDIUM — The documented quality bar remains unmet for broad release  
**Resolution: OPEN**

`docs/product-spec.md:152–165` requires every applicable visual/accessibility dimension to score at least 4/5; below-bar scores block release, and `NOT OBSERVED` is not a pass. The scorecard records open gates and accessibility scores of 3 for core surfaces, including device-empty (`docs/visual-quality-scorecard.json:28`), the first-habit builder (`:114`), and check-in (`:135`). Native Narrator, high contrast, mixed-monitor DPI, and other conditions remain unobserved.

**Impact:** This bars a general customer release under the product’s stated acceptance criteria. It does not by itself bar a narrowly scoped owner-only evaluation, provided the limitations are disclosed and no accessibility pass is claimed. These are documented acceptance gaps, not proof of a specific runtime accessibility failure.

## Owner/manual gates and scope boundary

`docs/status.md:28–51` says exact-installer installation/launch feedback is **PENDING**, the installer is unsigned, and the public download pointer and customer launch remain held. It records a clean static scan for the documented candidate but explicitly does not establish runtime safety. The earlier reported Defender behavior detection concerns a different candidate; its cause and remediation are not established by this review. Manual verification is an owner gate, not a product defect, and protection warnings must not be bypassed.

The repository accurately describes Budlark as an engineering preview, not a complete MVP. The exit matrix marks reminders and experiment readiness blocked, several customer loops partial, outcome targets unmeasured, and overall full-MVP exit **NOT GREEN** (`docs/mvp-exit-matrix.md:57, 67, 72, 126`). Those gaps do not preclude a bounded owner-only evaluation, but do preclude representing that evaluation as public-launch or full-MVP acceptance. No risk is accepted by this review.

## Recommendation

**No-go for owner-test sign-off on this exact HEAD/artifact pairing** until PROD-1 is addressed and PROD-2 is fixed. Then consider only a designated owner test of the exact, hash-verified candidate, with installation/launch feedback recorded against those bits. **No-go for public/customer release** while the stated acceptance gates remain open. No merge, release, deployment, or other changes were made.
