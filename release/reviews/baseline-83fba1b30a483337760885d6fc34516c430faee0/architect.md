# Baseline architect review

**Candidate:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Verdict:** **CHANGES_REQUIRED**  
**Confidence:** High in both findings.

## Scope and method
Read-only, architecture-focused review of the baseline: release governance and role definitions; sign-off validation and CI artifact promotion; and selected app, API, persistence, and website composition/data-flow paths. Confirmed the checkout was at the requested commit and the worktree was clean. No files were changed; no tests, builds, installer execution, access changes, merges, releases, or deployments were performed.

The tracked-file inventory contained 682 files. This was a bounded architect review, not a line-by-line review of generated files, assets, and every platform-specific file.

## Inspected files
- `docs/release-governance.md`, `release/roles.json`
- `tool/verify_release_signoffs.mjs`, `test/release_signoffs_test.mjs`
- `.github/workflows/ci.yml` (release job, lines 500–586)
- `tool/release_bundle.mjs`, `tool/release_payload.mjs`
- `README.md`, `pubspec.yaml`, `api/package.json`, `site/package.json`
- `lib/core/garden_store.dart` (lines 1–250), `lib/core/models.dart`
- `lib/services/sync_service.dart` (lines 1–260, 310–352), `lib/services/identity.dart` (lines 1–240)
- `lib/app/bloomstep_app.dart` (lines 1–220)
- `api/src/backend.mjs` (lines 1–570), `api/src/contracts.mjs`, `api/src/storage-target.mjs`
- `api/src/primary-auth.mjs`, `api/src/auth-transport.mjs`, `api/src/invitations.mjs` (lines 1–290)
- `site/build.mjs`

## Findings

### ARCH-1 — Role evidence references need not exist
**Severity:** Medium · **Confidence:** High

The governance requires each role to write a review record and describes sign-offs as evidence-backed (`docs/release-governance.md:3–4, 22–24`). But the gate checks only that `evidence` is a nonempty array of nonempty strings (`tool/verify_release_signoffs.mjs:92–93`); it verifies the generated evidence README, not the referenced role-review files (`:123–127`). The test fixture supplies `release/reviews/baseline-<candidate>/<role>.md` references without creating those files, yet its complete approved set passes (`test/release_signoffs_test.mjs:25–40, 43–56`).

**Impact:** The release gate can accept required sign-offs whose claimed review evidence is absent, weakening the stated evidence-backed approval control.

### ARCH-2 — Recorded artifact ID is not checked against the promoted artifact
**Severity:** Medium · **Confidence:** High

The verifier checks that artifact run/artifact IDs are numeric and consistent across sign-offs (`tool/verify_release_signoffs.mjs:91, 107–108`), but does not resolve them to actual GitHub artifacts. The release workflow extracts only `runId` from a sign-off (`.github/workflows/ci.yml:561–564`) and downloads artifacts by run and name, without checking the recorded `artifactId` (`:568–570`). The installer hash check binds the downloaded bytes, but does not substantiate that the recorded artifact ID or run produced them, as required by governance (`docs/release-governance.md:8–11, 32–33`).

**Impact:** Release evidence can assert an unverified run/artifact provenance even when the promoted installer bytes match the approved hash.

## Review disposition
No owner-accepted risks recorded. The inspected app/API paths showed explicit account-bound storage and sync checks; no additional architect findings were substantiated within this bounded review.
