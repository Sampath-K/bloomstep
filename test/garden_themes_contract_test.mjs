import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { themes, seasonalVariants, contrastRatio, resolveThemeAccess, celebrationPolicy } from '../docs/design/garden-themes/theme-model.mjs';
import { renderSvg, renderContactSheet } from '../docs/design/garden-themes/render.mjs';

const directory = new URL('../docs/design/garden-themes/', import.meta.url);
const days = count => Array.from({ length: count }, (_, i) =>
  new Date(Date.UTC(2026, 0, i * 2 + 1)).toISOString().slice(0, 10));
const free = ['meadow-dawn', 'zen-garden', 'night-garden'];

test('six theme families have complete opaque tokens and the agreed companions', () => {
  assert.deepEqual(themes.map(t => [t.name, t.bird, t.unlockDays]), [
    ['Meadow Dawn', 'Skylark', 0], ['Zen Garden', 'Wren', 0],
    ['Night Garden', 'Nightingale', 0], ['Rain Forest', 'Hummingbird', 7],
    ['Desert Bloom', 'Finch', 21], ['Seasonal', 'Skylark', 45],
  ]);
  assert.equal(new Set(themes.map(t => t.id)).size, 6);
  for (const theme of themes) {
    assert.ok(theme.background.length > 20);
    assert.deepEqual(Object.keys(theme.palette).sort(), [
      'canvas', 'surface', 'text', 'muted', 'accent', 'onAccent', 'sky',
      'ground', 'plant', 'bloom', 'bird', 'wing', 'detail',
    ].sort());
    for (const color of Object.values(theme.palette)) assert.match(color, /^#[0-9A-F]{6}$/);
  }
  assert.deepEqual(seasonalVariants, ['spring', 'summer', 'autumn', 'winter']);
});

test('WCAG contrast calculation matches reference extremes and rejects invalid colors', () => {
  assert.equal(contrastRatio('#000000', '#FFFFFF'), 21);
  assert.equal(contrastRatio('#123456', '#123456'), 1);
  assert.ok(Math.abs(contrastRatio('#777777', '#FFFFFF') - 4.478089) < 0.00001);
  for (const color of ['#fff', '#FFFFFFFF', 'red', '#GGGGGG']) {
    assert.throws(() => contrastRatio(color, '#FFFFFF'), TypeError);
  }
});

for (const theme of themes) {
  test(`${theme.name}: all specified text and control pairs meet at least 4.5:1`, () => {
    const p = theme.palette;
    const pairs = [
      ['text', 'canvas'], ['text', 'surface'], ['muted', 'canvas'],
      ['muted', 'surface'], ['onAccent', 'accent'],
      ['accent', 'canvas'], ['accent', 'surface'],
    ];
    for (const [fg, bg] of pairs) {
      const ratio = contrastRatio(p[fg], p[bg]);
      assert.ok(ratio >= 4.5, `${theme.name} ${fg}/${bg}: ${ratio.toFixed(3)} < 4.5`);
    }
  });
}

test('free themes, including dark, need neither practice nor an account', () => {
  assert.deepEqual(resolveThemeAccess({ practiceDays: [] }), free);
});

test('distinct nonconsecutive practice days unlock exactly at 7, 21 and 45', () => {
  for (const [count, expected] of [[6, 3], [7, 4], [20, 4], [21, 5], [44, 5], [45, 6]]) {
    assert.equal(resolveThemeAccess({ practiceDays: days(count) }).length, expected, `${count} days`);
  }
  assert.deepEqual(resolveThemeAccess({ practiceDays: Array(100).fill('2026-01-01') }), free);
  assert.deepEqual(resolveThemeAccess({ practiceDays: days(7).reverse() }),
    [...free, 'rain-forest']);
});

test('every earned theme survives missing history and all later lower practice totals', () => {
  const earned = resolveThemeAccess({ practiceDays: days(45) });
  for (let count = 0; count <= 45; count++) {
    assert.deepEqual(resolveThemeAccess({ practiceDays: days(count), unlockedThemeIds: earned }), earned);
  }
  assert.deepEqual(resolveThemeAccess({ practiceDays: [], unlockedThemeIds: ['seasonal'] }), [...free, 'seasonal']);
  assert.deepEqual(resolveThemeAccess({ practiceDays: days(7), unlockedThemeIds: ['desert-bloom', 'desert-bloom'] }),
    [...free, 'rain-forest', 'desert-bloom']);
});

test('invalid entitlement inputs fail explicitly instead of fabricating success', () => {
  for (const practiceDays of [null, {}, ['2026-02-30'], ['not-a-date'], ['2026-13-01'], [7], ['2026-1-01']]) {
    assert.throws(() => resolveThemeAccess({ practiceDays }), TypeError);
  }
  assert.throws(() => resolveThemeAccess({ practiceDays: [], unlockedThemeIds: null }), TypeError);
  assert.throws(() => resolveThemeAccess({ practiceDays: [], unlockedThemeIds: ['missing-theme'] }), /Unknown theme/);
  assert.deepEqual(resolveThemeAccess({ practiceDays: ['2024-02-29'] }), free);
});

test('app OR OS reduced motion disables every flight with an equivalent static result', () => {
  for (const theme of themes) {
    for (const appReducedMotion of [false, true]) {
      for (const osReducedMotion of [false, true]) {
        const policy = celebrationPolicy({ appReducedMotion, osReducedMotion });
        const reduced = appReducedMotion || osReducedMotion;
        assert.equal(policy.flight, !reduced, theme.id);
        assert.equal(policy.durationMs, reduced ? 0 : 1000, theme.id);
        assert.equal(policy.staticBird, true);
        assert.equal(policy.ambientMotion, false);
        assert.equal(policy.statusText, 'A little practice, a little growth.');
        assert.equal(policy.sound, false);
      }
    }
  }
});

test('celebration and audio preferences are separate, finite and strictly typed', () => {
  assert.equal(celebrationPolicy({ soundEnabled: true }).sound, true);
  assert.equal(celebrationPolicy({ soundEnabled: true, osReducedMotion: true }).flight, false);
  const off = celebrationPolicy({ celebrationEnabled: false, soundEnabled: true });
  assert.equal(off.sound, false);
  assert.equal(off.flight, false);
  assert.equal(off.durationMs, 0);
  assert.equal(off.staticBird, true);
  assert.ok(off.statusText);
  for (const key of ['appReducedMotion', 'osReducedMotion', 'celebrationEnabled', 'soundEnabled']) {
    assert.throws(() => celebrationPolicy({ [key]: 'false' }), TypeError);
  }
});

test('all 24 committed SVGs match deterministic renders and have accessible descriptions', () => {
  const expected = [];
  for (const theme of themes) {
    for (const state of ['main', 'completion', 'return', 'icon']) {
      const name = `${theme.id}-${state}.svg`;
      expected.push(name);
      const actual = readFileSync(new URL(name, directory), 'utf8');
      assert.equal(actual, renderSvg(theme, state), `Regenerate stale ${name}`);
      assert.match(actual, /role="img" aria-labelledby="title description"/);
      assert.match(actual, /<title id="title">Budlark/);
      assert.match(actual, /<desc id="description">/);
      assert.ok(actual.includes(`data-bird="${theme.bird}"`));
      assert.doesNotMatch(actual, /<script|<animate|<image|https?:\/\/(?!www\.w3\.org)/);
      if (state === 'main') assert.ok(actual.includes('Mark complete'));
      if (state === 'completion') assert.ok(actual.includes('Nicely done'));
      if (state === 'return') assert.ok(actual.includes('See you tomorrow after coffee'));
    }
  }
  assert.deepEqual(readdirSync(directory).filter(name => name.endsWith('.svg')).sort(), expected.sort());
  assert.throws(() => renderSvg(themes[0], 'missing-state'), /Unknown render state/);
});

test('P14 frames have one heading, one action, at most twelve words and an honest growth transition', () => {
  for (const theme of themes) {
    for (const state of ['main', 'completion', 'return']) {
      const svg = renderSvg(theme, state);
      const visible = [...svg.matchAll(/<text\b[^>]*>([^<]*)<\/text>/g)].map(match => match[1]);
      const wordCount = visible.join(' ').trim().split(/\s+/).length;
      assert.equal(visible.length, 4, `${theme.id}/${state}: wordmark, heading, sentence, action only`);
      assert.equal((svg.match(/data-role="heading"/g) || []).length, 1);
      assert.equal((svg.match(/data-role="primary-action"/g) || []).length, 1);
      assert.equal(wordCount, state === 'main' ? 9 : 11);
      assert.ok(wordCount <= 12);
      if (state !== 'main') assert.ok(visible.includes('See you tomorrow after coffee'));
    }
    assert.match(renderSvg(theme, 'main'), /data-growth="bud"/);
    assert.doesNotMatch(renderSvg(theme, 'completion'), /data-growth="bud"/);
    assert.match(renderSvg(theme, 'completion'), /habit bud has grown to bloom/);
    assert.match(renderSvg(theme, 'return'), /coffee cup recall the next anchor/);
  }
});

test('self-contained contact sheet includes every state and a small icon study', () => {
  const actual = readFileSync(new URL('contact-sheet.html', directory), 'utf8');
  assert.equal(actual, renderContactSheet(), 'Regenerate stale contact sheet');
  assert.equal((actual.match(/<section /g) || []).length, 6);
  assert.equal((actual.match(/data:image\/svg\+xml;base64,/g) || []).length, 30);
  for (const theme of themes) {
    assert.ok(actual.includes(`id="${theme.id}"`));
    for (const state of ['main', 'completion', 'return', 'icon']) {
      assert.ok(actual.includes(Buffer.from(renderSvg(theme, state)).toString('base64')));
    }
  }
  assert.match(actual, /--cp-bg: #f7f4ef/);
  assert.match(actual, /html\[data-theme="dark"\]/);
  assert.match(actual, /prefers-color-scheme/);
  assert.doesNotMatch(actual, /(?:src|href)="https?:|<link|<iframe/);
});
