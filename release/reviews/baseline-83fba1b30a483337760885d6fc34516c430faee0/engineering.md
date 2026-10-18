# Engineering baseline review

**Baseline:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Verdict:** **CHANGES_REQUIRED** — one low-severity validation defect; no risk acceptance.

## Scope and method

I read the engineering role definition and release governance, checked the clean checkout and commit, reviewed the CI test/build and release-promotion steps, and examined the new sign-off verifier and its tests. I also inventoried tracked files and ran `node --check` on all tracked `.mjs` and `.js` files; those syntax checks passed.

**Runtime verification remains unobserved:** Flutter/Dart are unavailable and API/site dependencies are not installed. I did not install dependencies or run tests/builds. CI defines API checks/tests (`.github/workflows/ci.yml:76–77`), site tests/build, Flutter analysis/tests (`:249–253`), and Windows release builds (`:343`), but I did not verify their result at this commit.

## Files inspected

- `.github/workflows/ci.yml`
- `README.md`, `pubspec.yaml`, `analysis_options.yaml`
- `api/package.json`, `api/tsconfig.json`
- `site/package.json`, `site/build.mjs`
- `docs/release-governance.md`, `docs/status.md`, `docs/mvp-exit-matrix.md`
- `release/roles.json`, `release/reviews/README.md`, `release/signoffs/README.md`, `release/evidence/README.md`
- `tool/verify_release_signoffs.mjs`, `test/release_signoffs_test.mjs`

## Findings

### ENG-1 — LOW: Sign-off timestamps accept impossible dates

`tool/verify_release_signoffs.mjs:16` uses a shape-only regex for UTC timestamps. That check is applied to accepted-risk owner timestamps at line 55 and review timestamps at line 95. For example, `2026-13-99T25:99:99Z` matches the regex even though it is not a valid date/time. The test at `test/release_signoffs_test.mjs:165–168` rejects a non-date string but does not cover invalid numeric components.

**Root cause:** the validator checks timestamp formatting, not calendar/time validity.  
**Needed:** strict date/time validation plus regression cases for invalid month, day, and hour values.

## Governance boundary

`release/roles.json:34–37` assigns this role code quality, tests, and build health. The owner’s manual installer verification remains pending in `docs/status.md:28–31`; this review does not resolve it. I made no source or release edits and created no review/sign-off drafts. No risk was accepted, and no merge, release, or deployment is authorized.
