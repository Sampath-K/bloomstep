import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { themes, contrastRatio } from '../docs/design/garden-themes/theme-model.mjs';

const base = new URL('../', import.meta.url);
const dark = { canvas: '#17232D', surface: '#22313C', text: '#F2F4F0', muted: '#C0CBCD', accent: '#B5D9B2', onAccent: '#17232D' };
const light = { canvas: '#F7F4EF', surface: '#FFFFFF', text: '#242424', muted: '#5C5C5C', accent: '#2F6F4E', onAccent: '#FFFFFF' };
const dimensions = {
  garden: [640, 320], bird: [160, 160], song: [64, 64], seed: [160, 160],
  sprout: [160, 160], bud: [160, 160], bloom: [160, 160],
  'bud-growth-still': [160, 160], 'lark-celebration-still': [320, 240],
};
export const productionThemes = themes.map(theme => ({
  id: theme.id, name: theme.name, bird: theme.bird,
  available: true, price: 0, unlockDays: 0,
  defaultBrightness: theme.id === 'night-garden' ? 'dark' : 'light',
  palettes: {
    light: theme.id === 'night-garden' ? light : Object.fromEntries(Object.keys(light).map(key => [key, theme.palette[key]])),
    dark: { ...dark },
  },
  art: { ...theme.palette },
}));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const path = (d, fill, extra = '') => `<path d="${d}" fill="${fill}"${extra ? ` ${extra}` : ''}/>`;
const stroke = (d, color, width = 2, extra = '') =>
  path(d, 'none', `stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round" ${extra}`);
const group = (id, body, transform = '') => `<g id="${id}"${transform ? ` transform="${transform}"` : ''}>${body}</g>`;

function definitions(theme) {
  const p = theme.art;
  return `<defs>
<linearGradient id="sky" x2="0" y2="1"><stop stop-color="${p.sky}"/><stop offset="1" stop-color="${p.canvas}"/></linearGradient>
<linearGradient id="petal" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${p.bloom}"/><stop offset="1" stop-color="${p.bird}"/></linearGradient>
<linearGradient id="feather" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${p.wing}"/><stop offset="1" stop-color="${p.bird}"/></linearGradient>
</defs>`;
}

function birdArt(theme) {
  const p = theme.art;
  const humming = theme.bird === 'Hummingbird', wren = theme.bird === 'Wren';
  const finch = theme.bird === 'Finch', lark = theme.bird === 'Skylark';
  return group('bird', [
    group('tail', path(wren ? 'M50 96C36 79 31 58 25 48C20 67 24 97 41 113Z' : humming
      ? 'M48 98L13 128L45 116L30 141L65 111Z'
      : 'M50 92C37 100 24 110 13 127L51 120L67 107Z', p.bird)
      + stroke(wren ? 'M30 65L42 101' : 'M27 118L53 104', p.wing, 2)),
    group('feet', stroke('M70 116L68 136L59 140M68 136L77 139M91 116L94 136L85 140M94 136L104 139', p.bird, 3)),
    group('body', path('M43 94C41 74 57 64 78 66C94 68 103 60 109 54C120 69 118 88 103 107C88 126 57 123 43 106C41 102 41 98 43 94Z', p.bird)
      + path('M51 99C66 111 87 115 103 98C94 121 67 125 51 109Z', p.wing, 'opacity=".7"')),
    group('wing', path(humming ? 'M58 91C44 76 34 52 43 30C62 41 77 62 82 87C77 98 66 100 58 91Z'
      : 'M51 87C64 75 86 78 97 89C89 107 65 114 51 87Z', 'url(#feather)')
      + stroke(humming ? 'M48 44L69 86M45 57L64 86' : 'M60 90Q74 99 88 92M62 97Q73 103 82 98', p.bird, 1.8)),
    group('head', path('M88 61C84 44 93 30 109 30C127 30 137 44 132 58C128 69 117 75 104 71Z', p.bird)
      + (lark ? path('M96 34L94 17L105 26L111 14L118 32Z', p.bird) : '')
      + path('M99 58Q112 60 125 53Q120 69 106 68Z', p.wing)
      + path('M112 42a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0', p.detail)
      + path('M114 41a1 1 0 1 0 2 0a1 1 0 1 0-2 0', p.surface)),
    group('beak', path(humming ? 'M130 43L159 37L132 49Z' : finch
      ? 'M130 40L151 49L129 56Z' : 'M131 44L147 49L130 52Z', p.bird)),
    lark ? group('breast-detail', stroke('M86 80L88 85M94 77L96 82M80 86L82 91', p.wing, 1.8)) : '',
  ].join(''));
}

