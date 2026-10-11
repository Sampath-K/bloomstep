# Automatic updates: capability and activation gates

## Current customer behavior

The public website still distributes the immutable unsigned Inno preview.12.
Those installed copies have only the old manual release check. They cannot
receive this implementation, or future fixes, automatically without a trusted
one-time bootstrap. This PR does not install, publish, promote, or migrate anyone.

New builds check the approved GitHub repository at startup and every 24 hours
while running, including before sign-in. A visible status and persistent opt-out
are available on every app route. Checks do not download or run installers,
terminate work, change consent, sign out, or touch garden databases. Network,
authentication/rate-limit and corrupt-preference errors remain visible.
The existing manual check is retained. Preference storage is an independent
`updates\preferences.json` under the existing application support directory.

## Implemented automatic apply engine

The optional signed MSIX distribution uses **Windows App Installer**, not a
custom script that executes unsigned EXEs. `tool\msix_update.mjs` generates the
real package manifests and the enrolling `Bloomstep.appinstaller` feed;
`tool\build_msix.ps1` packages verified same-source x64/ARM64 Release trees into
one native-routing bundle, signs both packages and bundle with an explicitly
approved certificate, and requires Windows signature/trust verification.

Customers must install through **the `.appinstaller` file**, not the bare bundle.
The feed enrolls Windows launch checks (zero-hour interval, no prompt, no
activation blocking) plus its approximately eight-hour background task. Windows
owns payload verification, native architecture selection and transactional
package deployment; Bloomstep never launches a downloaded executable.
No force-shutdown or forced downgrade option is used. Running app updates may
be deferred until it exits; reminder-enabled close-to-tray is not an exit.
Saved active work is not deliberately interrupted. A failed deployment does not
become a success in the app; Windows App Installer/Deployment diagnostics are
the source of installation errors. There is no automatic rollback of a
successfully installed but logically faulty release: repair requires a fixed,
higher-version signed package, not a downgrade or a database rollback.

Trust is Windows-validated package signing with the exact package
name/publisher identity. SHA-256 receipts bind candidate bytes/provenance, **not
publisher authenticity**. The feed is HTTPS on the existing GitHub repository;
it is not itself a detached-signed document. Windows binds the installed package
to its publisher/name and only accepts validly signed applicable higher versions.
A hostile feed can withhold updates, but must not authorize another publisher's
code. Never allow `ForceUpdateFromAnyVersion`, force-close apps, trust a root
downloaded from the feed, or silently replace this with unsigned Inno execution.

Preview and stable use separate fixed package identities. SemVer
`major.minor.patch-preview.N` maps to `major.minor.patch.N`; stable maps to
`major.minor.patch.65535`. Components are bounded to Windows' 16-bit range;
preview revisions are 1..65534. Unsupported suffixes, build metadata, ambiguous
versions and x86 fail closed. Stable/preview switching requires a separately
approved bootstrap, never cross-channel automatic installation.
The existing unnumbered developer `-preview` maps to revision zero for SDK
validation only; the signing builder rejects it as a production candidate.

## Build and release integration (not activated)

The manual `signed-msix-candidate` workflow takes an exact successful existing
CI run and version, verifies commit/run/artifact provenance, and executes the
builder behind the `msix-signing` environment. Configure required environment
reviewers **before using it**, plus approved public variables
`BLOOMSTEP_MSIX_PUBLISHER`, `BLOOMSTEP_MSIX_CERTIFICATE_THUMBPRINT` and protected
secrets `BLOOMSTEP_MSIX_PFX_BASE64`, `BLOOMSTEP_MSIX_PFX_PASSWORD`.
The certificate needs code-signing EKU, a private key and a Windows-trusted chain.
Normal CI also packages its **real compiled Bloomstep** x64/ARM64 Release
artifacts with the same builder's explicit `-UnsignedValidationOnly` mode.
It validates SDK schema/architecture/provenance and uploads only an accurately
labeled receipt, not an unsigned MSIX. This is not an install/signature pass.
No certificate/root is provisioned by this PR. Current Inno publication and
genuine launch gates are unchanged; the candidate workflow only uploads workflow
artifacts, never publishes a customer release or updates the website. Artifacts
in a public repository must not be described as private distribution.
Production timestamping/key lifecycle must be approved before public signing.

