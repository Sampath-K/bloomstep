# Installer and customer onboarding contract

Authorized source increment from main `30fd380194bed46686c5483accfa71ff06c9f068`.
The original source increment did not authorize a release. On 7 October 2026,
the owner separately authorized website promotion of the already published
preview.9 and standing quality-gated immutable preview releases for subsequent
app/installer merges. Existing preview.8/preview.9 binaries remain immutable.
Parent pixel review and mandatory exact-source quality gates still gate this
candidate. The user-directed frozen-v1 resequence defers the new operational
pipeline; the exact preview.10 and separately authorized recovery preview.12
owner-manual-trial exceptions are described below.
No new release has been published by this increment.
The separate website-only preview.9 promotion did not itself authorize app
changes or release/tag mutation. The preview.8 warning/capture evidence below
remains historical and must not be relabeled as preview.9.

## Bounded universal follow-up (unreleased)

PR21 merged as `45efbf2da0cb8363675321e5e257d5dd66391f04`; that exact source
was published as immutable preview.10 after parent actual-pixel review.
Preview.10 and its public bytes are not rebuilt or replaced. The website
continues to offer preview.9 until separate owner acceptance/promotion.

The new package uses the existing Inno wizard and embeds both genuine,
same-run Release directories, not nested installers. `ProcessorArchitecture`
reports the **native Windows OS** architecture; Inno uses
`IsWow64Process2`'s native machine (with `GetNativeSystemInfo` fallback).
`paX64` and `paArm64` are exclusive file checks; `arm64 or x64os` rejects
32-bit/unsupported Windows before installing. `x64compatible` must not
select a universal payload because it includes ARM Windows x64 emulation.
The compiler must be observed as Inno 6.3 or newer; its exact version is
recorded in the package manifest. The gate logs executable version metadata
before running an `Output=no` compile-only probe. It requires a single
authoritative compiler-engine banner and successful architecture-syntax
compilation; missing/old engine evidence fails closed. ISCC executable
resource metadata alone is not the compiler-engine version.
CI product-resource authority accepts only trailing ASCII-space padding
after the two exact known product/isolated-fixture names, never leading
whitespace or another name. Owned Cancel/confirmation clicks are posted
nonblocking because Inno opens a modal exit question. Native proof writes
per-stage PID/exit/dialog/invocation receipts before and after dispatch and
bounded install/uninstall/corruption/cleanup waits; a timeout fails, not passes.

Tradeoff: one larger download carries both native payloads; measure the
compiled byte count rather than promising a size. No runtime payload fetch,
retry, network host, temporary bootstrap installer or ARM fallback is added.
Installation is offline once downloaded; sign-in/sync still require a
connection. Secondary per-architecture assets remain support options.
Existing per-user `PrivilegesRequired=lowest` and `runasoriginaluser` remain.
No signing capability is added: a new package hash has its own reputation,
and unknown-publisher/reputation warnings can remain. It does not newly
require admin/UAC elevation; do not elevate to bypass a warning. Checksums
establish consistency, not signing or safety.

Before compilation, each Release tree must match the same-run source/version,
native EXE/DLL machine types, required Flutter assets and `data/app.so` AOT
payload, exact inventory and
SHA-256 hashes. Missing/corrupt/debug/fixture inputs fail; no
`skipifsourcedoesntexist` or disabled embedded checksum is permitted.
The manifest plus trusted same-run Actions artifact provenance establishes
the input chain; PE structure alone is not proof that arbitrary bytes are a
genuine build.

CI universal proof uses disposable actual x64 and ARM64 runners and a native
MSVC-built x64 console process (not managed PE metadata or a CLR that may
run natively on ARM), with a source/hash-pinned separate test artifact.
That process queries native architecture on ARM with `IsWow64Process2`, and
actual process architecture with `GetProcessInformation(ProcessMachineTypeInfo)`.
The former API's process-machine output classifies WOW64 and can be zero for
x64 emulation; zero must not be interpreted as native ARM execution. Keep it
separately labeled in receipts. The probe requires native AMD64 machine code
and excludes managed/ARM64EC builds. Its source is LF-pinned so producer and
consumer hashes agree across runner Git configurations. Lifecycle proof covers
owned-window Cancel before
payload, actual selected installed PE/all-file hash/inventory readback,
silent/default-off zero receipt, and owned uninstall. A separate isolated
AppId checksum fixture contains genuine release payloads plus one
uncompressed marker; exactly one marker byte is changed in a copy. A checksum
failure must roll back the payload and leave observations absent. This is
fault-injection evidence, not a corrupted public release or customer trial.
Unsupported/32-bit hosts have contract coverage, not real hardware proof.
Keyboard/Narrator and ordinary sign-in/customer launch acceptance are not
inferred from these checks.

