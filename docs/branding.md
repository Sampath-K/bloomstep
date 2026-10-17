# Bud Lark branding and retained-name inventory

The app's exact product name is **Bud Lark**. The registered domain is **budlark.com**.
The user's correction supersedes the mistaken, unshipped Budlock name in commit
`eba2c0db9739ef63f34064415accc07be3853212`; that name is not a second product identity.
Current display text, metadata, contracts, wordmark and social card use Bud Lark.
Only this correction record and a negative regression assertion retain the mistaken name.
This source change does not
attach that domain, change DNS, redirect traffic, deploy, publish, release or sign
anything. The repository remains `Sampath-K/bloomstep`.

## Changed customer surfaces

| Surface | Source and disposition |
| --- | --- |
| App and native UI | `lib/app/bloomstep_app.dart`, garden/profile screens, invitation/share/callback/error copy, tray and notification display text, Windows window title and file/product/publisher metadata now say Bud Lark. Source class names are unchanged. |
| Platform display metadata | Android application label, iOS/macOS `CFBundleDisplayName` and short `CFBundleName`, and the package description say Bud Lark. Build products, bundle IDs and package names are unchanged. |
| Installer UI | `packaging/bloomstep.iss` and `install-progress.iss` use Bud Lark for product/publisher, invitation description, introduction and Launch checkbox. Strict product-resource and accessibility validators follow the new display text without loosening their checks. |
| Website and release metadata | Both customer pages, structured data, social/search descriptions, download labels, invitations, operator console and callback use Bud Lark. The release-bundle description generator uses Bud Lark; existing download URLs, filenames, hashes and owner-test restrictions remain exact. |
| Current docs | README, product contract, website-funnel description, deployment branding instructions, active installer/VM checkbox instructions and the unreleased changelog use Bud Lark. Historical sections are not rewritten. |
| Current brand assets | Existing flower, palette and layout retained; wordmark and social-card text now say Bud Lark. Their asset paths stay stable. `generate_brand_assets.py --text-only` can generate both with Pillow; `create_social_image.ps1` also uses the new name. |
| Hosted sign-in source | `infra/configure-customer-branding.ps1` and its mocked preservation/readback test now target Bud Lark text. The live tenant has **not** been modified or verified. |

## Retained occurrences and rationale

Inventory covers tracked text, case-insensitively, plus tracked asset filenames
and known text-bearing binary images. At base `a778a66`, `git grep -I -i -o
bloomstep` found **1,429 occurrences in 232 files**. A retained occurrence is
not necessarily branding: most are imports, infrastructure and test contracts.
After this migration there are **1,280 occurrences in 224 files**, excluding this
inventory document itself (including assertions that protect retained names).
The following categories account for the remaining names; files can span more
than one category.