function plantArt(theme, stage) {
  const p = theme.art;
  const soil = path('M35 143C54 134 107 134 126 143C109 152 54 152 35 143Z', p.ground);
  if (stage === 'seed') return group('plant-seed', soil + path('M70 129C68 116 82 109 94 115C98 129 85 137 70 129Z', p.bird)
    + stroke('M75 129Q81 120 91 117', p.wing, 2));
  const stemTop = stage === 'sprout' ? 78 : 48;
  const leaves = group('leaves',
    path('M80 116C61 115 39 102 38 82C59 80 77 93 80 109Z', p.plant)
    + path('M81 95C89 73 107 68 123 71C122 90 103 104 81 102Z', p.plant)
    + stroke('M48 89L76 110M88 96L114 78', p.ground, 1.6));
  const stem = stroke(`M80 140C76 114 84 88 80 ${stemTop}`, p.plant, 5);
  const bud = path('M80 64C57 55 54 33 66 19C70 30 77 28 80 16C84 28 91 29 96 19C108 37 101 56 80 64Z', 'url(#petal)')
    + stroke('M80 59Q70 46 72 34M80 59Q90 45 89 34', p.wing, 1.2, 'opacity=".6"');
  const bloom = group('petals',
    path('M80 57C56 62 39 49 44 34C48 24 61 25 69 31C56 6 78 0 86 21C96 0 116 13 105 31C131 24 138 47 115 55C115 78 91 80 80 57Z', 'url(#petal)')
    + stroke('M83 43L66 36M85 42L86 24M90 45L106 37M91 50L105 61', p.wing, 1.5, 'opacity=".65"')
    + path('M77 43a12 12 0 1 0 24 0a12 12 0 1 0-24 0', p.wing)
    + path('M85 39a2 2 0 1 0 4 0a2 2 0 1 0-4 0M91 45a2 2 0 1 0 4 0a2 2 0 1 0-4 0', p.bloom));
  return group(`plant-${stage}`, soil + stem + leaves + (stage === 'sprout' ? '' : stage === 'bud' ? bud : bloom));
}

