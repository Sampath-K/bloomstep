# Garden visual quality review

**Status: reviewable source work, not release/native-quality acceptance.**
This is an expert heuristic review, not a user study, retention improvement,
GrowthBook result or Store certification. Target: **>=4 in every applicable
dimension**, no compensating mean, no critical accessibility/privacy/task defect.
The current matrix still has open gates; documenting the bar does not meet it.

## Source and evidence

Base: `a778a66` (preview14 pointers remain unchanged). The separate experiment
foundation was imported from `c1cf69b` as `dcb6898`, followed by official SDK
replacement `de90e7b` as `51915de`. The selected provider is GrowthBook through a
replaceable resolver, default off. Only the narrow test-clock portion of PR48
`d8909a4` was composed as `bd368c9`; its continuity UI/status claims were not
imported. The visual source uses
only resolve/rendered/outcome hooks, not SDK types. Hosted setup, approved study
configuration and real outcomes are not demonstrated.

The canonical rubric and mandatory per-change checklist are in
[product-spec.md](product-spec.md#human-centered-garden-design-and-validation).
The machine-readable per-surface source of truth is
[visual-quality-scorecard.json](visual-quality-scorecard.json), checked by
`test/visual_quality_contract_test.dart`: required dimensions, anchored range,
existing rendered evidence, explicit unknowns/open gates and no unreviewed
score regression. This checks record integrity, **not the truth of a heuristic
score or accessibility certification**. Each row records
`PASS_OBSERVED_SCOPE` or `NOT_OBSERVED`; passing declared widget checks does not
close its sub-target or native gates.

Images in [`evidence/visual-quality`](evidence/visual-quality) are actual Flutter
widget raster output from Windows, Segoe UI/Material icons, labelled synthetic
data, disposable SQLite gardens and mock HTTPS/platform bridges. They are not
Figma/mockups or installed-app screenshots. Account presentation is synthetic,
not a real signed-in customer. No email, invite, OS Share panel, permission,
destructive action, publication or release was performed.

`before-chrome-*.png` show the initial `a778a66` chrome. The three
`before-surface-*.png` preserve the existing Settings/form content before their
hierarchy/semantic refinements (with the new surrounding chrome already present).
The old outbound dialog was source-reviewed but not captured before replacement:
its **before numeric grade is NOT OBSERVED**, not a manufactured comparison.

## Measurable changes and checks

| Surface/change | Concrete contract and evidence type |
|---|---|
| Invitation ready | One filled primary action; original paired plants; concise privacy boundary always visible; optional methods/card/details expand. Zero server/transport calls on open/dismiss. Actual rendered and functional widget evidence. |
| Invitation recipe | Existing exact-field/category approval retained; no dead empty picker; shared-text consequence stays visible when approved; removal/change invalidates receipt. Synthetic full approval/removal journey. |
| Pending/error/receipt | Duplicate gestures disabled; Close/Escape remain usable while pending; no disposed update or late transport after close. Failed HTTP/clipboard yields no success URL/receipt. Cached/fresh/expiry details remain distinct. |
| Share methods | Exact channel-attributed server URL goes to mock clipboard/native bridge and real QR renderer. Composer/panel **requested**, never called sent/delivered. Actual email/Share recipients and delivery NOT OBSERVED. |
| Chrome | Original garden scenery, static equivalent for both motion settings; one finite 700ms entrance, no repeating ticker; compact <=300px image+label Plant action. Populated desktop scenery is compact and the first Did it remains hit-testable at 1100x900. Device/account empty/populated source layouts rendered. |
| Forms/confirmation | Scrollable feedback/destructive disclosure at 640x480/200%; named feedback type, question-associated naturalness sliders and spoken rating values. Cancel leaves synthetic data intact. |
| Settings | Named motion/privacy/reminder/data sections; essential collection/revocation consequences visible beside choice; secondary technical scope expandable. Existing consent logic and Settings entry points preserved. |
| Experiment seam | Default control headings; actual-render callback and typed outcomes only. No collection without the shared consent/config contract, no custom UI bucketing. Useful saved practice is the primary proposed outcome, not invitation volume. |

Contract-first red checks were observed before the relevant implementation:
missing two-plant/one-primary invitation contract; missing canopy/compact CTA;
missing question semantics; missing Settings hierarchy; missing scorecard file.
The new cache regression also revealed unstable disclosure state during async
prefix changes: keyed controls now retain expansion/focus state. A rendered
focused dark primary label failed the widget contrast guideline at regular
weight. The stronger label now preserves the actual Segoe UI text theme and
passes the light/dark widget contrast check. Final image inspection caught the
initial weight-only override losing that typeface; a failing font-family
regression now guards it. The original plant/check-in/undo test also exposed
practice being displaced by tall scenery; compact populated scenery and an
initial-viewport hit test guard that regression. Native high contrast remains
a separate gate.

Reproduce synthetic renders without contacting a real server:

```powershell
$env:BLOOMSTEP_SCREENSHOTS = '<new-private-output-directory>'
flutter test --no-pub --dart-define=BLOOMSTEP_TEST_BUILD=true test\garden_chrome_visual_test.dart test\invitation_widget_test.dart test\invitation_visual_test.dart test\recipe_builder_visual_test.dart test\surface_review_visual_test.dart
flutter test --no-pub test\visual_quality_contract_test.dart
flutter analyze --no-pub
```

The test-build define enables only existing test adapters in the test process,
not a shipping feature flag. `--no-pub` uses resolved dependencies: this host's
normal Flutter plugin setup reports a symlink/Developer Mode prerequisite.
No Windows setting was changed to bypass it.
For the existing loopback HTTP tests, restore the API's declared dependencies
and bundle only `site/customer.mjs` into ignored `site/assets/customer.js` using
the existing esbuild dependency. The full site build was deliberately not run:
it can rewrite published page pointers. No tracked site asset/pointer changed.

## Validation receipt and limits

Final synthetic matrix: **20 passing interaction/render tests**, including
light/dark, 200% text, short windows, finite/static motion, exact QR/platform
arguments and consent withdrawal. **108 current PNGs and seven baseline PNGs**
are committed here; all eight contact sheets were inspected, alongside
full-size invitation/chrome/short-window examples. These are actual Flutter
renders, not installed-app acceptance. Test logs and the exact clean source head
are bound in the PR receipt; screenshot counts do not establish quality.
The complete composed client suite passes **304 tests with one existing skip**;
Flutter analysis reports no issues. The suite was also run without screenshot
capture so image-encoding delays cannot conceal interaction timing failures.
QR completion waits for its rendered frame; subsequent actions wait for the
actual enabled control, not a success label that precedes persistence.

Both real local SQLite-to-loopback HTTP journeys pass after restoring their
existing prerequisites. The focused experiment API contracts pass (4 tests)
and API type checking passes. The attempted broad API suite ended with child
process `SIGTERM`/timeouts; it is **not claimed green** and must be rerun on a
stable host for broad API acceptance. No customer/cloud service was contacted.
The former date-sensitive reminder failure is addressed only by the imported
test-clock fix, with no production reminder policy change.

Native Windows compilation/installed observation is blocked by the host's
plugin symlink/Developer Mode prerequisite. Narrator, high contrast, Windows
snap/mixed DPI and device-measured performance are not observed. This bounded PR
is reviewable source/evidence, not a declaration that every >=4 target is met.

## Per-surface scorecard

Vectors are **D / H / G / A / T**, each out of 5: discoverability, hierarchy,
garden coherence/tone, accessibility/responsiveness, feedback/recovery/trust.
`N/O` means NOT OBSERVED, not zero. No score of 5 is awarded without independent
evidence. The detailed JSON ties each row to exact conditions, PNGs, checks and
gaps. All current rows remain open against the full Windows quality bar.

| Existing surface/state | Before -> current | Key assessment / remaining gate |
|---|---|---|
| Device empty garden | 4/3/2/3/4 -> 4/4/4/3/4 | Garden identity and compact action improved; native checks open. |
| Account populated garden | 4/3/3/3/4 -> 4/4/4/3/4 | Coherent shell; not a live account/PR48 composition. |
| Device populated, 200% | 3/3/2/3/4 -> 3/3/4/3/4 | No overflow; long profile precedes scenery and needs composed review. |
| Account empty, short/dark | 3/3/2/3/4 -> 4/4/4/3/4 | Persistent labelled action; native snap/DPI unknown. |
| Canopy motion/static | N/O -> 4/4/4/3/4 | Finite animation tested, not device frame timing. |
| Outbound invitation ready | N/O -> 4/4/4/3/4 | Clear primary, honest always-visible privacy. |
| Outbound pending/error | N/O -> 4/4/4/3/4 | Cancel/retry/late-result safety exercised synthetically. |
| Methods/QR/copied/cached | N/O -> 4/4/4/3/4 | Exact URL/bridge evidence, not delivery. |
| Empty recipe option | N/O -> 4/4/4/3/4 | Empty state is actionable without private fields. |
| Recipe/category/exact approval | N/O -> 4/3/3/3/4 | Safe explicit consent; category picker remains utilitarian. |
| Incoming invitation decision | N/O -> 4/3/3/3/4 | Accept/decline intact; explanatory block still dense. |
| Accepted cosmetic/card review | N/O -> 4/3/3/3/4 | No automatic planting; real mutual reward unverified. |
| First habit anchor/action/celebration | N/O -> 4/4/4/3/4 | Typed/suggested steps rendered through 200%; Narrator pending. |
| Edit recipe | N/O -> 4/3/3/3/4 | Functional familiar form; dense and narrower matrix. |
| Planted success/growth preview | N/O -> 4/4/4/3/4 | Honest future-growth illustration and next step. |
| Did it/rest reasons/undo | N/O -> 4/4/4/3/4 | Positive/autonomous; <300ms native budget unmeasured. |
| Weekly reflection/Recipe Doctor | N/O -> 4/3/3/3/4 | Clear choices, long text needs refinement. |
| Naturalness sliders | 4/3/3/2/4 -> 4/3/3/3/4 | Question/value semantics added; native reading order pending. |
| Settings/consent/export rows | 3/2/3/3/4 -> 4/3/3/3/4 | Sections improve orientation; detailed observation blocks still dense. |
| Recipe/local deletion confirmations | N/O -> 4/4/3/3/4 | Scrollable consequences and cancellation; no deletion performed. |
| Feedback/Rating composer | 4/3/3/2/4 -> 4/3/3/3/4 | Named controls/scrolling; no team submission or reply. |
| Empty My feedback | N/O -> 3/4/3/3/4 | Honest empty state; no direct compose action here. |
| Published releases empty | N/O -> 4/4/3/3/4 | Mock empty result; actual download/browser states unobserved. |
| Fourth-habit Start small | N/O -> 4/4/3/3/4 | Explicit autonomy, no limit silently imposed. |
| PR48 continuity/profile/new name/view/copy | N/O -> N/O | Separate branch `0a094e92`; exact combined source not rendered. |
| Native reminders/tray/startup/time pickers | N/O -> N/O | Source-inventoried, no OS permission/actions performed. |
| Native email/Share/file pickers/activation | N/O -> N/O | Mock adapter contracts cannot grade OS UI. |
| Optional measurement/sandbox settings | N/O -> N/O | Off rows visible; enrollment/receipt/config states not rendered. |
| Rare transient/error/graduation/rating prompts | N/O -> N/O | Source inventory only; exact state matrix is an open gate. |

## Complete source inventory and observation limits

The inventory follows `HabitHome`, `ProfileSection`, `GardenScreen` and
`RecipeBuilder` plus the optional settings widgets. Existing reachable surfaces:
device/account profile/sign-in/restore/sign-out/clear-saved-sign-in; first-run
builder/suggested/custom/edit/start-small/celebration; garden loading/empty/
active/graduated; practice/did-more/rest/undo/reconnect/paused-reminder states;
weekly Doctor/naturalness/cooldown/graduation/rating eligibility; outgoing
invite/channel/card/category/approval/receipt/error and incoming accept/decline/
shared-card/cosmetic/cache-warning states; feedback types/rating/composer/list/
queue/status/replies/own-record deletion; Settings motion/product events/
observation/measurement/sandbox/reminders/quiet times/snooze/startup/export/
update/local+server deletion/trust. Native handoffs include provider browser,
Share/email, JSON save/open, time picker, deep links, tray and notifications.

**Critical issues / exact remaining gates:** Native Narrator, Windows high
contrast, keyboard and focus across the entire app, snap/resizing and mixed-DPI
monitors are NOT OBSERVED. No accessibility certification is asserted. The
composed PR48 persistent device/account controls must be rendered and rescored
before integration acceptance. Dense unchanged reflection/approval/observation
surfaces have sub-target hierarchy scores, not a blanket "polished" pass.
Rare conditional states need dedicated rendered fixtures; no inferred grades.
Check-in feedback <300ms, cold start <2s and vector frame <16ms retain their
existing targets but have no device benchmark in this receipt.

## Windows capability map

| Capability | Implementation / observation status |
|---|---|
| Resizing, labelled navigation, primary action | Implemented; widget sizes 420x820/200%, 640x480 and desktop observed. Actual Windows snap and mixed-monitor DPI supported by host framework but unverified here. |
| Keyboard, focus, semantics | Invitation Escape/Enter/restore/duplicate guards and labelled controls observed in widget tests. Full native keyboard/IME/Narrator not observed. |
| Light/dark, text contrast | Existing semantic tokens reused; invitation contrast/named-target checks observed. Windows high-contrast integration/screen-reader perception not observed. |
| Reduced motion/micro-animation | App/OS media flag static alternatives + finite entrance observed synthetically. Device render latency unmeasured. |
| Native Share and email | Implemented explicit handoffs; mock bridge observed. Native target/composer/cancel/delivery not observed. |
| File save/open/export | Existing native APIs; source/contract coverage. Actual picker/permission/cancel on this source not observed. |
| Notification/tray/startup/quiet hours | Existing opt-in implementation; no permission changes made. Actual Windows delivery/capability constraints belong to native acceptance. |
| Deep links/single instance | Existing parser/inbox/bridge contracts. Installed OS activation not exercised by this pass. |
| New OS capabilities / Store certification | Not applicable to this bounded pass / deferred; no new integration or blanket certification promised. |

## Iteration decision

Keep the accessible baseline improvements independent of experimentation.
Before promoting any visual/copy variant, maintain the declared rubric bars and
all consent/quality invariants, and separately evaluate useful saved practice,
task completion, errors and burden using the selected provider's approved plan.
No invitation volume, dwell time, addictive retention or cosmetic score is a
substitute for voluntary habit outcomes. No hosted GrowthBook result exists in
this receipt.