After separate release authorization and all gates below, publish the exact
verified immutable bundle as
`v<version>/Bloomstep-<version>.msixbundle`. Publish the channel enrollment feed
at `update-preview/Bloomstep.appinstaller` or `update-stable/Bloomstep.appinstaller`.
Those new channel feed releases are **mutable metadata only**: update their feed
asset monotonically; do not replace existing executable release assets.
Add an approved customer website link to the enrolling feed only after verifying
GitHub redirects/MIME/download behavior with actual App Installer.
Feed expiry is not enforced by Windows; availability/freshness require operator
monitoring. Do not repoint today's unsigned preview download as part of testing.

## Preservation and genuine remaining gates

Manifest activation is `win32App`, full-trust `mediumIL`, Windows 10 2004+/11,
not virtualized Desktop Bridge `packagedClassicApp`. Existing
`com.bloomstep\bloomstep` Windows known-folder paths, DPAPI plugin/version,
account-specific SQLite files, single-instance locks and consent are unchanged.
No file copying, credential decoding, database migration, uninstall of Inno, or
registry cleanup is implemented. The `bloomstep` protocol is declared in MSIX.

This design reduces AppData virtualization risk; it **does not prove migration**.
Production remains blocked until a disposable ordinary-user Windows slot proves:

- Approved trusted signing, real app launch and `.appinstaller` enrollment on
  native x64 and ARM64, including actual Flutter/VC++ runtime dependency
  availability; no trust/root relaxation on customer machines.
- Synthetic legacy SQLite garden, account/session DPAPI records and consent
  survive Inno-to-MSIX bootstrap and a real version A-to-B packaged update, with
  unchanged physical storage identity and one shared instance lock. Never use
  the owner's installed app or private data for this test.
- Active editing/sync/reminders are deferred safely; exit and next launch apply
  B without lost pending writes, sign-out or unintended consent changes.
- Offline/disabled/policy-blocked, same-version, wrong publisher/architecture/
  channel, downgrade, corrupt/partial payload and failed deployment cases retain
  A and expose actual Windows errors/retry behavior. Validate transactional
  failure recovery on disposable machines, not merely source assertions.
- Website enrollment and signed feed rotation from A to B, approved bootstrap
  instructions and certificate renewal/key custody.

Source/unit contracts and SDK packaging evidence are distinct from these
installed-app tests. Existing synthetic DPAPI regression establishes unpackaged
branding preservation only, not packaged migration. An offline, disabled,
blocked or never-enrolled client cannot be guaranteed instantly latest; launch
checks are nonblocking to preserve offline use, and background checks are not
continuous. Security fixes still require communication and observable rollout.

### Local implementation evidence

`tool\verify_msix_packaging.ps1` exercises the actual Windows SDK with two
monotonic versions and x64/ARM64 manifests/bundles, file-only ephemeral
code-signing keys, CMS publisher signature verification, and expected Windows
trust rejection for that unprovisioned publisher. It does not enroll a root,
install a package or execute its deliberately inert payload. Its receipt labels
automatic application, app launch and data migration **NOT TESTED**; private key
material is deleted even on failure.

The updater scheduler, UI/navigation, release discovery and existing physical
Windows DPAPI/storage contracts have targeted tests. A real Windows build was
attempted after resolving worktree-only junction/short-path issues; this host
lacks Visual Studio ATL (`atlbase.h`), required by the existing notifications
plugin. Native build success must come from the unchanged native CI gates or a
properly provisioned disposable build worker, not be inferred from Dart analysis.

References:
[Windows automatic update/repair](https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview),
[UpdateSettings](https://learn.microsoft.com/en-us/uwp/schemas/appinstallerschema/element-update-settings),
[packaged Win32 runtime/storage behavior](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes).
