# Preview.15 cloud handoff

**17 October 2026. Cloud session `833fae00` owns continuation after this note
is pushed. Local session `964ad09d-7fce-4b66-a8fc-670c4493a195` stops.**

## Superseding owner direction

The owner aborted the VM/local-runner work. Protected self-hosted installer
acceptance is removed from the launch workflow; no runner setup, VM provisioning,
or queue retry is in scope. Hosted API, x64/ARM64 build/test, installer
correctness/package checks remain. The owner will manually verify the exact
downloaded Budlark installer; acceptance stays **PENDING** until feedback is
recorded against that artifact's source SHA and checksum.

This handoff's later VM-gate and release sequence is historical and superseded
by the owner's instruction. Do not merge, tag, release, deploy, change account
access/protection, or update the public download pointer before separate
authorization. PR51's website-doc change is separate and must remain untouched
from this branch.

Repository: `Sampath-K/budlark`.
Continue on `sampath-k-ship-owner-trial-installer-fixes`, PR #48.
Last code-changing head: `8dc00de88c0b8414065026f7c1cc46f2db35ea3a`.
This handoff/proposal/status commit is documentation-only; resolve its exact
SHA from Git. Main at readback:
`a778a66560b8a7b3ee9449d8e00af876c41461ec`.
No PR was merged, preview.15 tag created, release published, or site deployed
by this handoff.

## Exact branch manifest and dispositions

| PR | Branch and observed head SHA | Disposition |
| --- | --- | --- |
| #48 | `sampath-k-ship-owner-trial-installer-fixes` / `8dc00de88c0b8414065026f7c1cc46f2db35ea3a` before this documentation commit | Merge the final checked head only after required engineering checks pass. Includes approved continuity, name, practice-first hierarchy/copy, default-off GrowthBook lineage, #50 tooling and fail-closed #36 foundation. |
| #49 | `sampath-k-autonomous-funnel-experiments` / `de90e7b59a6cdeaddd1c89035b9b701a25f8eaf6` | Patch-equivalent content is already in #48. After #48 merges, close as superseded with its exact merged commit; keep GrowthBook off. |
| #50 | `sampath-k-live-preview-project-status` / `c584b23b9b29046730063489ab18dfe225ab26de` | Both unique commits composed in `8d3fb21729215bec33aff43796acd491a1310510`; 21 contracts pass. After #48 merges, close as composed with exact main evidence. |
| #36 | `sampath-k-microsoft-profile-photos` / `6a2a975aceb81df70f2eff0962d8f1f33b76c963` | Both unique commits composed in `8dc00de88c0b8414065026f7c1cc46f2db35ea3a`. Production `microsoftPhotoIdentity` is still null; no browser, Graph call, permission, credential or photo activation. Preserve name/compact hierarchy. Close as composed only after #48 lands. |
| #26 | `sampath-k-real-installer-warning-guide` / `91e678865d42b1d74e23ec5207c30df43d323604` | Do not merge wholesale: installer/profile fixes were composed by #46/#47, but this historical branch also contains #38's held coach changes. Close as superseded only with a comment distinguishing shipped installer/profile commits from the explicitly unshipped coach patch. |
| #27 | `sampath-k-budlark-automatic-updates` / `3ec07ccc50aaed741cec642f521d30b53f80464f` | Leave open/unmerged, excluded from preview.15 pending exact visual/copy approval. No signing, feed, trust, installation or activation. |
| #29 | `sampath-k-budlark-growth-layer` / `e88bfaa639fcf9d20232e3065b9252759e32bc93` | Leave open/unmerged, excluded from preview.15 pending exact weekly-summary visual/copy approval. |
| #30 | `sampath-k-guided-success-recovery` / `c9b119c0e324f74c2f8e2f3e7b53845112700e08` | Leave open/unmerged, excluded from preview.15 pending exact recovery-card visual/copy approval. |
| #38 | `sampath-k-surprise-badges-and-habit-coach` / `77d7e75d163fbfd95cf9f15fb296889773217c5e` | Leave open/unmerged, excluded from preview.15 pending badge/coach copy, layout and motion approval. |
| #28 | `sampath-k-habit-first-profile-sign-in` / `adb51b30da43e0629efd5ee6db5b0d545f625150` | Already closed as superseded by `b2b85233ccb034eb4439df5e4ebd9ee9044ee91d` and `d0c3ad1dbaa8a2f42a6f9dcb8277d94b1d749603`; closure comment cites first-habit wiring/tests. |
| #31 | `sampath-k-profile-refinement` / `7e7b7d1e52c8f0c4260584bd136b1499a52cafa3` | Already closed as superseded by `ef4f755991b4744dfb7c1866430793cf3030a8e2`, `2e1d3ecc4e3d50699f99245dff2ed8b6ef2f2ee6`, `d0c3ad1dbaa8a2f42a6f9dcb8277d94b1d749603`, and `7552b520e183d219f668fbdc02005d8acb20758f`. |
| #33 | `sampath-k-budlark-aarrr-funnel-dashboard` / `8b5e317cc47a62208a749683bc5ab2c48d193401` | Already closed as superseded: its head is an ancestor of main, including composition `1701911be537e0c543267a0163574e5bb9c4a20b`. |

