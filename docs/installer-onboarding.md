# Installer and customer onboarding contract

## WITHDRAWN: Defender-blocked private candidate

On 9 October 2026 Windows Defender reported the severe threat
`Behavior:Win32/DefenseEvasion.A!ml` and successfully quarantined private
zero-click candidate SHA-256
`b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5`
from source `3cd29f0b635e5fdce2a2f9ade939024416216401`, artifact
`11568545878` in run `37815203643`.

**Do not download, restore, distribute, or run this candidate.** This is a
malware/behavior detection, not an unknown-reputation warning. Do not use
Keep anyway, Run anyway, exclusions, protection changes, or quarantine
restoration. It is not established as a false positive.

Defender attributed events to an Inno temporary installer process before
quarantine; partial-install state is unknown. The presence of an existing
installed executable/protocol is not evidence that the attempted installation
completed. Preserve existing customer installation and data; no cleanup,
uninstall, or retry on that machine is authorized by this incident.

Earlier installation-only CI and hash consistency do not establish a clean
security outcome. The historical hosted security gate failed closed because
real-time and behavior protection were unavailable (run `37859130228`, receipt
`11585685771`). That workflow is now retired and explicitly refuses further
withdrawn-binary access; historical source/receipts are retained. The new standard
candidate's VM gate verifies enabled protection and exact hashes, preserving
versions, scan outcomes and detections. Missing protection or detections fail closed.
Even a clean static scan does not override the observed local behavior
quarantine or establish non-elevated launch acceptance. No vendor sample
submission or third-party binary upload is authorized.

## Active native one-click correction (unpublished, not security accepted)

The owner rejected extra Next screens in the conventional baseline. The corrected
source shows one visible native **Ready** page with the same branded value-prop
art and **Install**, uses the default per-user location (existing installs retain
their folder), then progress and Finish. **Launch Bloomstep** is **checked by
default** on Finish and the user can freely untick it before selecting Finish.
No destination choice is required; standard settings disable Welcome, directory
and program-group pages and the Ready memo. Cancel remains native.
There are no timer callbacks,
automatic page advances/clicks, hidden/minimized windows, artificial holds or
custom message pumps. Original Anchor/Action/Celebrate artwork remains static.
The source continues per-user `PrivilegesRequired=lowest`, offline native
architecture routing and absent/zero installer observations. Checked launch is
withheld for silent, elevated, suppressed or non-interactive contexts.

This is a legitimate design change, **not an established Defender remediation**.
The possible link between zero-click behavior and detection remains an untested
hypothesis. The new build is CI-only and unpublished. Old candidate withdrawal
remains in force; no owner-machine execution, merge, release/tag or site promotion.

Launch-after-install and genuine-app evidence require the protected disposable
standard-user interactive VM runner labelled `defender-interactive`. Until the
owner supplies it, those jobs remain queued, not passing. See
[owner VM preparation, runner registration and teardown](defender-test-vm.md).
Hosted workers compile only; installer execution, native screenshots, lifecycle
and privacy proofs are explicitly withheld there and routed to the protected VM.

### Owner-reported clean baseline, not replacement acceptance

The owner reported running exact baseline source
`922da673552c3a6534d1a563d1e23521aff17e65` installer SHA-256
`0ef50e8f261adc55eaa05cd28c9a5368af6be859411e9b8a98feaf46902c1db8`
on their ARM64 machine: installation succeeded with Defender real-time and
behavior protection enabled and no detections in the preceding hour.
This is one owner-reported host observation, not independently inspected event
receipts, protected-VM acceptance, provider/full-journey or launch-token proof.
It does not transfer to the new one-click bytes or invalidate the older
zero-click withdrawal. No agent retry on that machine was performed.

PR28's six app commits through
`2753a6203f97923557f2de669c5f66cd3fdf70a6`, plus the rendered custom-field
label/value overlap correction at exact PR28 head
`adb51b30da43e0629efd5ee6db5b0d545f625150`, are composed into this branch.
The final source includes the seven app commits in order:
`cfa46b75`, `298735c7`, `625ec537`, `67f1bf17`, `dd959648`, `2753a620`,
`adb51b30`.
inline profile/device garden, once-only first-run habit-builder invitation,
custom text on all three steps, and post-save seed growth with reduced motion.
The composed executable still needs exact-head native evidence; source
composition does not establish genuine launch or account acceptance.

## Historical autonomous designs (superseded; not instructions)

User-directed after testing: the setup steps that each required Next were not
interesting and had too much text. Both variants below build from the same
source (`/DInstallFlow=oneclick` default, `/DInstallFlow=zeroclick` experiment).
No release, tag, signing, site promotion or merge is authorized by this work.

**One picture, three words.** One original visual (exported from the app's own
`PlantArt`, see `education-art-provenance.json`) shows a cup (anchor), a sprout
(action) and a smile (celebrate) with the native words **Anchor**, **Action**
and **Celebrate** as the only text, then a plant growing through five stages and
a garden of five blooms (more anchors, more habits, a bigger garden). The words
are real native labels so screen readers announce them; the pictures carry no
baked-in text.

**One-click (default).** The visual shows for 4 seconds with only Cancel, then
moves on by itself to the destination page (per-user default, Browse). **Install**
is the only click. There is no Ready page, no Finish page and no launch
checkbox. After a successful interactive install Setup closes and opens
Bloomstep as the original, non-elevated installing user (`ExecAsOriginalUser`).

**Zero-click (private experiment).** Double-clicking the installer shows the
same visual while installing to the default per-user folder with no pages and
no clicks; the visual is held until about 5 seconds have passed (a requested
brand hold, not install work), then Bloomstep opens. Upgrades reuse the
previous folder. Interactive Inno Setup always shows one pre-install page; the
zero-click build puts the same visual on it and advances on the first timer
tick without a click, so the generic Inno welcome text never appears.

