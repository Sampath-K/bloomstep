# Legal-compliance review — baseline `83fba1b30a483337760885d6fc34516c430faee0`

**Source tree:** `5b2eb392aff651f15dfd3f34b987e1b1282dc098`  
**Worktree:** clean. **Changes:** none.

## Scope and method

Reviewed the release-role policy and review/sign-off process; the public site and release page; privacy, measurement, product, and website-launch documentation; relevant website collection/API code and app identity, analytics, and diagnostics code; and Flutter, API, and site dependency manifests and locks. Checked the tracked-file inventory for terms, license, and notice documents. This was a targeted, read-only technical compliance review—not a line-by-line audit of all repository files.

**Inspected files:** `release/roles.json`, `release/reviews/README.md`, `release/signoffs/README.md`, `docs/release-governance.md`, `docs/product-spec.md`, `docs/website-launch.md`, `docs/measurement.md`, `docs/backend-contracts.md`, `docs/microsoft-profile-photos.md`, `README.md`, `site/index.html`, `site/releases/index.html`, `site/customer.mjs`, `site/measurement.mjs`, `site/build.mjs`, `api/src/website-funnel.mjs`, `lib/services/identity.dart`, `lib/services/analytics_sandbox.dart`, `lib/services/session_diagnostics.dart`, `lib/services/experience_experiments.dart`, `pubspec.yaml`, `pubspec.lock`, `api/package.json`, `api/package-lock.json`, `site/package.json`, and `site/package-lock.json`.

## Findings

### LC-1 — Medium — Preview terms and product-use license are not documented

The public site describes a free, downloadable owner-test preview, but the reviewed pages provide no terms of use, end-user license, or stated license grant for the app. No project `LICENSE`, `NOTICE`, EULA, or terms file is tracked. The release-role policy assigns terms review to legal-compliance (`release/roles.json`, `legal-compliance` role); `site/index.html:202` describes the preview as free, while `site/index.html:191` limits it to designated testers.

**Assessment:** This is a confirmed documentation gap, not a conclusion that any particular law requires specific terms. The owner/legal reviewer must decide what terms or usage grant, if any, should govern the preview before public launch.

### LC-2 — Medium — Public privacy notice is explicitly a draft with unresolved decisions

The page labels its notice **“Draft privacy notice”** (`site/index.html:281`) and says it does not claim compliance with a particular privacy law or certification (`:284`). It also identifies unconfirmed provider-log, sign-in, support-email, backup-retention, and restore behavior (`:293`, `:296`). The product specification makes privacy/legal review a human launch gate (`docs/product-spec.md:445`).

**Assessment:** The site is candid about these limits; I found no confirmed misrepresentation in the reviewed consent and measurement flows. But the draft label and unresolved facts mean this review cannot support a public-launch privacy approval. Applicable obligations and final disclosures remain owner/legal decisions; this review does not infer jurisdiction or legal basis.

### LC-3 — Medium — Dependency and distribution license compliance is not evidenced

The app declares numerous runtime dependencies, including Flutter packages for identity, storage, analytics, and diagnostics (`pubspec.yaml:9–33`); the API and site also declare dependencies (`api/package.json:8–11`, `site/package.json:7`). The npm lockfiles contain SPDX license metadata, but the repository has no consolidated third-party inventory/notices artifact, and no tracked product license or end-user grant was found.

**Assessment:** No license violation is established from this evidence. Before distributing the app publicly, identify what is actually included in each installer, verify applicable dependency obligations and notices, and document the intended license for Budlark itself.

## Store-policy status

No current Store submission was found: the release page says there is no Microsoft Store version yet (`site/releases/index.html:134`, `:158`), and the product specification places Store packaging later (`docs/product-spec.md:387`). Therefore Store-policy compliance is **not assessable/applicable to this direct-download candidate**; it remains a future review gate, not a current pass.

## Technical observations and verdict

In the inspected code, website measurement is opt-in and respects DNT/GPC (`site/customer.mjs:85–131`); the third-party analytics sandbox is non-release-only and consent-gated (`lib/services/analytics_sandbox.dart:11–12`, `:181`); and GrowthBook evaluation is documented as local-only (`lib/core/growthbook_experience_provider.dart:5`). These observations are consistent with the reviewed disclosures, but do not verify every operational statement, vendor practice, or business-policy assertion.

**Verdict: `CHANGES_REQUIRED` for public-launch readiness.** The findings are documentation and verification gaps—not determinations of legal non-compliance. No jurisdiction-specific legal conclusion or legal approval is offered. The governance policy binds sign-off to candidate source and installer hashes; this baseline review was not bound to an installer SHA-256 and is not a release sign-off.