The coordinator explicitly resolved on 17 October: no exact owner approval is
available for #27/#29/#30/#38; "merge all PRs" does not override mockups-before-code.
**Those four PRs must not block the approved preview.15 scope.** Leave them
unmerged with the written dispositions above, rather than adding their UI.

## Approval-held proposals

- Copy/source table: `docs/evidence/copy-review/deferred-pr-copy.md`.
- Conceptual, self-contained review gallery:
  `docs/evidence/visual-quality/proposals/deferred-pr-gallery.html`.
- Gallery opened and read back in Browser canvas; it is explicitly not an
  actual Flutter render or a native accessibility pass. No production UI
  strings or motion for these four PRs were implemented.
- #27 conflicts: raw exception interpolation, long jargon-heavy dialog, and
  a permanent bottom status row that could consume the primary viewport.
  Proposal keeps updates in Settings, uses short safe errors, retains manual
  installation, and proposes automatic discovery off pending owner decision.
- #29 conflicts: unreviewed weekly-summary layout, internal “deterministic”
  language, raw errors, and long sync disclosure.
- #30 conflict: unreviewed extra recovery card and text within practice cards.
- #38 conflicts: new badge/coach cards and an unapproved 700 ms fade.
  Proposal is static and secondary to practice. New motion needs separate
  approval and reduced-motion support.

These are proposals only. Do not implement them during the cloud release job.
Keep the separate final visual/motion polish pass approval-gated.

## Verified implementation and local evidence

Approved packet: `8a0772cf8fc5bb8d46c9d70bc4e70f5b340fab17`.
Implementation: `ad80c230982f6ec99e47079da71831592f220498`.
Strict containment correction:
`6adb889db5a95e9345cd2894519c383a2c302058`.
E2E title alignment:
`56100590d4715773f21c7f945f1cf3a7378f26c3`.

`garden_chrome_visual_test.dart` supplies the exact `MediaQuery.size` and
asserts all four edges of the full Did it control inside 420x820/200% and
640x480/200%, plus recipe context, semantics and keyboard order. It is not
just center/hit-test visibility. Source-rendered synthetic screenshots already
opened in Browser:

- `docs/evidence/visual-quality/chrome-account-populated-large.png`
- `docs/evidence/visual-quality/chrome-account-populated-short-large.png`
- `docs/evidence/visual-quality/device-copy-confirmation-SYNTHETIC.png`

The older `combined-device-copy-confirmation-SYNTHETIC.png` is stale.
The copy guide and release-blocking accessibility rule are in the product spec,
visual review/scorecard and `docs/copy-guide.md`.