| Category | Retained names and locations | Why retained |
| --- | --- | --- |
| Repository, URLs and origins | `Sampath-K/bloomstep` throughout workflows, update checks, docs, tools, release config/build/render code and tests; existing Azure site origins and sitemap/canonical URLs | Avoid broken links, changed update trust allowlists, deployment or unapproved domain routing. `budlark.com` is registered but not assumed configured. |
| Source/package compatibility | `pubspec.yaml` name; `package:bloomstep` imports in tests/tools/integration tests; `BloomstepApp`, `BloomstepTheme`, `BloomstepWindowsPaths`; internal Node package names/lockfiles; source filenames | Renaming the product does not require a public source/API or dependency-identity migration. |
| Binary and bundle identity | `windows/CMakeLists.txt`, `Runner.rc` InternalName/OriginalFilename; Android namespace/application ID/Kotlin package; iOS bundle IDs; macOS build-product name/bundle ID, project references, scheme, test hosts and existing copyright identity | Preserve installed-app identity, native build wiring, tests and plugin path derivation. Use separate display metadata rather than rename executables or invent a legal owner. |
| Existing Windows installation and startup | Installer AppId, `Programs\Bloomstep`, `DefaultGroupName=Bloomstep`, `Bloomstep`/`Uninstall Bloomstep` shortcut paths, old startup `.lnk` cleanup and Run value; `launchAtStartup.setup(appName: 'Bloomstep')` | These are also visible legacy names. Keep upgrade/uninstall/startup identity to avoid duplicates, stale shortcuts or changing existing user choices. A separately validated shortcut/startup migration is deferred. |
| Local/private state | `com.bloomstep\bloomstep` support/cache/DPAPI paths; `%LOCALAPPDATA%\Bloomstep\measurement`; `bloomstep-session`; browser measurement/invitation keys; export filenames | Preserve gardens, credentials, consent, pending invitations, instance locks and recognizable export formats. No state is copied, reset, migrated or deleted. |
| Protocol and integration contracts | `bloomstep://`, `Software\Classes\bloomstep`, `bloomstep/native_share`, `bloomstep/toast_history`, `Bloomstep.Garden` AUMID and `Bloomstep` toast group, `X-Bloomstep-Authorization`, event schemas/registry | Existing links, native channels, notifications and authenticated requests must continue to work. User-facing descriptions around them use Bud Lark. |
| Infrastructure and security identity | `api/`, `infra/`, `.github/workflows/`, `site/production-isolation.mjs`: Cosmos `bloomstep/data`, Azure resource/tenant/registered application names and tags, `Bloomstep.Admin`, `Bloomstep.AggregateWriter`, `Bloomstep.SpendGuard`, `BLOOMSTEP_*` settings, GitHub environments/secrets, test users/flows and federated subjects | Identity discovery and authorization depend on these exact values. Renaming some display names would create a different registration in existing name-based reconciliation. No infrastructure or protected CI is changed. Operator messages still name actual required roles. |
| Published artifacts and release tooling | `site/customer-config.json`, both HTML pages, `site/release-downloads.mjs`, `site/build.mjs`, `tool/release_bundle.mjs`, `tool/release_payload.mjs`, installer output filename and verification fixtures: `Bloomstep-<version>-windows-<arch>-setup.exe` | Existing release files are immutable. Retain artifact naming end-to-end instead of making links point to nonexistent Bud Lark files or changing protected release CI. Future artifact renaming is a separate coordinated decision. |
| Existing asset paths | `site/assets/bloomstep-{icon,favicon,wordmark,social}.png`, HTML/configuration/generator references and `.gitignore` entries | Stable references are harmless; current wordmark/social pixels say Bud Lark. Flower-only icons contain no old product text and are unchanged. |
| Historical screenshots and provenance | `sample-garden.png`, warning/download PNGs, their three provenance JSON files, `bloomstep-download-help-sample.txt`, installer education-art provenance | Authentic capture labels, hashes and source revisions must remain truthful. The sample-garden caption explicitly identifies the pre-rename preview. Warning alt text keeps the actual filename shown. No audit image is repainted. |
| Historical records and operational project names | Existing changelog releases; `docs/status.md`, `acceptance.md`, `mvp-exit-matrix.md`, `analytics-sandbox.md`, `website-launch.md`, historical installer/deployment sections, security/backend/measurement docs and recorded analytics project names | Keep revision-specific observations, release evidence, approved contacts and real resource/project labels, not retroactive claims that old builds or hosted pages were called Bud Lark. Current branding guidance above takes precedence. |
| Fixtures and verification scaffolding | `test/`, `integration_test/`, `tool/`, `site/test/`, `api/test/`, `infra/test*`: temporary evidence paths, synthetic recipe text, package imports, preserved identifiers and historical release fixtures; `Bloomstep isolated journey proof` in installer/validator/protected CI | Keep bounded synthetic identities and compatibility assertions. Tests of current product labels were updated; strict installer resource checks now expect Bud Lark for the real product, but preserve the exact isolated fixture identity pinned by protected CI. Helper function names remain source-compatible. |

Reproduce the complete line-level inventory without reading ignored build output:

```sh
git grep -n -I -i bloomstep
git ls-files '*bloomstep*' '*Bloomstep*'
```

`test/branding_contract_test.mjs` checks the new product name and explicit retained
identity contracts. Its customer-prose scan permits only specific protocol,
startup/state, role, published filename and historical-screenshot exceptions.

## Verification

- Contracts were corrected first to the exact **Bud Lark** display name; six
  branding contracts failed against parent `eba2c0d` before source changes.
  Final targeted run: **118 passed, 0 failed, 3 Windows-only skips** across
  branding, installer, release, measurement packaging, website and the real
  loopback operator-preview browser journey.
- `npm --prefix site run build` succeeds. `site/verify-browser.mjs` passes at the
  local preview origin, including Bud Lark titles/structured data, responsive
  layouts, no-JS, dark/forced-colors, privacy signals and API-outage download checks.
  Android XML and both Apple property lists parse with Bud Lark display metadata.
- The correction's broader `node --test test/*.mjs` run has **92 passed,
  1 failed, 3 skipped**, with the sole pre-existing failure in
  `test/support_surface_contract_test.mjs:44`: the expected support-copy sentence
  is absent from `site/releases/index.html` at both parent `eba2c0d` and original
  base `a778a66`. No unrelated
  privacy copy or test was changed to conceal it.
- Native Flutter tests/builds are blocked as described below; browser/source
  contracts are not native installer, upgrade or user-data runtime acceptance.

## Deferred decisions and external work

- No Store listing/package manifest is checked in. Store, Google OAuth branding,
  hosted customer-tenant branding and any live release descriptions still need
  separately authorized owner review/publication; updated source is not readback.
- Protected `.github/workflows/ci.yml` still authors release titles/body text
  containing Bloomstep. Updating that future publishing metadata and its older
  publisher-path probe is deferred because protected CI changes are explicitly
  excluded. No release was created, edited or published.
- No new logo, lock motif, palette, slogan or trademark/legal-controller claim is
  introduced. Final brand identity is deferred. Existing flower artwork is reused.
  The regenerated wordmark/social card use available FreeSans Bold/Regular on
  Linux in place of the generator's Windows Segoe UI defaults.
- A shortcut/startup/artifact rename needs explicit upgrade and protected native
  lifecycle evidence. Existing user state and immutable downloads take priority
  over removing every visible legacy filename.
- Flutter/Dart are absent on this Linux host; the official SDK metadata download
  returned HTTP 403. Native Flutter tests/builds and Windows installer compilation,
  upgrade, notification and runtime acceptance are therefore not claimed.
  No unrelated Dev Box session, branch or validation process was used.
