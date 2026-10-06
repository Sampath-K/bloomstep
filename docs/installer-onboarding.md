# Installer and customer onboarding contract

Authorized source increment from main `30fd380194bed46686c5483accfa71ff06c9f068`.
This is not a release authorization. Keep preview.8 downloads and checksums;
preview.9 tagging/publication and public recruitment/promotion remain held.

## Behaviour (contract before implementation)

- Teach one routine-linked tiny action and a personal celebration using original
  Bloomstep wording and illustrations, not book text, cover art or third-party
  logos. Describe Bloomstep as an independent app inspired by the Tiny Habits
  method, not affiliated with or endorsed by BJ Fogg or Tiny Habits. Link only
  the official learning pages `https://tinyhabits.com` and
  `https://tinyhabits.com/book/`; learning is optional, never an install gate.
- Reuse native installer steps (directory, existing optional observations,
  ready, progress, finish). Add no custom educational pages, quizzes, tracking,
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
| Wrong/unknown architecture | Manual Windows System type guidance and both unchanged preview.8 choices |
| Missing or corrupt bitmap | Strict build failure before distribution; no unchecked runtime extraction |
| Art unavailable / high contrast | Complete text alternative; no meaning or control expressed by color/art alone |
| Keyboard, dark/light, 320px, 200% scale | Visible focus, semantic headings/alt, wrapping and no horizontal scroll; system colors in forced-colors |
| Reduced motion / no interaction | Static original art; no animation, audio, autoplay, quiz or decorative clickable controls |
| Wizard directory / ready / progress / finish | Native back/cancel/install navigation, concise ready teaching, optional finish launch; no extra educational step |
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
coordinates; native directory, consent, Start Menu and Ready steps were viewed
at the host's 150% scale and canceled. No target directory was created.
Progress/Finish remain source/compile evidence only: post-install launch is
explicitly `unchecked`, not visually exercised by installing a fixture.