The checksum oracle accepts only the actual Inno "The source file is
corrupted" / source hash-verification error, not path/header mentions of
corruption, checksum or CRC. The receipt retains sanitized specific error
lines and requires all target files, including the marker, absent. Owned
Welcome Cancel must return Inno's pre-install Cancel exit code 2; process
absence alone is not acceptance.

Independent genuine universal-app launch jobs on x64/ARM64 require the
same-source/hash-authorized product package and native payload, a real
non-elevated interactive installing token, default-checked Finish versus
explicit unchecked Finish, actual process count/owning-user SID/token
elevation and zero observations. Only disposable CI can run this proof;
no ordinary user/customer installation is authorized. The inert fixture
remains separate evidence. An elevated hosted worker fails **before**
installer start and cannot satisfy the genuine launch gate. No raw SIDs,
profile paths or user data are published in its sanitized receipt.
Both branches require actual wizard/launcher successful exit0. The checked
native process must still be alive at the end of the ten-second observation
window with a visible owned app window; a briefly sampled/crashed process is
not a pass. Ordinary sign-in and full journey still require owner acceptance.

The owner separately authorized an exact manual-test candidate on 7 October
2026, with genuine launch-after-Finish explicitly
UNVERIFIED. Exact-head API/x64/ARM64/customer-quality/universal-native gates
and parent review remain mandatory. Preview.11's tag-run native evidence
passed, but publication failed because the release validator expected an
array while PowerShell serialized the single exact checksum error as a
string. That tag stays immutable and unpublished. Parent authorized carrying
only this manual-trial exception to **exact recovery preview.12**, not a
general future waiver; preview.13 and later again require launch proof.
Publication verifies the selected tag-run package bytes, source/version,
payload manifests, both actual native lifecycle/frame receipts, and genuine
launch receipts bound to that SAME package SHA. The preview.12 exception
accepts only the known elevated interactive worker guard with zero modes,
not an arbitrary launch failure. Jobs remain visibly failed; no protection,
installer behavior or token guard changes. Same-source builds may have
different binary hashes; never mix push/PR/tag-run artifacts. Checksum receipt
normalization accepts one exact error string or a nonempty string array
containing only exact recognized errors; missing/malformed/unknown entries
or incorrect lifecycle exits still fail. An explicit failed-preview11 local
audit validates its original bytes/receipts without authorizing publication.

The GitHub prerelease is publicly accessible, not a private distribution.
It is intended only for the owner manual checklist, not recruitment or
customer-ready acceptance. Keep preview.10 immutable and the public pointer
on preview.9. Only separately accepted checked/unchecked launch and ordinary
sign-in/full journey can authorize promoting these SAME verified bytes.

Owner checklist: fresh public package/source/checksum readback; native x64
and ARM64 install (including emulated setup process); Welcome/recipe/garden
education and Back/Cancel; optional observations unchecked with zero receipt;
checked Finish exactly one non-elevated app as the installing user; unchecked
Finish zero app; ordinary sign-in and full garden journey; offline installation
and explicit unsupported/corrupt stop. Keep the public pointer on preview.9
and no external recruitment until separate owner acceptance. Promote the
same verified immutable bytes if accepted, not a rebuild.

The site supports an optional verified `release.universal` URL/SHA-256 entry.
Without it current preview.9 rendering is unchanged. With it the static,
no-JS primary link is "Download Bloomstep for Windows", with secondary
architecture links collapsed. Browser CPU hints are not queried in that mode;
its click uses the existing `unknown` architecture category without changing
telemetry or consent. No invented candidate checksum is committed.

