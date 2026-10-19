# Production garden asset pack

All six themes have immediate access, with Meadow Dawn the default. Owner P15
supersedes the original milestone gates. PR56 is ready for review, not a merge
or release approval. This pack supplies production-consumable original vector
geometry and raster assets; native UI integration remains the release session's
responsibility. "High quality" is an owner review goal, not a measured outcome.

## Stable file contract

`assets/garden_themes/manifest.json` is the source-of-truth runtime contract:
stable theme ids, display names, companion species, immediate availability,
light/dark semantic palettes, layout origins, asset dimensions and SHA-256
digests. It enumerates every generated path, including density variants.

For each of `meadow-dawn`, `zen-garden`, `night-garden`, `rain-forest`,
`desert-bloom`, `seasonal`, `assets/garden_themes/<id>/` contains:

| File stem | Logical pixels | Purpose |
| --- | --- | --- |
| `garden` | 640 x 320 | Original decorative scenery; no text, controls or habit progress |
| `bird` | 160 x 160 | Transparent distinct-species companion; separated head, beak, wing, tail, feet |
| `song` | 64 x 64 | Transparent note layer, only visible at 300-800ms in normal motion |
| `seed`, `sprout`, `bud`, `bloom` | 160 x 160 | Transparent plant states; fixed origin/bounds for transitions |
| `bud-growth-still` | 160 x 160 | Reduced-motion final bloom example |
| `lark-celebration-still` | 320 x 240 | Reduced-motion grown plant + settled bird example; no song notes |

Every stem has canonical `.svg`, base `.png`, `2.0x/<stem>.png` and
`3.0x/<stem>.png`. Garden exports reach 1920 x 960; bird exports reach
480 x 480. PNGs preserve transparency for layers. Canonical SVGs use original
bounded vector paths, named layer groups, opaque art tokens and subtle vector
gradients, no images, fonts, scripts, third-party content or embedded animation.
Do not replace the real OS launcher icon with a theme badge.

## Flutter integration (no new SVG dependency)

Use **`Image.asset`** for the shipped PNGs; Flutter automatically selects the
2.0x/3.0x density variants. SVG is the canonical source, not a dependency on an
uninstalled SVG renderer. Do not pass `.svg` to `Image.asset`. No runtime Lottie,
Rive or SVG package is added by this pack.

The release session adds the following directories to its `pubspec.yaml`
Flutter assets list (one entry per theme; Flutter bundles recognized density
variants automatically):

```yaml
- assets/garden_themes/meadow-dawn/
- assets/garden_themes/zen-garden/
- assets/garden_themes/night-garden/
- assets/garden_themes/rain-forest/
- assets/garden_themes/desert-bloom/
- assets/garden_themes/seasonal/
- assets/garden_themes/manifest.json
```

```dart
Image.asset(
  'assets/garden_themes/$themeId/bird.png',
  width: 160,
  height: 160,
  excludeFromSemantics: true,
  filterQuality: FilterQuality.high,
)
```

Whitelist theme ids against the manifest. Default to Meadow Dawn only for a
missing preference; a failed settings read/write must show the app's existing
error/retry, not pretend a persisted selection succeeded. Preserve an unknown
future preference in storage until a supported choice is explicitly applied.
Persist and sync the selected id through existing per-garden settings boundaries;
never merge account and device gardens merely to share a theme choice.

The picker is at most two taps from profile card/settings, uses all six options,
and previews without writing until Apply. No payment, practice counter or lock
affordance. Theme selection must not delay the <10-second planting journey.
The release session owns these UI/persistence/sync checks and Flutter packaging.

## Motion contract

Each theme's `motion.json` is **not a playable Lottie** file. It is a documented
Rive-style state/layer timeline, schema `budlark.motion-spec.v1`, intended for
Flutter's existing animation/transform APIs or later animator tooling. There is
no unmeasured 60fps claim and no runtime playback implementation in this pack.

Only a unique successful **durable** practice transaction starts both clips.
No trigger on failed writes, rebuilds, navigation or server replay. Cancel on
dispose, theme change or a new effective reduced-motion preference; never block
input or focus. Keep at most one finite sequence active and never extend it
with a queue of completions.

Bud growth runs 0-300ms, crossfading persisted before/after stage layers at a
fixed root origin with a subtle 0.96-to-1 scale. Use the saved stages; do not
invent progress, advance a fully grown plant or infer success from an animation.
Bird landing runs 0-300ms (20px right, 28px up to settled), the singing pose/
optional note layer lasts 300-800ms, then the companion rests through 1000ms.
No ambient loop, flashes, flying fireflies, falling rain or moving leaves.
Sound is off by default; this pack contains no audio.

For **app OR OS reduced motion**, skip every tween immediately, show the saved
after-stage plant and still bird, and announce the same ordinary check-in
confirmation once. `bud-growth-still` illustrates the final bloom only: if the
saved after-stage is seed/sprout/bud, select that stage PNG instead. The same
applies to the composition still; do not use its bloom to override saved progress.
Each clip names an explicit reduced-motion SVG and raster fallback plus the
mid-animation cancellation rule in `motion.json`.

## Contrast and previews

Both light and dark palettes expose `canvas`, `surface`, `text`, `muted`,
`accent`, `onAccent`. Tests require >=4.5:1 for text and muted text on both
backgrounds, accent on both backgrounds and onAccent on accent. These proofs
apply to semantic UI tokens, not decorative scenery. The manifest includes
numeric `contrastProof` ratios for both modes. Never put text on the art
or use bird/leaf colors as the only success/selection signal. Forced colors,
focus rings and OS accessibility preferences override decorative theme choices.
The dark semantic set is shared intentionally for consistent readable controls;
the six original scenery/companion palettes remain distinct.

`production-previews/<theme-id>.png` provides an actual 960 x 640 rendered
composition for every theme (Night Garden uses dark UI). The corresponding SVG
is its deterministic preview source. These are asset composition screenshots,
not screenshots of the running Flutter app or performance/accessibility proof.
Production frames isolate art; release still needs real light/dark/forced-color,
200% text, Narrator, keyboard, density and in-app reduced-motion checks.
Seasonal currently renders autumn; no unrendered spring/summer/winter artwork
is claimed in this six-family asset delivery.

## Reproduction

```powershell
node tool/garden_assets.mjs
python tool/export_garden_assets.py
node tool/garden_assets.mjs --manifest
python tool/export_garden_assets.py --verify
node --test test/production_garden_assets_test.mjs test/garden_themes_contract_test.mjs test/brand_assets_test.mjs
```

The exporter uses the installed Python Playwright and headless Edge, pinned to
software rendering and sRGB to avoid GPU-dependent gradient differences. It fails
explicitly if prerequisites are missing; it does not download software or bypass
browser protections. Vector/JSON generation has no dependency, randomness,
timestamps or remote assets. PNG encoding is browser-version-dependent; the
manifest hashes the actual committed bytes. Regeneration on the same installed
renderer is checked separately; cross-browser pixel identity is not promised.
