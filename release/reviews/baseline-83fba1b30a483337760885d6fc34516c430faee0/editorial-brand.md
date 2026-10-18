# Editorial-brand baseline review

**Baseline:** `83fba1b30a483337760885d6fc34516c430faee0`  
**Role:** `editorial-brand` — Budlark voice, naming consistency, launch materials  
**Mode:** Read-only. Worktree was clean before and after review. No edits, commits, sign-offs, or release/deployment actions.

## Scope and method

No `governance/roles/branding` directory was present. I used `release/roles.json` for role requirements and `docs/branding.md` for the retained-name inventory, then reviewed current copy guidance, launch/status documentation, customer-site source, changelog, relevant app error copy, and branding contracts. I checked source references with targeted searches and verified cited lines directly. I did **not** inspect a live deployment, run tests, or verify that public pages currently serve this source.

## Findings

### ED-01 — P2: Launch checklist names a superseded download pointer

`docs/website-launch.md:80` says “Existing preview.12 pointer unchanged,” but checked-in `site/customer-config.json:6–18` points to preview.14; both customer pages also identify preview.14 (`site/index.html:191–200`, `site/releases/index.html:132–156`), and `CHANGELOG.md:25` says preview.12 is superseded. This makes the launch checklist inconsistent with the current source and could misdirect launch decisions. Update the checklist to describe the source pointer accurately. **This is a source/documentation finding, not evidence about what is currently deployed.**

### ED-02 — P3: Active copy guide retains the former product name

`docs/copy-guide.md:1,13–14` calls itself the “Bloomstep” editorial guide and says to use terms “unless Bloomstep has a user-tested term.” That conflicts with the current name in `docs/branding.md:3,8` and its statement that current documents should use Budlark (`:22`). Update the guide’s product references; this is internal editorial guidance, not a customer-facing defect.

### ED-03 — P2: Startup error suggests fixes that do not cover all caught failures

`lib/main.dart:22–43` includes support-directory setup, invitation parsing, instance startup, and window operations inside one `try`; `:44–53` catches all failures but tells users to use a valid link or close an existing window. Those steps do not address failures such as support-directory or window initialization errors. Split the error paths or give a neutral, actionable recovery route for non-link failures.

**Severity mapping:** P2 = medium; P3 = low.

## Inspected files

`release/roles.json`; `docs/branding.md`; `docs/copy-guide.md`; `docs/website-launch.md`; `docs/status.md`; `docs/release/preview15-handoff.md`; `README.md`; `CHANGELOG.md`; `site/index.html`; `site/releases/index.html`; `site/customer-config.json`; `site/release-downloads.mjs`; `lib/main.dart`; `lib/core/garden_store.dart`; `test/branding_contract_test.mjs`.

## Disposition and verdict

Historical warning captures and published `Bloomstep-…` filenames, repository/package/protocol identifiers, and the explicitly documented `launchAtStartup.setup(appName: 'Bloomstep')` compatibility identity were **not** treated as rename findings. The customer-site source consistently describes an owner-only preview and warns that it is unverified for general use. The served public deployment was not checked.

**Editorial-brand assessment: not ready to record as a public-launch sign-off** while ED-01–03 remain unresolved. `release/roles.json:7,64–67` requires evidence-backed sign-off bound to the exact candidate commit, source tree, and installer SHA-256; this review does not provide or record that sign-off.