function backgroundArt(theme) {
  const p = theme.art;
  const hills = path('M0 254C109 195 204 233 320 242C454 251 537 188 640 223V320H0Z', p.ground)
    + path('M0 286C152 257 218 295 375 267C495 246 583 263 640 279V320H0Z', p.plant, 'opacity=".12"');
  let details = '';
  switch (theme.id) {
    case 'meadow-dawn':
      details = path('M489 74a39 39 0 1 0 78 0a39 39 0 1 0-78 0', p.wing)
        + stroke('M39 280Q58 222 47 178M62 284Q89 241 81 209M576 274Q589 227 607 201', p.plant, 2.5)
        + path('M43 181C35 164 39 151 47 148C55 161 55 171 49 183ZM78 211C69 198 72 187 80 182C89 194 88 204 84 215ZM603 203C599 188 606 178 615 179C617 191 612 202 607 208Z', p.bird)
        + stroke('M102 131Q117 120 128 128M147 108Q159 99 172 105', p.bird, 2);
      break;
    case 'zen-garden':
      details = [0, 9, 18, 27].map(offset => stroke(`M21 ${269 + offset}C120 ${225 + offset} 168 ${299 + offset} 290 ${266 + offset}S477 ${241 + offset} 619 ${274 + offset}`, p.bird, 1, 'opacity=".32"')).join('')
        + path('M55 257C60 230 93 229 114 248C116 267 65 271 55 257ZM103 268C113 247 141 253 148 267C139 278 115 279 103 268Z', p.bird)
        + stroke('M544 257L535 145M535 188L502 159M537 201L576 163', p.plant, 5)
        + path('M493 166C469 149 487 126 506 137C495 107 529 105 534 132C548 105 570 126 554 143C585 131 592 164 564 170C542 193 514 183 493 166Z', p.bloom);
      break;
    case 'night-garden':
      details = path('M507 71C507 43 528 27 548 34C522 43 525 83 553 89C534 102 507 92 507 71Z', p.wing)
        + path('M18 260L63 159L103 257L132 198L171 274ZM488 269L540 170L586 261L617 206L640 254V284Z', p.plant, 'opacity=".22"')
        + [[65, 107], [162, 186], [236, 62], [406, 147], [556, 191], [596, 123], [456, 227]].map(([x, y]) =>
          path(`M${x} ${y}a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0`, p.wing)).join('');
      break;
    case 'rain-forest':
      details = path('M0 207C4 98 64 57 119 85C112 158 53 200 0 207ZM640 205C548 202 513 118 552 63C622 74 650 134 640 205Z', p.plant)
        + stroke('M9 196L98 95M633 190L563 80', p.ground, 2)
        + stroke('M34 163L27 126M49 147L68 144M73 121L71 97M594 139L614 129M578 111L578 89', p.ground, 1.4)
        + path('M143 154C129 173 131 186 143 186C155 186 157 174 143 154ZM504 130C494 145 493 154 503 155C514 153 514 146 504 130Z', p.bird, 'opacity=".6"');
      break;
    case 'desert-bloom':
      details = path('M478 80a37 37 0 1 0 74 0a37 37 0 1 0-74 0', p.wing)
        + path('M0 230Q142 158 283 233Q452 151 640 214V289H0Z', p.ground)
        + stroke('M87 267V156M87 214H58V184M88 233H113V198', p.plant, 16)
        + stroke('M84 253V174M59 203V191M109 223V204', p.ground, 1.4)
        + path('M80 157C65 146 73 133 85 140C91 122 106 136 98 147C112 154 101 167 89 157Z', p.bloom)
        + path('M560 275Q551 243 561 216Q568 245 578 257Q592 240 594 233Q607 264 596 279Z', p.plant);
      break;
    case 'seasonal':
      details = stroke('M96 269V152M96 207L66 182M97 186L126 156', p.bird, 6)
        + path('M43 170C21 145 40 116 63 120C62 94 96 87 110 112C135 92 159 121 143 145C169 162 145 193 121 183C103 209 69 199 65 182C55 187 48 180 43 170Z', p.bloom)
        + stroke('M56 150L71 164M93 124L97 150M125 133L112 154', p.wing, 2)
        + path('M514 266C523 252 537 253 548 257C542 273 524 274 514 266ZM565 278C574 261 585 263 596 268C588 281 576 285 565 278Z', p.wing)
        + stroke('M520 266L540 258M572 277L590 269', p.bird, 1);
      break;
    default: throw new Error(`Unknown theme ${theme.id}`);
  }
  return group('scenery', path('M0 0H640V320H0Z', 'url(#sky)') + hills + details
    + group('perch', stroke('M416 246Q459 240 500 246', p.bird, 3)));
}