## Behaviour (contract before implementation)

- Teach one routine-linked tiny action and a personal celebration using original
  Bloomstep wording and illustrations, not book text, cover art or third-party
  logos. Describe Bloomstep as an independent app inspired by the Tiny Habits
  method, not affiliated with or endorsed by BJ Fogg or Tiny Habits. Link only
  the official learning pages `https://tinyhabits.com` and
  `https://tinyhabits.com/book/`; learning is optional, never an install gate.
- Keep branded Welcome as **Your garden starts with one seed**, followed by
  **A tiny recipe** and **Watch it become a garden**, then directory, existing
  unchecked observations, Ready, progress and Finish. The three educational
  beats are guaranteed for interactive setup; silent setup skips them. Explicit
  destination selection is not skipped on upgrades; the previous directory is
  prefilled and visibly reviewed, preserving custom install locations. The
  isolated fixture never reuses a previous path. The optional Start Menu-folder page is omitted (existing shortcut
  creation remains). No quizzes, tracking,
  autoplay or required external navigation. Keep per-user/no-elevation setup,
  silent/default-off receipts, ownership, protocol and sign-in gates unchanged.
- Use original, deterministic bitmap art in native wizard chrome. Compiler
  inputs are explicit and required, never wildcard/skip-if-missing educational
  assets. Text is the complete teaching alternative; art conveys no exclusive
  information. Respect native fonts/system colors and scaled layout.
- Customer teaching and download help are static HTML: readable without JS,
  API, sign-in, consent or third-party calls. Existing production theme tokens
  are used. No new storage, tracker, auth, tenant or test-auth changes.
- Browser help distinguishes Edge and Chrome on Windows. Ctrl+J and
  the browser's Downloads view are navigation, not permission to override a
  warning. Browser versions and managed policies vary. The user-provided
  preview.8 warnings are historical observations, not universal behavior or CI
  captures. Never use a benign view as a warning fallback. Flow art is labeled illustrative.
- Before any SmartScreen continuation: source, exact asset/architecture and
  release SHA-256 check; a hash establishes file consistency, not trust,
  signing or safety. Unknown, unexpected, malware, policy or verification
  failure means stop/cancel, not disable protection, unblock globally or run
  as administrator. Preserve conditional More info / Run anyway guidance only
  for the unsigned-app reputation prompt when policy permits.

Exact limited-scope text on the customer landing and releases paths:

> Limited preview — Bloomstep is an early, unsigned Windows app for trying tiny, routine-linked habits, check-ins, and a personal growing garden. Sign-in is required; some features and sign-in options are still being refined. This is not the complete verified MVP, and it is not medical advice. There is no Microsoft Store version yet. If you use the app, private feedback is available in-app after sign-in.

No controller, privacy contact, legal basis or processor/backup retention is
invented. Existing disclosed retention and TODOs remain. No tester count,
eligibility, support SLA or invitations to join a cohort are added.

## Edge / error matrix

| Surface / situation | Required result and verification |
| --- | --- |
| Site home, releases, invitation query | Same limited preview boundary; native invitations remain explicit, no new recruitment or auth path |
| Book/method navigation | Official HTTPS destinations, independence statement; no mandatory navigation or third-party embed |
| JS disabled / API unavailable | Teaching, native details controls, architecture downloads, checksums and safety help still usable |
| Edge / Chrome, blocked download | Browser-specific Downloads navigation; stop on unresolved warnings or managed policy; no blanket bypass |
| SmartScreen reputation vs malware/policy block | Conditional existing unsigned-prompt guidance only; stop otherwise; no claim that a hash proves safety |
| Wrong/unknown architecture | Manual Windows System type guidance and both current preview.9 choices; warning observations remain preview.8 |
| Missing or corrupt bitmap | Strict build failure before distribution; no unchecked runtime extraction |
| Art unavailable / high contrast | Complete text alternative; no meaning or control expressed by color/art alone |
| Keyboard, dark/light, 320px, 200% scale | Visible focus, semantic headings/alt, wrapping and no horizontal scroll; system colors in forced-colors |
| Reduced motion / no interaction | Static original art; no animation, audio, autoplay, quiz or decorative clickable controls |
| Wizard welcome / recipe / grow / directory / observations / ready / progress / finish | Three original illustrated beats before options, native Back/Next/Cancel/Install navigation, freely toggleable Finish launch |
| Wizard observations / silent upgrade | Existing separate unchecked consent and error notification; silent does not collect or inherit ownership |
| Cancel before install | No installation or receipt side effect from educational content; viewing art never uploads |
| Fixture compile / visual inspection | Compile real Inno installer with inert fixture payload, inspect UI then cancel before install; no customer install/data/elevation |
| CI / PR | Source validation and dual-architecture CI evidence; no tag, release publication or customer acceptance inferred |

