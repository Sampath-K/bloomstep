# Budlark: a bud to grow, a bird to celebrate

**Owner-approved theme direction (P15); PR ready for review, not released.**
All six themes are immediately selectable, with Meadow Dawn as default.
The [production asset pack and integration contract](garden-themes/production-assets.md)
now supplement these design frames. App picker, settings/sync and real animation
playback remain owned by the release session. No merge or release is implied.
The branch began at `origin/main` `8e8bf58`.

## Expected experience

The bud is your habit: seed, sprout, then bloom as practice accumulates. The lark
is your companion, not your score. The current folded-wing mark asks people to
infer a bird; the proposed mark shows a separate head, beak, wing, tail and
perched feet above an unmistakable bud. At small sizes the silhouette, not tiny
feather detail, must carry both ideas.

After a successful habit completion, the companion lands and sings visually for
about one second, then rests. The app celebrates the person's tiny action; it
does not replace their chosen Tiny Habits celebration. Garden themes change the
setting and companion, not the habit recipe, progress rules or primary action.
This is a hypothesis for delight and voluntary return, not evidence of retention.

See the [six-theme contact sheet](garden-themes/contact-sheet.html). Each row has
a minimal main-window proposal, a completion keyframe, a return-cue frame and
an icon with a 32px preview.
These are original deterministic SVG concepts, **not Flutter screenshots,
goldens, native accessibility evidence or final launcher assets**.

## Companion behavior

| Surface / event | Proposed behavior |
| --- | --- |
| Main garden | A still bird perches near the scenery, away from controls. No idle loops, hunger, alerts, sadness or attention requests. |
| Completion accepted | Durably save the check-in before the trigger. For an accepted local offline write, retain existing sync wording; the bird does not imply server sync. Bud grows to the next stage as the bird lands, 0-300ms; sing 300-800ms; settle 800-1000ms. The frames show bud to bloom. No modal, focus move, input lock or delay to the next action. |
| Completion failed | Keep the existing explicit error/retry. No success bird. Repeated taps or retries of the same logical check-in must not replay the celebration. |
| Rapid completions | At most one finite sequence at a time; coalesce visual feedback while retaining each check-in's ordinary status. Do not queue a flock or extend the one-second duration. |
| Reduced motion | App **or** OS setting disables flight, growth tweening, translation, pulsing, fades and animated fireflies immediately, including mid-sequence. Show the final grown plant, perched bird and the same success status. |
| Sound | Silent by default; the singing pose and small note shapes work without audio. A later explicit sound preference may opt into a brief original cue, respecting mute/quiet settings. No autoplay on launch or preview; no audio assets supplied here. |
| Empty garden / first plant | A calm perched companion beside "Start small". No unlock promotion before planting. |
| Sign-in | A still companion in the release session's owner-directed calm sign-in-first storyboard. The release session owns sign-in/profile layout and the top-right profile card; these garden frames intentionally omit that chrome to isolate the minimal core action. Never change provider/browser UI or obscure the device/account boundary. |
| Return cue | After practice, a still bird, grown plant and small coffee cup accompany "See you tomorrow after coffee". This example assumes a daily morning-coffee anchor with tomorrow as its next occurrence. Use the person's actual next anchor, not a generic daily schedule or automatic reminder. |
| Milestone | A small dismissible acknowledgement, after the core task. No confetti modal, countdown or demand to share. |
| Rest, misses, return | No wilt, loss, streak reset, unhappy bird or "come back" guilt. Growth and unlocked themes remain. |

The success status is announced once through the existing live region; decorative
birds, notes and scenery are excluded from semantics. When celebrations are off,
the normal check-in confirmation remains; the companion is still present.
Bird type is theme-specific: "lark" names the companion's brand role, not a claim
that wrens or hummingbirds are larks. Budlark remains one word.

### P14 craft refinement: calm, joy and tiny

The owner finds the earlier UI anxious, wordy and transactional. Every garden
frame now uses **one heading, one primary action and at most 12 visible words**,
including the wordmark: main has nine; completion and return each have 11.
Theme names, milestone marketing, recipe metadata and explanatory paragraphs
stay outside the core frame. Full accessible recipe wording and necessary
account/sync/error information still belong in the real app; do not hide safety
or data-boundary information merely to meet an illustration's word budget.

Main: "Your garden" / "After coffee, stretch once." / "Mark complete".
Completion: "Nicely done" / "See you tomorrow after coffee" / "Back to garden".
Return: "Rest belongs here" / the same next-anchor cue / "Close garden".
The cup is an anchor reminder, not a prompt to keep interacting.

The release session owns the default recipe sentence, at most three taps to
plant in under ten seconds, the sign-in-first sequence and profile card.
No theme choice, mascot tutorial or unlock pitch may add a required tap.
The times and tap counts are acceptance targets, **not measured results** here.

For a later Flutter component, pass the **persisted** before/after growth stages,
the theme id, a unique completion-event identity and the effective motion
preference. Trigger once after the storage transaction succeeds, not on rebuild,
navigation, sync replay or a failed write. The stage shown must match the saved
habit state; never invent progress just for animation or reset an already-grown
plant. The proposed one-stage completion progression must be reconciled with
the release session's growth model before implementation. This proposal exports
no production Flutter widget; `celebrationPolicy` is a Node contract fixture only.

