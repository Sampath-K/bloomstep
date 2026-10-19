# Growth-website review

**Baseline:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Role:** `growth-website` — positioning, website, download path, acquisition claims (`release/roles.json:58–61`)  
**Mode:** Read-only. No files changed; no risk accepted; no merge, release, or deployment action taken.

## Scope and method

Reviewed the role registry; homepage and releases-page copy; download configuration/rendering; acquisition reporting labels; related launch/funnel and product documentation; and the published `v0.1.0-preview.14` product source where necessary to compare site claims with the app. Checked the referenced GitHub release and ran focused website tests. The configured production website did not resolve from this environment, so its served content was not verified.

**Inspected files:** `release/roles.json`; `site/index.html`; `site/releases/index.html`; `site/customer-config.json`; `site/build.mjs`; `site/release-downloads.mjs`; `site/acquisition-panels.mjs`; `site/website-panels.mjs`; `site/test/launch.test.mjs`; `site/test/release-downloads.test.mjs`; `site/test/customer-warning.test.mjs`; `site/assets/customer-warning-provenance.json`; `site/assets/download-capture-provenance.json`; `README.md`; `docs/branding.md`; `docs/copy-guide.md`; `docs/product-spec.md`; `docs/release-governance.md`; `docs/status.md`; `docs/website-funnel.md`; `docs/website-launch.md`; `docs/release/preview15-handoff.md`; and, at tag `v0.1.0-preview.14`, `lib/features/garden/profile_section.dart`, `README.md`, and `site/index.html`.

## Findings

### GROWTH-1 — Medium — Site incorrectly says sign-in is required

The site presents sign-in as a prerequisite in the hero and download section (`site/index.html:161,191,202,258,269`; the releases page also says it at `site/releases/index.html:164`). But the exact published `v0.1.0-preview.14` source offers an enabled sign-in button and explicitly tells users, **“Plant without signing in. This device garden stays on this device; no sync or analytics.”** (`lib/features/garden/profile_section.dart:108–126` at that tag); the tagged README likewise says signed-out users can plant locally (`README.md:18–23`). This misstates the download’s access requirement and may deter users who could try the local-only garden. Distinguish local use from account sign-in for sync.

### GROWTH-2 — Low — Launch documentation points to superseded preview.12

`docs/website-launch.md:80` says the existing download pointer is preview.12; `docs/website-funnel.md:93–102` likewise identifies preview.12 and refers to its size and warning evidence. In contrast, `site/customer-config.json:6–18` points to preview.14, and the read-only GitHub release lookup confirmed that preview.14 is published as a prerelease with matching asset names, sizes, and SHA-256 digests. Update the stale documentation so it does not misdirect launch operators.

## Positive evidence and gates

The site clearly labels preview.14 as owner-test-only, unsigned, and **not verified for general use**; it does not claim installer safety or completed installation (`site/index.html:191–202`). Its measurement/reporting copy distinguishes events from people, download clicks from completed downloads, and descriptive event ratios from causal conversion (`site/website-panels.mjs:7,75`; `docs/website-launch.md:45–52`). No efficacy inference is supported or made by this review.

The focused launch, download-rendering, and warning-provenance tests passed: **10 passed, 0 failed**. These source-contract tests do not establish the live site’s contents or owner acceptance. The production-origin request failed at DNS resolution; live deployment remains unverified. `docs/status.md:27–30` records owner installation/launch feedback for the newer candidate as **PENDING**. No role-specific public-launch sign-offs were present under `release/signoffs/`; the registry makes this role required for public launch.

## Verdict

**CHANGES_REQUIRED for the growth-website role.** Correct the sign-in prerequisite claim and refresh the stale preview.12 documentation before approval. Public-launch and live-site verification remain separate open gates.