Historical behavior and limitations (the standard redesign above is authoritative):

- SmartScreen and Mark-of-the-Web: an unsigned download from the internet still
  shows "Windows protected your PC" (More info, then Run anyway only for the
  exact verified file). This is not bypassed and signing is deferred.
- no UAC: setup is per-user with `PrivilegesRequired=lowest`; it never asks for
  elevation. If someone runs it as administrator anyway, the app is not opened
  elevated; a message asks them to open Bloomstep from the Start menu.
- Error, disk, close-running-app and cancel dialogs stay visible and actionable.
  Silent installs never open the app.

**Reduced motion.** With Windows animations off the picture is held still; the
4-second auto-advance and 5-second hold still apply. A subtle drift is the only
motion when animations are on.

**Options moved out of setup.** The launch checkbox is gone because the app now
always opens after an interactive install. Settings already has
"launch at Windows sign-in"; setup never had shortcut or analytics choices, and
no new default-on collection is added. Installer observations stay disabled.

**First launch in the app (code evidence only).** A fresh user lands on the
empty garden ("Your garden is ready to grow") whose primary action is
**Plant a habit**; returning users keep their per-account garden. This is from
app code and tests, not an installed-app observation; a separate session owns
the sign-in/profile change on that screen.

**Evidence and honest gaps.** Disposable CI captures the actual compiled
welcome, destination, installing frames, timings, DPI and installer SHA-256 for
both variants. Hosted CI runners are elevated, so automatic launch is
withheld there by design: genuine non-elevated automatic launch is UNVERIFIED.
144 DPI is uncovered unless actually observed. x64 hosted runners report the
static (reduced-motion) preference, which is not motion evidence.

## Earlier destination-first source increment (superseded)

User-directed follow-up after immutable preview.12: destination/Browse is the
only preinstall decision, retaining the per-user default and upgrade location.
The native button is explicitly **Install**, not Next. Welcome, teaching,
observations and Ready pages are removed. Existing authored seed/recipe/garden
BMPs move to real installing progress with a native `CreateCallback`/`SetTimer`
callback and a small bounded drift. Following actual1.5-2.1second installations,
parent-directed cadence is600ms: seed, recipe, then garden at1200ms, retaining
the last panel rather than repeatedly cycling. It runs only while installing,
never delays completion, and does not guarantee all panels on faster installs.
These brief visual transitions are not a guarantee that users read every caption.
Windows reduced-motion continues to keep scene0 static, not rapidly swap scenes.
CI's exact Inno6.7.1 `CreateCallback` returns `LongWord` (32-bit setup callback
address), not the `NativeInt` used by newer online help. The declaration is
bound to that engine's supported signature on both native OS hosts.
Inno's actual progress bar remains authoritative; scenes are not progress percentages.
There is no sleep, minimum dwell, network host, WebView or added dependency.
Windows `SPI_GETCLIENTAREAANIMATION` is queried read-only; disabled or unavailable
preferences produce static art. Page changes, completion, modal interruptions
and setup disposal stop the callback. Finish says **Bloomstep is ready** and
**Open Bloomstep to create your first tiny habit**; existing successful,
interactive, non-elevated checked/unchecked/silent launch guards are unchanged.

Installer observations are **disabled**, including silent installs: no prompt,
receipt/event/UUID generation, owner marker or replacement consent. Upgrade
still removes an old owner marker, never adopts its consent, and preserves
unmatched existing legacy receipts. Legacy uninstall still removes only receipts
and `.pending` files whose first event matches that installation's owner marker.
An unmatched old receipt remains subject to the existing app's seven-day
next-access expiry/privacy controls; app-side compatibility and separate consent
flows are not changed.

Contract RED evidence precedes implementation. Disposable CI records exact
package/source hashes, actual destination/Cancel, timed real-install frames,
Finish, timer disposal and bounded owned-process stage/exit state. It records
actual DPI and missing coverage rather than labeling enlarged/static source art
as high-DPI motion proof. Fast installs may legitimately show fewer scenes;
three-scene/reduced-motion/high-DPI evidence and parent pixel review remain
mandatory before merge, not inferred from a green capture script. Genuine
non-elevated checked/unchecked launch/full journey acceptance remains pending.
Receipts distinguish `seed-to-flower`, `routine-action-celebration` and
`growing-garden`: different committed artwork hashes, actual native captions,
captured PNG hashes and first-observed transition timestamps. Missing scenes
are explicitly listed; timer logs distinguish initialization from installing.
Exact PR run37627423101 reached Finish in1526ms (x64 static preference) and
2104ms (ARM64 motion preference), both at96DPI. Only scene0 was visible;
scene1/2 transitions and144DPI remain absent in that earlier3000ms-cadence run.
New600ms source needs its own actual compiled evidence. These fast installs are not slowed
to obtain screenshots. This passing lifecycle capture is not full pixel approval.
The website promotion belongs to a separate PR. Preview.12's bytes/tag are
unchanged; this source increment does not authorize a new public release.

References: [Inno last-page Install caption](https://jrsoftware.org/ishelp/topic_setup_disablereadypage.htm),
[supported native timer callback](https://jrsoftware.org/ishelp/topic_isxfunc_createcallback.htm),
[supported native controls](https://jrsoftware.org/ishelp/topic_scriptclasses.htm),
[Windows animation preference](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow).
Microsoft's [billboard](https://learn.microsoft.com/en-us/windows/win32/msi/billboard-control)
and [progress UX](https://learn.microsoft.com/en-us/windows/win32/uxguide/progress-bars)
(Windows 7-era guidance) are pattern references only, not a new MSI dependency
or accessibility certification.

The sections below describe earlier iterations and publication boundaries.

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
