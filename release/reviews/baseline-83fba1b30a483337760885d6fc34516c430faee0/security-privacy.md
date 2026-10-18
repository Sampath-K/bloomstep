# Security/privacy baseline review

**Target:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Source tree:** `5b2eb392aff651f15dfd3f34b987e1b1282dc098`  
**Worktree:** Clean at review start.  
**Verdict:** **CHANGES_REQUIRED** — two confirmed release-gate issues remain open. This is AI evidence, not owner risk acceptance.

## Scope and method

Enumerated the tracked repository at the target commit and performed a static, role-focused review of authentication and authorization, data handling and telemetry, platform permissions, installer security, deployment workflows, and the newly added release sign-off gate. Searched relevant source/configuration trees for authentication, storage, network, logging, markup, and process-execution patterns; then traced the release candidate/sign-off flow from candidate resolution through publication.

No code or release records were changed. No tests or installers were run; no installer was downloaded or executed; no access/protection settings were changed; no merge, release, or deployment was performed.

**Exact files directly inspected:**

- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/docs/release-governance.md`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/release/roles.json`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/release/reviews/README.md`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/release/signoffs/README.md`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/release/evidence/README.md`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/tool/verify_release_signoffs.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/ci.yml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/installer-security.yml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/production-isolation.yml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/azure.yml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/README.md`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/pubspec.yaml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/package.json`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/backend.mjs` (selected ranges)
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/auth-transport.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/primary-auth.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/functions.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/contracts.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/storage-target.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/support.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/invitations.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/invitation-contracts.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/aggregate-auth.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/api/src/spend-auth.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/identity.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/sync_service.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/session_events.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/session_diagnostics.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/installer_measurement.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/analytics_sandbox.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/remote_config.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/update_service.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/windows_storage_identity.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/windows_toast_history.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/services/microsoft_photo.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/app/session_boundary.dart`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/lib/core/garden_store.dart` (selected ranges)
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/customer.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/operator-auth.mjs`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/console.mjs` (selected range)
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/console.html`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/operator-callback.html`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/config.json`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/site/staticwebapp.config.json`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/packaging/bloomstep.iss`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/tool/inno_compiler_version.ps1`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/android/app/src/main/AndroidManifest.xml`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/ios/Runner/Info.plist`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/windows/runner/runner.exe.manifest`
- `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/macos/Runner/Release.entitlements`

## Security findings

### SEC-1 — Untrusted sign-off metadata reaches a privileged shell command

**Category:** StringInjection  
**Severity: HIGH | Confidence: 9/10**  
**Evidence:** `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/ci.yml:561-564, 569`; `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/tool/verify_release_signoffs.mjs:183-190, 91`

**Problem:** The tag-release workflow resolves a candidate, reads `artifact.runId` directly from the first sign-off JSON file, and writes it to `$GITHUB_OUTPUT` without validating it. The value is then interpolated directly into a Bash script at line 569. `resolveCandidate()` only checks that a candidate directory contains a `.json` file and that its candidate SHA is an ancestor; it does not parse or validate the sign-off record. The numeric `runId` check occurs later in `verifySignoffs()`, after the artifact-download step.

A crafted sign-off record can therefore make the release job execute attacker-supplied shell syntax before the later validation runs. The release job has `contents: write` and `actions: read` permissions (`ci.yml:548-550`). Exploitation requires a commit containing the crafted record to reach a tag-triggered release run; repository tag protections and who can trigger such a run were not inspected.

**Suggested fix:** Validate and constrain the sign-off record and `runId` before writing any workflow output; only accept decimal run IDs. Pass validated values to later steps via environment variables rather than direct `${{ }}` interpolation in shell scripts, and reject multiline output values.

### SEC-2 — Role approvals and owner acceptance are self-asserted, not authenticated

**Category:** BrokenAccessControl  
**Severity: MEDIUM | Confidence: 8/10**  
**Evidence:** `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/tool/verify_release_signoffs.mjs:53-56, 91-103`; `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/.github/workflows/ci.yml:571-586`; `/root/copilot-worktrees/bloomstep/sampath-k-symmetrical-invention/docs/release-governance.md:22-36`

**Problem:** The gate treats role records as approvals based on their contents alone. It checks that reviewer session/model, scope, evidence entries, and owner-acceptance fields are nonempty strings (and that the acceptance timestamp matches a format); it does not authenticate the reviewer or owner, verify an approval from a trusted identity, or require the referenced review file to exist and match the record. The generated evidence is rendered from those same records. The workflow then publishes after the gate without an in-workflow authenticated role-approval check.

A contributor able to supply sign-off records for a tag-triggered run can therefore make the gate report all required roles approved without establishing that those independent reviews or any claimed owner risk acceptance occurred. The practical ability to do this depends on repository write/tag controls, which were not verified.

**Suggested fix:** Bind each role verdict and owner acceptance to an authenticated, independently verifiable approval mechanism (for example, trusted signed attestations or protected required reviewers). Validate that referenced review artifacts exist and correspond to the signed verdicts; do not treat reviewer/owner identity strings as authorization.

## Low-severity findings

None substantiated.

## Unverified runtime and owner gates

The supplied context says candidate `083f2de` was previously static-clean with manual installer feedback pending, and that an earlier `9085df1` installer had Defender behavior detected. I did not independently verify those observations or any runtime behavior. No installer was executed and no current Defender/SmartScreen result was collected. Repository branch/tag protection settings and external identity-provider, cloud, and deployment configuration were not inspected. These remain owner/runtime gates and are not additional findings from this static review.
