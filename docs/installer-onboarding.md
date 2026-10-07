# Installer and customer onboarding contract

Authorized source increment from main `30fd380194bed46686c5483accfa71ff06c9f068`.
The original source increment did not authorize a release. On 7 October 2026,
the owner separately authorized website promotion of the already published
preview.9 and standing quality-gated immutable preview releases for subsequent
app/installer merges. Existing preview.8/preview.9 binaries remain immutable.
PR review and a reviewed operational release-pipeline dependency still gate
this source candidate; no new release has been published by this increment.
The separate website-only preview.9 promotion did not itself authorize app
changes or release/tag mutation. The preview.8 warning/capture evidence below
remains historical and must not be relabeled as preview.9.

## Behaviour (contract before implementation)

- Teach one routine-linked tiny action and a personal celebration using original
  Bloomstep wording and illustrations, not book text, cover art or third-party
  logos. Describe Bloomstep as an independent app inspired by the Tiny Habits
  method, not affiliated with or endorsed by BJ Fogg or Tiny Habits. Link only
  the official learning pages `https://tinyhabits.com` and
  `https://tinyhabits.com/book/`; learning is optional, never an install gate.
- Keep the standard branded Welcome as **Anchor a routine**, followed by
  **Plant a tiny recipe** and **Celebrate and grow**, then directory, existing
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
  warning. Browser versions and managed policies vary. No claimed observed
  warning or fake screenshot. Any flow art is labeled illustrative.
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
| Wrong/unknown architecture | Manual Windows System type guidance and both preview.9 choices |
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
coordinates; native Welcome, directory, consent, Start Menu and Ready steps were viewed
at the host's 150% scale and canceled. No target directory was created.
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
The compile-only capture still never selects Install or Finish. Actual OS DPI
is recorded; missing 100/150/200-percent pixels and screen-reader acceptance
remain explicit coverage gaps until observed, never substituted with font or
wizard-size scaling.

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
authorized the next immutable preview.10 after this app/installer change
merges, subject to exact-SHA quality gates, parent visual review before merge,
and the separately reviewed release pipeline. Published installers must be
downloaded again and hash-verified before any newest-download site pointer.
Website-only changes deploy without a preview version bump. Historical
preview.8 screenshots remain labeled preview.8; they are not preview.9/10
warning observations. No release or new tag has been created by this increment.
App guided creation/support and private first-created metrics are dependent
follow-ups, not completed by this installer/site layer.
