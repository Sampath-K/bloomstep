# QA/release baseline review

**Baseline:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Verdict:** **NOT READY for release or customer launch.** The previous artifact is useful evidence for its own source only; it does not establish acceptance or readiness for this baseline.

## Scope and method

Read-only review of release governance and role definitions, the CI/release workflow, release evidence and payload validators, installer packaging behavior, relevant installer/release contract tests, current status/handoff, and the public download pointer. No installer was executed, no tests were run, and no role-specific review/sign-off drafts or shared reviews were opened. The previous artifact’s hash and static-scan result below are reported from the repository status ledger, not independently re-downloaded or re-scanned here.

Inspected: `.github/workflows/ci.yml`; `docs/release-governance.md`; `release/roles.json` and the evidence/reviews/signoffs README files; `docs/status.md`; `docs/release/preview15-handoff.md`; `tool/release_bundle.mjs`; `tool/release_payload.mjs`; `tool/verify_release_signoffs.mjs`; `packaging/budlark.iss`; `packaging/install-progress.iss`; `test/release_bundle_test.mjs`; `test/release_signoffs_test.mjs`; `test/universal_installer_test.mjs`; `test/installer_standard_flow_test.mjs`; `site/customer-config.json`; and `site/releases/index.html`.

## Findings

### QA-REL-01 — Previous artifact does not identify this baseline — **HIGH**

The status ledger identifies the prior candidate as source `083f2def66c1e084c56653238b85802ff260c3c3`, run `39100447327`, artifact `12127077182`, SHA-256 `8bac5279fc24db9a0e00ef423d650b02b4298f02ade0200b60110e5506abe6f6` (`docs/status.md:9–20`). The reviewed baseline is `83fba1b30a483337760885d6fc34516c430faee0`. Governance requires sign-offs to bind the candidate commit, source tree, installer hash, and producing run/artifact (`docs/release-governance.md:8–11`), and requires a new candidate and renewed sign-offs after a fix (`:22–26`).

**Impact:** The prior artifact and its successful hosted checks cannot attest to this baseline. A fresh source-bound candidate and corresponding evidence are required.

### QA-REL-02 — Owner installer acceptance is still pending — **HIGH / release blocker**

The ledger records a static Defender scan with no threats reported, but also states the installer is unsigned and owner installation/launch feedback is **PENDING** (`docs/status.md:22–30`). It says hosted build/package checks are not installation or launch acceptance and that the public pointer/customer launch remain held (`:48–53`). CI performs a static scan without executing the installer (`.github/workflows/ci.yml:523–530`); the installer contract tests inspect source/configuration rather than performing native acceptance (`test/universal_installer_test.mjs:11–38, 80–94`).

**Impact:** The documented static result is not runtime safety or installer acceptance. Do not treat the prior hash, static scan, or hosted checks as owner approval.

### QA-REL-03 — Tag workflow can publish a public prerelease while trial status is pending — **MEDIUM**

The tag release job gates publication on successful hosted jobs and public-launch sign-offs, then records the owner trial as pending and runs `gh release create` (`.github/workflows/ci.yml:571–586`). The evidence generator sets `publicationAuthorized: !auditOnly` while also recording installer acceptance as `UNVERIFIED` and owner status as `PENDING` (`tool/release_bundle.mjs:47–56`). The workflow itself notes that the prerelease is publicly accessible (`ci.yml:582`).

**Impact:** Pending status is disclosed, but is not a machine-enforced block on public prerelease publication. This conflicts with the current instruction not to release before owner feedback. Do not tag or run this publication path absent separate authorization and the required new candidate.

### QA-REL-04 — Artifact ID is recorded but not independently resolved — **LOW**

Governance says sign-offs bind the producing run and artifact IDs (`docs/release-governance.md:8–11`). The release job downloads artifacts by run ID and artifact name (`.github/workflows/ci.yml:569–570`); the validator checks that sign-offs agree on an artifact ID (`tool/verify_release_signoffs.mjs:91, 107–108`) but does not compare that ID to the downloaded artifact’s actual GitHub artifact ID.

**Impact:** The installer SHA check binds the released bytes, so this is a provenance-record gap rather than evidence of byte substitution. Consider verifying the fetched artifact ID or making the run ID plus checked hash the explicitly authoritative identity.

## Positive controls observed

- Universal packaging is source/version/name/hash-bound and checksums both architecture payload-manifest hashes (`tool/release_bundle.mjs:20–40`); payload validation checks architecture, inventory, and file hashes (`tool/release_payload.mjs:34–67`).
- Installer configuration specifies per-user installation, native x64/ARM64 payload selection, and a post-install launch option (`packaging/budlark.iss:62–89, 97–111, 132–141`).
- The public site remains on preview.14 with its own published hashes (`site/customer-config.json:5–18`); this review did not change or promote that pointer.

**Disposition:** No approval or accepted risk is recorded by this review. The previous artifact’s static “no threats reported” result and owner feedback status remain as documented; neither establishes acceptance for the reviewed baseline.