## Source and evidence

`site/assets/habit-*.svg` and `site/assets/download-flow.svg` are original static
vector artwork. `tool/generate_installer_art.mjs` deterministically generates
`packaging/assets/wizard-*.bmp`; `--check` verifies exact committed bytes.
Native wizard art is compiled into the installer, not copied into customer data.
Source-contract tests cover safety wording, packaging, navigation and consent;
browser checks cover rendering/fallback. Compiling and viewing a canceled
fixture wizard does not prove a customer installation, Narrator acceptance,
Windows warning occurrence, production identity, or clinical outcomes.

Actual `edge-downloads.png` and `chrome-downloads.png` show their own native
Downloads views, not a mockup or generic Chromium substitute. Visible captions
and `download-capture-provenance.json` identify actual products/versions,
capture date, benign loopback text sample and no observed installer warning.
The source tool uses fresh profiles, never opens the sample and never overrides
security. Chrome's generic organization-managed banner is left unmodified.
Validated official Microsoft SmartScreen and Chrome warning articles are linked
only as external help; advice to disable protection is not reproduced.

Firefox 155 was restored into an isolated session-state Playwright cache, not
installed as a system browser. Its native `about:downloads` navigation timed
out on two bounded attempts (load: 30s; commit: 10s). No Firefox screenshot,
specific control, warning or visual validation is claimed. Generic other-browser
Downloads navigation and completed-file verification remain. This is an
explicit optional-third-browser capture gap, not complete browser coverage.

The `OnboardingFixture` define uses a distinct fixture AppId, ignores previous
installation paths, and returns a nonempty `PrepareToInstall` error before
installation. Neither Install nor Finish is clicked during capture. Ordinary
CI compiles never supply that define and inspect full preprocessed source to
reject fixture identity/guard leakage. Captures use physical per-monitor DPI
coordinates. Historical baseline Welcome, directory, consent, Start Menu and
Ready views at a host's 150% scale were canceled without creating a target;
that is not evidence for the redesigned candidate. Exact-head actual 100% and
one high-DPI capture remain the frozen-v1 review requirement. Exhaustive DPI
and Narrator acceptance remain Store-readiness work, not inferred from names.
The updated source candidate makes the native **Launch Bloomstep and plant your
first habit** Finish choice checked by default and freely user-toggleable.
Launch is allowed only after successful interactive file installation on a
visible desktop, without administrator elevation, explicit unattended flags or
a prior launch attempt. Silent, failed and canceled setup cannot launch.
`runasoriginaluser` preserves installing-user credentials; it is not used as a
workaround for an elevated start. The elevated Finish instead explains how to
open the app normally. Product and installer observations remain separately
unchecked/default-off, with no retrospective educational events.

`tool/verify_installer_journey.ps1` is restricted to a named inert CI fixture,
with a distinct AppId and no protocol registry writes. Its probe reports only
launch count/token checks in sanitized artifacts; raw token information stays
in the disposable target and is deleted. That fixture is not Bloomstep and
does not prove ordinary app launch, provider sign-in or first-recipe acceptance.
Limited-task failures retain task state/result and a sanitized worker stage,
error type/line, session ID, interactive flag and elevation flag. These are
diagnostics, not proof of an available GUI or successful launch; missing worker
or outcome records remain failures. Names, SIDs and exception messages are not
included in the public diagnostic records.
The compile-only capture still never selects Install or Finish. Actual OS DPI
is recorded; missing 100/150/200-percent pixels and screen-reader acceptance
remain explicit coverage gaps until observed, never substituted with font or
wizard-size scaling.

