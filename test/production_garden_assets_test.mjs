import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { productionThemes, animationSpec, svgAsset, renderManifest } from '../tool/garden_assets.mjs';
import { contrastRatio, resolveThemeAccess, themes } from '../docs/design/garden-themes/theme-model.mjs';

const root = new URL('../', import.meta.url);
const read = path => readFileSync(new URL(path, root));
const roles = ['garden', 'bird', 'song', 'seed', 'sprout', 'bud', 'bloom', 'bud-growth-still', 'lark-celebration-still'];

test('approved themes are immediately selectable, default Meadow Dawn, no retained milestone gate', () => {
  assert.equal(productionThemes[0].id, 'meadow-dawn');
  assert.equal(productionThemes.length, 6);
  assert.deepEqual(resolveThemeAccess({ practiceDays: [] }), themes.map(theme => theme.id));
  for (const theme of productionThemes) {
    assert.equal(theme.available, true);
    assert.equal(theme.price, 0);
    assert.equal(theme.unlockDays, 0);
  }
});

test('every theme supplies light and dark semantic palettes at >=4.5:1', () => {
  for (const theme of productionThemes) {
    for (const mode of ['light', 'dark']) {
      const p = theme.palettes[mode];
      for (const [fg, bg] of [['text', 'canvas'], ['text', 'surface'], ['muted', 'canvas'], ['muted', 'surface'], ['onAccent', 'accent'], ['accent', 'canvas'], ['accent', 'surface']]) {
        assert.ok(contrastRatio(p[fg], p[bg]) >= 4.5, `${theme.id}/${mode} ${fg}/${bg}`);
      }
    }
  }
});

test('canonical vectors use bounded original geometry, named layers and deterministic output', () => {
  for (const theme of productionThemes) {
    for (const role of roles) {
      const svg = read(`assets/garden_themes/${theme.id}/${role}.svg`).toString('utf8');
      assert.equal(svg, svgAsset(theme, role));
      assert.match(svg, /viewBox="0 0 \d+ \d+"/);
      assert.match(svg, /<path/);
      assert.match(svg, /id="artwork"/);
      assert.match(svg, /<title/);
      assert.doesNotMatch(svg, /NaN|Infinity|<text|<image|<script|<animate|(?:href|src)=/);
      assert.ok(!/[ \t]+$/m.test(svg), 'No trailing whitespace');
    }
    const bird = svgAsset(theme, 'bird');
    for (const layer of ['tail', 'body', 'wing', 'head', 'beak', 'feet']) {
      assert.ok(bird.includes(`id="${layer}"`), `${theme.id}: bird ${layer}`);
    }
  }
  assert.throws(() => svgAsset(productionThemes[0], 'missing'), /Unknown asset role/);
});

test('growth and lark specifications are finite, precise and have explicit reduced-motion stills', () => {
  for (const theme of productionThemes) {
    const spec = animationSpec(theme);
    assert.equal(spec.schema, 'budlark.motion-spec.v1');
    assert.equal(spec.playableLottie, false);
    assert.equal(spec.trigger, 'durable-unique-completion');
    assert.equal(spec.replayOnBuildOrSync, false);
    assert.equal(spec.inputBlocking, false);
    assert.equal(spec.soundDefault, false);
    for (const name of ['budGrowth', 'larkCelebration']) {
      const clip = spec[name];
      assert.equal(clip.loop, false);
      assert.equal(clip.reducedMotion.durationMs, 0);
      assert.equal(clip.reducedMotion.condition, 'appReducedMotion || osReducedMotion');
      assert.equal(clip.reducedMotion.skipAllTweens, true);
      assert.ok(existsSync(new URL(clip.reducedMotion.still, root)));
      assert.equal(clip.frames[0].timeMs, 0);
      assert.equal(clip.frames.at(-1).timeMs, clip.durationMs);
      for (let i = 1; i < clip.frames.length; i++) {
        assert.ok(clip.frames[i].timeMs > clip.frames[i - 1].timeMs);
      }
    }
    assert.equal(spec.larkCelebration.durationMs, 1000);
    assert.equal(spec.budGrowth.durationMs, 300);
    assert.equal(spec.budGrowth.saturateAtFinalStage, true);
    assert.deepEqual(spec.budGrowth.stageOrder, ['seed', 'sprout', 'bud', 'bloom']);
    assert.equal(spec.larkCelebration.frames.at(-1).songVisible, false);
    assert.equal(spec.larkCelebration.frames.at(-1).translateY, 0);
    assert.deepEqual(JSON.parse(read(`assets/garden_themes/${theme.id}/motion.json`)), spec);
  }
});

test('manifest names all vector, raster and motion assets with real dimensions and hashes', () => {
  const manifest = JSON.parse(read('assets/garden_themes/manifest.json'));
  assert.equal(manifest.schema, 'budlark.theme-assets.v1');
  assert.equal(manifest.defaultThemeId, 'meadow-dawn');
  assert.equal(manifest.runtimeRenderer, 'Flutter Image.asset; SVG is canonical source');
  assert.equal(manifest.themes.length, 6);
  for (const theme of manifest.themes) {
    assert.equal(theme.available, true);
    for (const ratios of Object.values(theme.contrastProof)) {
      assert.equal(Object.keys(ratios).length, 7);
      for (const ratio of Object.values(ratios)) assert.ok(ratio >= 4.5);
    }
    assert.deepEqual(Object.keys(theme.assets).sort(), [...roles].sort());
    for (const [role, asset] of Object.entries(theme.assets)) {
      assert.match(asset.svg, new RegExp(`${theme.id}/${role}\\.svg$`));
      assert.equal(createHash('sha256').update(read(asset.svg)).digest('hex'), asset.svgSha256);
      assert.deepEqual(asset.rasters.map(r => r.scale), [1, 2, 3]);
      for (const raster of asset.rasters) {
        const png = read(raster.path);
        assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
        assert.equal(png.readUInt32BE(16), asset.width * raster.scale);
        assert.equal(png.readUInt32BE(20), asset.height * raster.scale);
        assert.ok([2, 6].includes(png[25]));
        assert.equal(createHash('sha256').update(png).digest('hex'), raster.sha256);
      }
    }
  }
  assert.equal(read('assets/garden_themes/manifest.json').toString('utf8'), renderManifest());
});

test('each theme has an exported full-composition screenshot and transparent high-DPI bird', () => {
  for (const theme of productionThemes) {
    const preview = read(`docs/design/garden-themes/production-previews/${theme.id}.png`);
    assert.equal(preview.readUInt32BE(16), 960);
    assert.equal(preview.readUInt32BE(20), 640);
    const bird = read(`assets/garden_themes/${theme.id}/3.0x/bird.png`);
    assert.equal(bird[25], 6, 'Transparent RGBA layer');
  }
});

test('release integration guide documents immediate access and real Flutter raster consumption', () => {
  const doc = read('docs/design/garden-themes/production-assets.md').toString('utf8');
  assert.match(doc, /Image\.asset/);
  assert.match(doc, /all six.*immediate/i);
  assert.match(doc, /not.*playable Lottie/i);
  assert.match(doc, /no.*60\s?fps/i);
  assert.match(doc, /pubspec/);
  assert.match(doc, /persistent|persisted/);
});
