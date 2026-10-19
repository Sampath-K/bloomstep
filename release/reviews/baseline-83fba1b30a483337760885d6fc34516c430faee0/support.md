# Support and Community Review

**Baseline:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Worktree:** Clean; no edits made.  
**Review type:** Read-only source and documentation review. No live mailbox, deployed Admin account, customer feedback, or GitHub issue triage was accessed; tests were not run.

## Scope and method

Reviewed the support role’s governance requirements, then traced the in-app feedback form through local storage, sync/API handling, authorized team access, response display, and support metrics. Compared those paths with public support/privacy copy and the documented acceptance state. Searched the relevant repository areas for triage and known-issues guidance. Did not inspect other role reviews or drafts.

## Findings

### SUP-1 — MEDIUM — Public-launch support operations remain unverified

**Readiness gate, not a demonstrated software defect.** The public contact is owner-approved and published, but the repository explicitly says its delivery has not been tested and no response deadline is promised (`docs/website-launch.md:64–67, 97–100`). The actual Admin feedback/rating round trip is still pending (`docs/status.md:584`); the feedback/team-response journey is marked partial (`docs/mvp-exit-matrix.md:61`). Business-day response measurement is unavailable because no calendar is configured (`api/src/support.mjs:99`; `docs/measurement.md:157`). I found no in-repository support triage or known-issues procedure in the reviewed paths.

The implementation has useful safeguards: team routes require the product-team role and exclude the spend-guard role (`api/src/backend.mjs:445–450`); feedback reads are audited before querying (`:567–579`). These safeguards do not establish that the contact reaches a monitored inbox or that an authorized operator can complete the real customer loop.

**Before Support sign-off:** verify the owner-controlled contact route and monitoring, identify triage/known-issue ownership, and complete an authorized feedback submit/status/reply/readback and exact-fixture-cleanup check. This does not require promising an SLA if the owner chooses not to.

### SUP-2 — LOW — In-app privacy warning is less specific than public guidance

The in-app form warns against “secrets or private account details” and says queued feedback may later reach the team (`lib/features/garden/garden_screen.dart:948–958`). The public FAQ additionally warns against including “sensitive habit details” (`site/index.html:260`), and the privacy notice says not to store medical records or other sensitive information in Budlark (`site/index.html:283`). Align the in-app warning with that more specific guidance. This is a copy/privacy clarity gap; I found no evidence of an actual disclosure or unauthorized access.

### SUP-3 — LOW — Website-funnel document has a stale contact TODO

`docs/website-funnel.md:104–105` still says the owner must supply a controller identity and privacy contact. The reviewed launch documentation and site already identify the project owner and publish the owner-approved contact (`docs/website-launch.md:64–65`; `site/index.html:281, 295`). Legal-basis and provider/backup-retention questions remain unresolved, so update the TODO to distinguish those outstanding items from the supplied identity/contact.

## Verdict

**CHANGES_REQUIRED for the public-launch Support role.** The code paths and privacy boundaries are reasonably structured, but operational intake, live feedback handling, and triage readiness lack verification; the in-app warning and one documentation TODO also need alignment. This verdict does **not** treat the owner mailbox or live-service gates as proven defects, and does not accept risk on the owner’s behalf.

The withdrawn Defender-quarantined binary remains excluded. Exact-installer manual acceptance remains **PENDING** as a separate release gate; it is not a support finding.

## Files inspected

- `release/roles.json`; `docs/release-governance.md`
- `docs/website-launch.md`; `docs/website-funnel.md`; `docs/mvp-exit-matrix.md`; selected portions of `docs/status.md`, `docs/measurement.md`, `docs/product-spec.md`, and `docs/backend-contracts.md`
- `site/index.html`; `site/releases/index.html`; relevant references in `site/verify-launch.mjs` and `site/test/launch.test.mjs`
- Relevant sections of `lib/features/garden/garden_screen.dart` and `lib/core/garden_store.dart`
- `api/src/support.mjs`; relevant sections of `api/src/backend.mjs`; `api/src/contracts.mjs`; support-related references in `api/src/functions.mjs`, `api/src/engagement.mjs`, and `api/src/goals.mjs`
- `api/test/support.test.mjs`; `test/support_surface_contract_test.mjs`; support-related references in `api/test/engagement.test.mjs`