The three visual beats are **Your garden starts with one seed**, **A tiny
recipe**, and **Watch it become a garden**, with native progress/text
equivalents. `tool/installer_art_export_test.dart` exports original full-panel
illustrations from the existing five-stage `PlantArt` renderer and original
recipe icons; these are authored artwork, not screenshots or evidence of a
customer garden. To re-author, set `BLOOMSTEP_EXPORT_INSTALLER_ART=true` and run
`flutter test --no-pub tool/installer_art_export_test.dart`; the exporter writes
source/asset SHA-256 provenance (authored text source is normalized to UTF-8/LF
for cross-platform checkout; bitmap bytes are hashed unchanged). This does not
change the raw source/image hashes of the genuine customer warnings.
`node tool/generate_installer_art.mjs --check`
rejects changed source or illustration bytes until explicitly re-exported.
Ready and Finish use a garden hero; Ready attribution/limitations remain
available behind the native **Preview details** button rather than a default
text wall.

Compile-only capture requires the CI source/hash manifest, distinct fixture
AppId and unconditional installation prohibition before launching the fixture.
It never selects Install or Finish, runs an app payload, or writes protocols.
Actual window DPI is recorded. A separately approved local capture may use the
same bounded exact-head fixture at the already configured OS DPI; it must not
change display/security settings or use unrelated desktop imagery.

Browser-specific panels are collapsed native `details` controls in the actual
default page. Render evidence separates `home-default` from
`home-help-expanded`; expanded screenshots are intentional inspection states,
not the default user journey. Both states are checked for narrow-page reflow.

## Genuine customer warning walkthrough

`site/assets/customer-warning-provenance.json` is the public source of truth for
the five user-authorized preview.8 ARM64 images, original/transformed hashes,
pixel crops and the single non-warning background redaction. Private originals
and personal paths are not published. `tool/prepare_customer_warnings.py`
validates all five exact source hashes before pixel-only lossless transformation:
no scaling, metadata, reconstruction or inferred warning pixels.

The Edge profile toolbar/face and unrelated document background are excluded,
while the complete Keep anyway button and original setup filename (including
the displayed `(1)` duplicate-download suffix) remain. Windows outside-dialog
edges are cropped. Every visible caption says real customer-provided screenshot,
not CI; browser/OS versions are unknown. Screenshots do not establish binary
SHA-256, execution success, app acceptance, safety or universal warning behavior.
They replace the benign Edge TXT view in the warning walkthrough; Chrome's
separate benign history sample remains accurately labeled, not a warning fallback.
Ordinary PR CI no longer triggers a new public-installer warning observation.
Only the separately authorized explicit workflow-dispatch gate can run that tool.

The three-beat/launch changes are **source candidate only**. The owner has
authorized preview.10 after reviewed source merge and mandatory exact-SHA
API/x64/ARM64/customer-quality gates using the existing release path; the new
pipeline is deferred until after frozen v1. The separate launch-evidence job
remains visibly failing when proof fails, with no `continue-on-error` or
success-shaped skip. Only the exact preview.10 tag has an owner-trial release
exception; later releases again require blocking launch evidence.

**launch-after-install: not yet verified, pending owner manual trial**

Preview.10 is **owner trial only**, publicly accessible on GitHub rather than
private. The public site remains on preview.9 and no external recruitment is
authorized until the owner reports both checked Finish (exactly one
non-elevated app as installing user) and unchecked Finish (no launch) passing.
Sign-in still precedes the builder. Either failure is a P0 frozen-v1 fix in the
next preview. This exception ends after M1; before M2/open preview/Store,
blocking automated or recorded clean-machine human launch proof is required
again. Public installer bytes must be freshly downloaded and hash-verified
before any later authorized site pointer promotion.

Website-only changes deploy without a preview version bump. Historical
preview.8 screenshots remain labeled preview.8; they are not preview.9/10
warning observations. No release or new tag has been created by this increment.
The primary three-step picker and post-plant next-step source are included in
frozen v1; source/widget tests do not replace signed-in customer acceptance.
Further guided polish/support and private first-created metrics remain
dependent follow-ups, not completed by this increment.