## Six theme families

| Theme | Companion | Setting | Access |
| --- | --- | --- | --- |
| Meadow Dawn (default) | Skylark, raised crest and warm wing | Sunrise, meadow grasses, seed heads | Free immediately |
| Zen Garden | Wren, compact body and upright short tail | Raked sand, stones, maple | Free immediately |
| Night Garden | Nightingale, long tail | Moonlight, quiet foliage, still fireflies | Free immediately; always available as the dark garden |
| Rain Forest | Hummingbird, long beak and pointed wing | Layered leaves, rain beads | Free immediately |
| Desert Bloom | Finch, stout beak and compact wing | Dunes, flowering cactus | Free immediately |
| Seasonal | Skylark | Autumn foliage in the current pack | Free immediately |

Owner P15 supersedes the earlier 7/21/45-day proposal: **no milestone gating**.
All six themes are free immediately, independent of practice history or account.
Misses, edits, deleted history and clock/season changes cannot remove access.
No subscription, currency, random drops, advertising or limited-time offer.
Autumn is the rendered Seasonal artwork; additional season illustrations are
not claimed as delivered by this pack.

The selected theme id is persisted/synced through the existing garden settings
by the release session. Switching gardens must respect account/device ownership;
do not merge their data or copy settings without the existing explicit boundary.
A failed settings write exposes an error/retry rather than claiming success.

## Theme model and boundaries

[`theme-model.mjs`](garden-themes/theme-model.mjs) is an executable **proposal
fixture**, not a production module. A theme has a stable `id`, display `name`,
`bird`, descriptive `background`, `unlockDays` and opaque palette tokens:
`canvas`, `surface`, `text`, `muted`, `accent`, `onAccent`, `sky`, `ground`,
`plant`, `bloom`, `bird`, `wing`, `detail`.

Semantic UI tokens are separate from decorative art tokens. Never put body text
on scenery. The executable contrast pairs are text/muted on canvas and surface,
onAccent on accent, and accent on canvas/surface for labeled controls. Bird,
wing, bloom and ground are decorative; their colors cannot stand for success,
availability or selection. Seasonal's palette represents autumn; the other
three palettes need the same contract before implementation.

Theme selection lives under the existing Settings surface: preview, Apply,
Cancel; only Apply persists. All six choices show "Included", with no lock or
counter. Reach the picker in at most two taps from profile card/settings.
The minimal main-window mockups add no theme choice to the primary habit flow.

The profile, recipes, reminders, privacy, sync errors, deletion warnings,
invitations and the anchor/action/celebration builder keep their existing
ordering, labels, boundaries and primary action. Theme changes cannot modify
habit difficulty, check-in counts, plant growth, notifications or analytics.
No new telemetry or permissions are proposed. The real launcher icon remains
stable (Meadow Dawn bird + bud if approved); the other five icon renders are
theme-gallery badges, not automatic OS shortcut/taskbar identity changes.

## Accessibility and acceptance before implementation

- Every normal text pair is at least **4.5:1**, including muted labels and
  button text. Focus, control edges and non-text state indicators need at least
  3:1 against adjacent colors. Use explicit labels/checkmarks, never color alone.
- Preserve high-contrast/forced-colors semantic tokens and system focus rings;
  decorative palettes must yield to system accessibility, not override it.
  Dark preference must retain access to free Night Garden rather than push an
  unlock. Theme preview cannot silently override accessibility preferences.
- Reduced motion is the OR of the app and OS preferences, not a per-theme
  exception. Fireflies, rain and seasonal leaves are static in every theme;
  there is no flashing or ambient movement even in normal motion.
- Keyboard/assistive-technology users can preview, apply, cancel and recover
  focus. Touch targets are at least 44 logical pixels. At 200% text, compact
  windows and mixed DPI, controls reflow/scroll rather than clip.
- Preview the candidate mark at 16, 24, 32 and 256px on light/dark Windows
  surfaces before replacing assets. The contact sheet's 32px sample is a
  design aid, not a passed legibility/usability test.

The owner approved the six theme directions and immediate access. Production
art quality and integrated behavior still need review. Implementation needs real Flutter
light/dark/high-contrast, 200% text, keyboard/Narrator and reduced-motion captures,
plus small-icon review. None of those app acceptance checks are claimed here.

## Reproduction and scope

From the repository root:

```powershell
node docs/design/garden-themes/render.mjs
node --test test/garden_themes_contract_test.mjs
```

The generator has no dependencies, clocks, randomness, remote fonts, downloaded
images or third-party art. It writes exactly 24 SVG files and one self-contained
HTML contact sheet with inline image data. Each completion image is the
singing/perched keyframe, not an animated recording. SVG is the canonical render;
the separate production pack includes PNG density exports and motion specs.

The HTML review shell uses the Clawpilot light/dark tokens; the embedded SVG
artwork intentionally uses the proposed Budlark palettes. Regeneration must be
byte-identical. Tests cover contrast, finite/reduced motion, free access,
all-six immediate access, invalid inputs, non-revocation,
deterministic renders and contact-sheet coverage. They do not establish native
app behavior. The production asset pack adds original assets only, no app imports,
pubspec changes, release-branch edits, installer changes, deployment or release.