At `8dc00de`, analyzer passed and 37 targeted photo/profile/viewport tests
passed. The photo avatar test was reconciled with the approved requirement
that the profile name remains visible; it still verifies the image and cache
eviction. The full Flutter suite returned exit 0 through watchdog run-check
(300-second cap), receipt
`7b5f1da8203227716745bc3b503e19d96a7f55b81c2a07d48fac336df7c74358`.
The dashboard contract receipt at `8d3fb21` is
`23f8814473159223ef8cad5a445a71328c326a8518e8a1a108be4a4b272f79e4`.
Receipts are local watchdog evidence, not cloud-accessible build artifacts.
Subsequent documentation changes make their workspace fingerprints historical;
rerun on the final cloud checkout, do not claim they attest a newer head.

Working local test invocation:

```powershell
flutter test --no-pub --no-test-assets --dart-define=BUDLARK_TEST_BUILD=true --concurrency 1 --reporter compact
```

Local `build\unit_test_assets` is a locked/protected asset path: ordinary
desktop integration setup failed to delete it. No deletion or OS setting
change was attempted. `--no-test-assets` unit/widget runs pass; genuine
native/plugin/asset compilation must be established by hosted Windows CI.
Watchdog uses explicit `cmd.exe /d /c C:\src\flutter\bin\flutter.bat ...`;
bare `flutter` produced `FileNotFoundError` in Python subprocess resolution.

## Historical CI and VM gates at handoff (superseded)

Refresh all states; queued workflow status can coexist with completed hosted
jobs because protected jobs lack a runner.

| Source | Run | Last observed result |
| --- | --- | --- |
| `8dc00de` | `38992052747` | API and funnel pass; hosted x64/ARM64 in progress; protected launch queued. |
| `8dc00de` | `38992047528` | API pass; hosted x64/ARM64 and funnel in progress; protected launch queued. |
| `8dc00de` | `38992052592` | Customer acquisition site pass. |
| `8dc00de` | `38992052642` | Isolated telemetry functional acceptance pass. |
| `8dc00de` | `38992052669`, `38992047596` | Offline analytics sandbox proof pass. |
| `8d3fb21` | `38991881705`, `38991877548` | Superseded CI runs queued; not final-head evidence. |
| `5610059` | `38991233816`, `38991229735` | Superseded native runs; API/funnel pass, native jobs had advanced into app contracts/E2E. Refresh outcomes only for diagnosis, not final-head proof. |
| `6adb889` | `38988575392`, `38988579638` | Hosted x64/ARM64 failed stale E2E expectation “Delete this recipe?”; fixed by `5610059` to the approved “Delete recipe?”. |

The handoff documentation commit triggers new checks; inspect its exact SHA.
The PR48 description is historical/stale (it still describes the old below-fold
follow-up); update it with the implemented containment results and current
commit/gate evidence before merge.

Repository runners API returned `total_count: 0`, `runners: []` at handoff.
No approved self-hosted `defender-interactive` runner is available. Protected
install/launch, lifecycle, genuine checked/unchecked app launch, Narrator,
high contrast, mixed DPI and real-provider/owner-installed acceptance are
**UNVERIFIED**, never pass-by-inference. Preserve all guards and runner checks.
Do not provision resources, change credentials or protections to clear them.

## Remaining work under the current owner direction

1. Finish the CI/launch contract edits on this feature branch without touching
   PR51. Keep hosted tests/builds and installer correctness contracts; remove
   all self-hosted installer execution dependencies.
2. Resolve merge conflicts and run the smallest relevant Node contracts,
   workflow validation and the existing hosted CI on the pushed exact head.
   Report missing/failed checks as blockers; do not weaken required protections.
3. Provide the downloadable installer from the hosted Actions artifact with its
   exact source commit, run/check evidence and SHA-256. Do not create a tag or
   GitHub release, deploy, merge, or update the public download pointer.
4. Wait for the owner's manual verification feedback. Record only observed
   result; until then installer acceptance is **PENDING**, not passed.

## Non-negotiable scope

The production site and `site/customer-config.json` stay on preview.14.
No Azure deployment/site promotion, signing/updater activation, cloud resource,
permission, credential, notification or experiment-flag change is authorized.
Mockups and editorial review come before new UI/copy code. Accessibility or
hierarchy defects of this grade block release; no deferral as polish.
No SmartScreen/Defender/security-warning bypass. No merge or release without
the applicable gates and explicit, honestly recorded trial exceptions.
