# Budlark: a bud to grow, a bird to celebrate

**Draft design proposal for owner review. Not approved, implemented, or included
in the dogfood release.** This branch changes only design artifacts and their
Node contract tests, based on `origin/main` at `8e8bf58`.

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
a main-window proposal, a completion keyframe and an icon with a 32px preview.
These are original deterministic SVG concepts, **not Flutter screenshots,
goldens, native accessibility evidence or final launcher assets**.

## Companion behavior

| Surface / event | Proposed behavior |
| --- | --- |
| Main garden | A still bird perches near the scenery, away from controls. No idle loops, hunger, alerts, sadness or attention requests. |
| Completion accepted | Save/queue the check-in through the existing habit flow first. For an accepted local offline write, retain existing sync wording; the bird does not imply server sync. Land 0-300ms, sing 300-800ms, settle 800-1000ms; no modal, focus move, input lock or delay to the next action. |
| Completion failed | Keep the existing explicit error/retry. No success bird. Repeated taps or retries of the same logical check-in must not replay the celebration. |
| Rapid completions | At most one finite sequence at a time; coalesce visual feedback while retaining each check-in's ordinary status. Do not queue a flock or extend the one-second duration. |
| Reduced motion | App **or** OS setting disables flight, translation, pulsing, fades and animated fireflies immediately, including mid-sequence. Show the final perched bird and the same success status. |
| Sound | Silent by default; the singing pose and small note shapes work without audio. A later explicit sound preference may opt into a brief original cue, respecting mute/quiet settings. No autoplay on launch or preview; no audio assets supplied here. |
| Empty garden / first plant | A calm perched companion beside "Start small". No unlock promotion before planting. |
| Sign-in | A still companion in the existing profile/first-plant surface. Do not introduce a new sign-in screen, change provider/browser UI or obscure the device/account boundary. |
| Milestone | A small dismissible acknowledgement, after the core task. No confetti modal, countdown or demand to share. |
| Rest, misses, return | No wilt, loss, streak reset, unhappy bird or "come back" guilt. Growth and unlocked themes remain. |

The success status is announced once through the existing live region; decorative
birds, notes and scenery are excluded from semantics. When celebrations are off,
the normal check-in confirmation remains; the companion is still present.
Bird type is theme-specific: "lark" names the companion's brand role, not a claim
that wrens or hummingbirds are larks. Budlark remains one word.

## Six theme families

| Theme | Companion | Setting | Access |
| --- | --- | --- | --- |
| Meadow Dawn (default) | Skylark, raised crest and warm wing | Sunrise, meadow grasses, seed heads | Free immediately |
| Zen Garden | Wren, compact body and upright short tail | Raked sand, stones, maple | Free immediately |
| Night Garden | Nightingale, long tail | Moonlight, quiet foliage, still fireflies | Free immediately; always available as the dark garden |
| Rain Forest | Hummingbird, long beak and pointed wing | Layered leaves, rain beads | 7 distinct practice days |
| Desert Bloom | Finch, stout beak and compact wing | Dunes, flowering cactus | 21 distinct practice days |
| Seasonal | Skylark | Spring buds, summer canopy, autumn leaves, winter evergreens | 45 distinct practice days; all four seasons stay selectable |

Thresholds are **coordinator-proposed review defaults**, not owner-approved
requirements. A practice day is any local calendar date with at least one
accepted habit completion, across all habits; multiple check-ins that day count
once. Days need not be consecutive. Store the local date with the completion;
do not recalculate past dates when time zone changes. This is a lifetime
consistency milestone, not a streak, speed challenge or purchase.

Unlocks are persisted entitlements, unioned with newly earned themes, never
recomputed downward. Misses, edits, deleting a habit/history entry and clock or
season changes cannot revoke them. Unlocking is free, permanent and never sold;
no subscription gate, currency, random drops, advertising or limited-time offer.
Seasonal offers a manual season selection; it never locks because a month ends.
Autumn is the one rendered seasonal example here, not four additional families.

Entitlements belong to the currently selected device/account garden, matching
existing storage boundaries. Switching gardens reads that garden's state without
merging. For a later explicit device-to-account copy, union earned unlocks only
within the already-confirmed copy transaction; never copy theme preferences,
consent or settings automatically. A failed save/copy reports an error and offers
retry; do not announce an unlock before it is durably retained. No account is
required to use free themes or earn device-garden milestones. Account sync,
schema migration and export format require a separately approved implementation.
Explicit deletion of the whole garden/account is data erasure, not a punishment;
do not retain hidden unlock records after the user's requested erasure.

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
Cancel; only Apply persists. Show availability as text ("Included" / "7 practice
days") rather than color or a shopping lock. Unlock acknowledgement never opens
the picker automatically. The main-window mockups show the active theme as
secondary, non-interactive context; they add no theme button to the habit flow.

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

Owner review is required for companion prominence, the six visual directions,
copy and milestone thresholds. Later implementation needs real Flutter
light/dark/high-contrast, 200% text, keyboard/Narrator and reduced-motion captures,
plus small-icon review. None of those app acceptance checks are claimed here.

## Reproduction and scope

From the repository root:

```powershell
node docs/design/garden-themes/render.mjs
node --test test/garden_themes_contract_test.mjs
```

The generator has no dependencies, clocks, randomness, remote fonts, downloaded
images or third-party art. It writes exactly 18 SVG files and one self-contained
HTML contact sheet with inline image data. Each completion image is the
singing/perched keyframe, not an animated recording. SVG is the canonical render;
no PNG export or Flutter golden is needed for this vector-only proposal.

The HTML review shell uses the Clawpilot light/dark tokens; the embedded SVG
artwork intentionally uses the proposed Budlark palettes. Regeneration must be
byte-identical. Tests cover contrast, finite/reduced motion, free access,
threshold boundaries, day deduplication, invalid inputs, retained unlocks,
deterministic renders and contact-sheet coverage. They do not establish native
app behavior. No changes to app imports, shipping assets, release branches,
installer packaging, deployment or release workflow are part of this proposal.