function compose(theme, role) {
  if (role === 'garden') return backgroundArt(theme);
  if (role === 'bird') return birdArt(theme);
  if (role === 'song') return group('song-notes',
    path('M20 42V15L46 9V36H41V16L25 20V42Z', theme.art.bird)
    + path('M9 44C9 37 25 34 25 40C26 48 10 52 9 44ZM30 38C30 31 46 28 46 34C47 42 31 46 30 38Z', theme.art.bird));
  if (role === 'bud-growth-still') return plantArt(theme, 'bloom');
  if (role === 'lark-celebration-still') {
    return group('grown-plant', plantArt(theme, 'bloom'), 'translate(22 59)')
      + stroke('M154 170H270', theme.art.bird, 4)
      + group('settled-companion', birdArt(theme), 'translate(143 53) scale(.8)');
  }
  return plantArt(theme, role);
}

export function svgAsset(theme, role) {
  if (!dimensions[role]) throw new Error(`Unknown asset role: ${role}`);
  const [width, height] = dimensions[role];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
<title id="title">Budlark ${theme.name}: ${role}</title>
<desc id="description">Original vector artwork. ${theme.bird} companion. ${role.includes('still') ? 'Reduced-motion final state; no animated effects.' : 'Decorative layer; exclude from app semantics.'}</desc>
${definitions(theme)}
${group('artwork', compose(theme, role))}
</svg>
`;
}

export function animationSpec(theme) {
  const prefix = `assets/garden_themes/${theme.id}`;
  const reduce = still => ({
    condition: 'appReducedMotion || osReducedMotion',
    durationMs: 0, skipAllTweens: true, still: `${prefix}/${still}.svg`,
    rasterStill: `${prefix}/${still}.png`,
    onPreferenceChange: 'cancel-in-flight-and-show-final-state',
  });
  return {
    schema: 'budlark.motion-spec.v1', playableLottie: false,
    description: 'Rive-style layer/state timeline specification; not a runtime animation file.',
    trigger: 'durable-unique-completion', replayOnBuildOrSync: false,
    inputBlocking: false, soundDefault: false,
    units: 'logical pixels; normalized opacity and scale; rotation in degrees',
    easing: { landing: [0.22, 1, 0.36, 1], growth: [0.2, 0, 0, 1] },
    budGrowth: {
      durationMs: 300, loop: false, stageOrder: ['seed', 'sprout', 'bud', 'bloom'],
      stageSource: 'persisted-before-and-after-stage; never manufacture progress',
      saturateAtFinalStage: true,
      layers: { before: 'persisted before-stage raster', after: 'persisted after-stage raster' },
      frames: [
        { timeMs: 0, beforeOpacity: 1, afterOpacity: 0, afterScale: 0.96 },
        { timeMs: 150, beforeOpacity: 0.4, afterOpacity: 0.6, afterScale: 0.99 },
        { timeMs: 300, beforeOpacity: 0, afterOpacity: 1, afterScale: 1 },
      ],
      reducedMotion: {
        ...reduce('bud-growth-still'),
        stageOverride: 'use persisted after-stage raster, not bloom still when after-stage differs',
      },
    },
    larkCelebration: {
      durationMs: 1000, loop: false, layerAsset: `${prefix}/bird.png`,
      pivot: [80, 140], songLayer: `${prefix}/song.png`,
      songOriginRelativeToBird: [128, -24],
      frames: [
        { timeMs: 0, translateX: 20, translateY: -28, rotation: -8, songVisible: false },
        { timeMs: 300, translateX: 0, translateY: 0, rotation: 0, songVisible: true },
        { timeMs: 550, translateX: 0, translateY: 0, rotation: -2, songVisible: true },
        { timeMs: 800, translateX: 0, translateY: 0, rotation: 0, songVisible: false },
        { timeMs: 1000, translateX: 0, translateY: 0, rotation: 0, songVisible: false },
      ],
      reducedMotion: reduce('lark-celebration-still'),
    },
  };
}

function assetEntry(theme, role) {
  const prefix = `assets/garden_themes/${theme.id}`;
  const svg = `${prefix}/${role}.svg`;
  const [width, height] = dimensions[role];
  return {
    svg, svgSha256: hash(readFileSync(new URL(svg, base))), width, height,
    rasters: [1, 2, 3].map(scale => {
      const filename = `${prefix}/${scale === 1 ? '' : `${scale}.0x/`}${role}.png`;
      return { scale, path: filename, sha256: hash(readFileSync(new URL(filename, base))) };
    }),
  };
}

export function renderManifest() {
  return JSON.stringify({
    schema: 'budlark.theme-assets.v1', defaultThemeId: 'meadow-dawn',
    runtimeRenderer: 'Flutter Image.asset; SVG is canonical source',
    decorativeSemantics: 'exclude; announce check-in success separately',
    picker: { allImmediatelySelectable: true, maxTapsFromProfileOrSettings: 2, persistenceOwner: 'release session; selected theme id in existing garden settings/sync' },
    layout: { garden: [640, 320], plantOrigin: [240, 142], birdOrigin: [366, 104] },
    seasonal: { renderedSeason: 'autumn', otherSeasons: 'same permanent selectable theme; additional seasonal variants not exported in this pack' },
    themes: productionThemes.map(theme => ({
      ...theme, motion: `assets/garden_themes/${theme.id}/motion.json`,
      contrastProof: Object.fromEntries(['light', 'dark'].map(mode => [mode,
        Object.fromEntries([['text', 'canvas'], ['text', 'surface'], ['muted', 'canvas'], ['muted', 'surface'],
          ['onAccent', 'accent'], ['accent', 'canvas'], ['accent', 'surface']].map(([fg, bg]) =>
          [`${fg}/${bg}`, Number(contrastRatio(theme.palettes[mode][fg], theme.palettes[mode][bg]).toFixed(4))])),
      ])),
      assets: Object.fromEntries(Object.keys(dimensions).map(role => [role, assetEntry(theme, role)])),
    })),
  }, null, 2) + '\n';
}

function preview(theme) {
  const p = theme.palettes[theme.defaultBrightness];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="960" height="640" viewBox="0 0 960 640">
${definitions(theme)}
<path d="M0 0H960V640H0Z" fill="${p.canvas}"/>
<g fill="${p.text}" font-family="Segoe UI, sans-serif"><text x="40" y="42" font-size="18">Budlark</text><text x="80" y="105" font-size="32" font-weight="600">Your garden</text></g>
<g transform="translate(80 132) scale(1.25)">${backgroundArt(theme)}${group('habit', plantArt(theme, 'bud'), 'translate(240 142)')}${group('companion', birdArt(theme), 'translate(366 104)')}</g>
<path d="M80 550H880V614H80Z" fill="${p.surface}"/>
<text x="104" y="590" fill="${p.text}" font-family="Segoe UI, sans-serif" font-size="23">After coffee, stretch once.</text>
<path d="M678 558H864V606H678Z" fill="${p.accent}"/>
<text x="700" y="589" fill="${p.onAccent}" font-family="Segoe UI, sans-serif" font-size="18">Mark complete</text>
</svg>
`;
}

export function generateVectors() {
  const previews = new URL('../docs/design/garden-themes/production-previews/', import.meta.url);
  mkdirSync(previews, { recursive: true });
  for (const theme of productionThemes) {
    const directory = new URL(`../assets/garden_themes/${theme.id}/`, import.meta.url);
    mkdirSync(directory, { recursive: true });
    for (const role of Object.keys(dimensions)) writeFileSync(new URL(`${role}.svg`, directory), svgAsset(theme, role));
    writeFileSync(new URL('motion.json', directory), JSON.stringify(animationSpec(theme), null, 2) + '\n');
    writeFileSync(new URL(`${theme.id}.svg`, previews), preview(theme));
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--manifest')) {
    writeFileSync(new URL('../assets/garden_themes/manifest.json', import.meta.url), renderManifest());
  } else generateVectors();
}
