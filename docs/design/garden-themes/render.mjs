import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { themes } from './theme-model.mjs';

const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const text = (x, y, size, value, fill, weight = 400) =>
  `<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" font-weight="${weight}">${escape(value)}</text>`;
const path = (d, fill, extra = '') => `<path d="${d}" fill="${fill}" ${extra}/>`;

function bird(theme, x, y, scale = 1, singing = false) {
  const p = theme.palette;
  const humming = theme.bird === 'Hummingbird';
  const wren = theme.bird === 'Wren';
  const finch = theme.bird === 'Finch';
  return `<g data-bird="${escape(theme.bird)}" transform="translate(${x} ${y}) scale(${scale})">
    ${path(wren ? 'M-17 12 L-46-27 L-37 18 Z' : 'M-18 8 L-53 25 L-46 38 L-10 25 Z', p.bird)}
    <ellipse cx="0" cy="8" rx="${wren ? 24 : 30}" ry="22" fill="${p.bird}"/>
    <circle cx="24" cy="-13" r="19" fill="${p.bird}"/>
    ${path(humming ? 'M40-17 L74-13 L40-10 Z' : finch ? 'M39-22 L59-11 L39-5 Z' : 'M40-17 L56-11 L40-8 Z', p.bird)}
    ${path(humming ? 'M-18 6 Q-50-48-7-28 L15 7 Z' : 'M-19 1 Q-7-8 17 8 Q1 28-19 1 Z', p.wing)}
    ${theme.bird === 'Skylark' ? path('M14-28 L16-43 L24-32 L31-39 L33-28 Z', p.bird) : ''}
    <circle cx="29" cy="-17" r="3" fill="${p.detail}"/>
    <path d="M-4 27 L-3 40 L5 40 M11 27 L12 40 L20 40" fill="none" stroke="${p.bird}" stroke-width="4" stroke-linecap="round"/>
    ${singing ? `<g fill="${p.accent}"><path d="M68-45 v-24 l16-4 v24 h-4 v-18 l-8 2 v20 Z"/><ellipse cx="65" cy="-44" rx="7" ry="5"/><ellipse cx="77" cy="-48" rx="7" ry="5"/></g>` : ''}
  </g>`;
}

function plant(theme, x, y, scale = 1, stage = 'bloom') {
  const p = theme.palette;
  const stemTop = stage === 'seed' ? -12 : stage === 'sprout' ? -70 : -115;
  return `<g data-growth="${stage}" transform="translate(${x} ${y}) scale(${scale})">
    <ellipse cy="6" rx="43" ry="10" fill="${p.ground}"/>
    <path d="M0 0 Q-5-45 0 ${stemTop}" stroke="${p.plant}" stroke-width="7" fill="none" stroke-linecap="round"/>
    ${path('M-2-33 Q-52-75-51-36 Q-34-7-2-22 Z', p.plant)}
    ${path('M1-55 Q47-92 48-56 Q33-31 1-44 Z', p.plant)}
    ${stage === 'bloom' ? `<g fill="${p.bloom}"><ellipse cy="-115" rx="21" ry="31"/><ellipse cx="-21" cy="-101" rx="22" ry="18"/><ellipse cx="21" cy="-101" rx="22" ry="18"/><ellipse cy="-86" rx="23" ry="18"/></g><circle cy="-104" r="12" fill="${p.wing}"/>` : ''}
    ${stage === 'bud' ? path('M0-93 Q-35-136 0-153 Q35-136 0-93 Z', p.bloom) : ''}
  </g>`;
}

function scenery(theme, state) {
  const p = theme.palette;
  let motifs = '';
  switch (theme.id) {
    case 'meadow-dawn':
      motifs = `<circle cx="763" cy="205" r="44" fill="${p.wing}"/>
        <path d="M150 352 Q172 301 165 273 M192 352 Q210 299 204 285 M800 352 Q809 302 830 285" stroke="${p.plant}" stroke-width="3" fill="none"/>
        <g fill="${p.bird}"><ellipse cx="165" cy="275" rx="5" ry="12"/><ellipse cx="204" cy="285" rx="5" ry="12"/><ellipse cx="830" cy="285" rx="5" ry="12"/></g>`;
      break;
    case 'zen-garden':
      motifs = `<g fill="none" stroke="${p.plant}" stroke-width="2" opacity=".35">
        <path d="M100 354 Q280 293 424 355 T860 347"/><path d="M100 368 Q280 307 424 369 T860 361"/>
        <path d="M100 382 Q280 321 424 383 T860 375"/></g>
        <g fill="${p.bird}"><ellipse cx="205" cy="335" rx="41" ry="20"/><ellipse cx="250" cy="347" rx="28" ry="14"/></g>
        ${path('M781 320 L770 246 M770 266 L737 240 M770 281 L811 249', 'none', `stroke="${p.plant}" stroke-width="7"`)}
        <g fill="${p.bloom}"><circle cx="740" cy="238" r="26"/><circle cx="777" cy="230" r="31"/><circle cx="811" cy="246" r="22"/></g>`;
      break;
    case 'night-garden':
      motifs = `<circle cx="777" cy="207" r="36" fill="${p.wing}"/>
        <circle cx="792" cy="196" r="32" fill="${p.sky}"/>
        <g fill="${p.wing}">${[[171, 249], [220, 293], [297, 211], [688, 276], [827, 295], [739, 319]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="3"/>`).join('')}</g>
        ${path('M90 351 L148 241 L204 351 M735 366 L808 254 L870 366', p.ground)}`;
      break;
    case 'rain-forest':
      motifs = `<g fill="${p.plant}">${path('M92 310 Q80 167 214 206 Q179 306 92 310 Z', p.plant)}
        ${path('M825 302 Q738 186 862 171 Q899 266 825 302 Z', p.plant)}</g>
        <path d="M103 294 L184 220 M834 280 L855 197" stroke="${p.ground}" stroke-width="3"/>
        <g fill="${p.bird}">${[[250, 218], [710, 224], [779, 274]].map(([x, y]) => path(`M${x} ${y} q-12 20 0 22 q12-2 0-22`, p.bird)).join('')}</g>`;
      break;
    case 'desert-bloom':
      motifs = `<circle cx="778" cy="204" r="39" fill="${p.wing}"/>
        ${path('M84 350 Q300 259 490 358 Q687 280 876 343 L876 390 L84 390 Z', p.ground)}
        <path d="M197 345 V247 M197 291 H172 V268 M197 313 H223 V282" stroke="${p.plant}" stroke-width="19" fill="none" stroke-linecap="round"/>
        <circle cx="198" cy="240" r="14" fill="${p.bloom}"/>`;
      break;
    case 'seasonal':
      motifs = `<path d="M188 353 V239 M188 293 L147 259 M188 276 L226 240" stroke="${p.bird}" stroke-width="9" fill="none"/>
        <g fill="${p.bloom}"><ellipse cx="146" cy="248" rx="24" ry="33"/><ellipse cx="185" cy="220" rx="30" ry="38"/><ellipse cx="224" cy="238" rx="24" ry="32"/></g>
        <g fill="${p.wing}"><ellipse cx="800" cy="331" rx="19" ry="7" transform="rotate(-25 800 331)"/><ellipse cx="750" cy="356" rx="17" ry="7" transform="rotate(25 750 356)"/></g>`;
      break;
    default: throw new Error(`Unrendered theme: ${theme.id}`);
  }
  return `<rect x="64" y="144" width="832" height="252" rx="16" fill="${p.sky}"/>
    <ellipse cx="480" cy="370" rx="392" ry="30" fill="${p.ground}"/>
    ${motifs}
    ${plant(theme, 365, 364, 0.66, 'sprout')}
    ${plant(theme, 493, 365, 1, state === 'main' ? 'bud' : 'bloom')}
    ${plant(theme, 628, 367, 0.7, 'bloom')}
    <path d="M564 292 Q629 284 689 292" stroke="${p.bird}" stroke-width="6" fill="none" stroke-linecap="round"/>
    ${bird(theme, 624, 252, 0.9, state === 'completion')}
    ${state === 'return' ? `<g transform="translate(754 304)">
      <path d="M0 0 H42 V28 Q21 42 0 28 Z M42 6 Q66 4 60 22 Q55 31 42 25" fill="${p.surface}" stroke="${p.bird}" stroke-width="4"/>
      <path d="M-8 44 H56" stroke="${p.bird}" stroke-width="4" stroke-linecap="round"/>
    </g>` : ''}`;
}

export function renderSvg(theme, state) {
  const p = theme.palette;
  if (!['main', 'completion', 'return', 'icon'].includes(state)) throw new Error(`Unknown render state: ${state}`);
  const icon = state === 'icon';
  const completion = state === 'completion';
  const title = `Budlark - ${theme.name} - ${state === 'main' ? 'main window' : state}`;
  const content = icon
    ? `<rect width="256" height="256" rx="48" fill="${p.canvas}"/>
       ${plant(theme, 118, 224, 0.72, 'bud')}
       <path d="M126 132 H214" stroke="${p.plant}" stroke-width="7" stroke-linecap="round"/>
       ${bird(theme, 173, 101, 0.76)}`
    : `<rect width="960" height="640" rx="16" fill="${p.canvas}"/>
       <rect x="0" y="0" width="960" height="48" rx="16" fill="${p.surface}"/>
       ${text(24, 31, 18, 'Budlark', p.text, 650)}
       <g data-role="heading">${text(64, 107, 32, completion ? 'Nicely done' : state === 'return' ? 'Rest belongs here' : 'Your garden', p.text, 650)}</g>
       ${scenery(theme, state)}
       <rect x="64" y="420" width="832" height="137" rx="16" fill="${p.surface}"/>
       ${text(88, 494, state === 'main' ? 26 : 23, state === 'main' ? 'After coffee, stretch once.' : 'See you tomorrow after coffee', p.text, 600)}
       <g data-role="primary-action"><rect x="696" y="463" width="176" height="48" rx="10" fill="${p.accent}"/>
       ${text(716, 493, 17, completion ? 'Back to garden' : state === 'return' ? 'Close garden' : 'Mark complete', p.onAccent, 600)}</g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${icon ? 256 : 960}" height="${icon ? 256 : 640}" viewBox="0 0 ${icon ? '256 256' : '960 640'}" role="img" aria-labelledby="title description">
  <title id="title">${escape(title)}</title>
  <desc id="description">${escape(icon ? `Visible ${theme.bird.toLowerCase()} perched above a bud. Original vector concept.` : `${theme.background}. ${completion ? 'The habit bud has grown to bloom; a perched bird sings.' : state === 'return' ? 'A still bird, a grown habit and a coffee cup recall the next anchor.' : 'A calm companion accompanies the main habit action.'} Original vector concept, not a running app.`)}</desc>
  <metadata>Original deterministic Budlark proposal artwork. No third-party assets.</metadata>
  <g font-family="Segoe UI, Aptos, Calibri, sans-serif">${content}</g>
</svg>
`.replace(/[ \t]+$/gm, '');
}

const shellCss = `
:root {
  color-scheme: light;
  --cp-bg: #f7f4ef;
  --cp-bg-elevated: #fcfbf8;
  --cp-surface: #ffffff;
  --cp-surface-soft: #f5f5f5;
  --cp-border: #dedede;
  --cp-border-strong: #919191;
  --cp-text: #242424;
  --cp-text-muted: #5c5c5c;
  --cp-text-soft: #6f6f6f;
  --cp-accent: #b11f4b;
  --cp-accent-hover: #9a1a41;
  --cp-accent-soft: rgba(177, 31, 75, 0.08);
  --cp-accent-fg: #ffffff;
  --cp-success: #16a34a;
  --cp-danger: #dc2626;
  --cp-warning: #f59e0b;
  --cp-link: #0078d4;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.12);
  --cp-overlay: rgba(255, 255, 255, 0.8);
  --cp-panel: rgba(255, 255, 255, 0.86);
  --cp-panel-strong: rgba(255, 255, 255, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.55);
  --cp-highlight: rgba(177, 31, 75, 0.12);
}
html[data-theme="dark"] {
  color-scheme: dark;
  --cp-bg: #3d3b3a;
  --cp-bg-elevated: #343231;
  --cp-surface: #292929;
  --cp-surface-soft: #2e2e2e;
  --cp-border: #474747;
  --cp-border-strong: #5f5f5f;
  --cp-text: #dedede;
  --cp-text-muted: #919191;
  --cp-text-soft: #b0b0b0;
  --cp-accent: #fd8ea1;
  --cp-accent-hover: #fb7b91;
  --cp-accent-soft: rgba(253, 142, 161, 0.14);
  --cp-accent-fg: #1a1a1a;
  --cp-success: #4ade80;
  --cp-danger: #f87171;
  --cp-warning: #fbbf24;
  --cp-link: #4da6ff;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.32);
  --cp-overlay: rgba(41, 41, 41, 0.88);
  --cp-panel: rgba(41, 41, 41, 0.72);
  --cp-panel-strong: rgba(41, 41, 41, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.04);
  --cp-highlight: rgba(253, 142, 161, 0.12);
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--cp-bg); color: var(--cp-text); font: 16px/1.5 "Segoe UI", Aptos, Calibri, -apple-system, BlinkMacSystemFont, sans-serif; }
main { max-width: 1600px; margin: auto; padding: 32px; }
h1 { margin: 8px 0; font-size: 36px; line-height: 1.2; }
h2 { margin: 0; font-size: 24px; }
p { margin: 8px 0 16px; }
a { color: var(--cp-link); }
a:focus-visible { outline: 3px solid var(--cp-accent); outline-offset: 4px; }
header { max-width: 960px; margin-bottom: 32px; }
.badge { color: var(--cp-accent); font-weight: 700; text-transform: uppercase; letter-spacing: .08em; font-size: 12px; }
.note, figcaption { color: var(--cp-text-muted); }
nav { display: flex; flex-wrap: wrap; gap: 16px; margin: 24px 0; }
section { border: 1px solid var(--cp-border); border-radius: 16px; background: var(--cp-surface); padding: 24px; margin: 24px 0; }
.grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; align-items: start; }
.theme-heading { display: flex; gap: 24px; justify-content: space-between; align-items: start; margin-bottom: 20px; }
.icon { width: 96px; flex-shrink: 0; }
figure { margin: 0; min-width: 0; }
img { display: block; width: 100%; height: auto; border: 1px solid var(--cp-border); border-radius: 10px; }
figcaption { margin-top: 8px; font-size: 14px; }
.small { width: 32px; height: 32px; border: 0; border-radius: 4px; margin-top: 16px; }
.legend { padding: 16px; background: var(--cp-accent-soft); border-left: 4px solid var(--cp-accent); border-radius: 10px; }
footer { color: var(--cp-text-muted); padding: 16px 0; }
@media (max-width: 1000px) { .grid { grid-template-columns: 1fr 1fr; } .icon { max-width: 168px; } }
@media (max-width: 680px) { main { padding: 16px; } section { padding: 16px; } .grid { grid-template-columns: 1fr; } h1 { font-size: 28px; } }
`;

export function renderContactSheet() {
  const image = (theme, state, className = '') => `<img ${className ? `class="${className}" ` : ''}width="${state === 'icon' ? 256 : 960}" height="${state === 'icon' ? 256 : 640}" src="data:image/svg+xml;base64,${Buffer.from(renderSvg(theme, state)).toString('base64')}" alt="${escape(`${theme.name}: ${state === 'completion' ? 'completion singing keyframe' : state === 'return' ? 'return cue with coffee cup' : state === 'icon' ? 'bird and bud icon' : 'minimal main garden window'}`)}">`;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Budlark garden themes - design review</title>
<script>
  (() => {
    const param = new URLSearchParams(window.location.search).get("scoutTheme");
    const theme =
      param || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
<style>${shellCss}</style></head>
<body><main><header><div class="badge">Approved theme direction / asset review / not released</div>
<h1>A bud to grow. A bird to celebrate.</h1>
<p>The habit grows from seed to bloom. Your companion lands, sings for one second and rests. All six themes are immediately selectable. No lost growth, no streak pressure, no shopping.</p>
<p class="note">24 original SVG concepts, not app screenshots. Each main frame has one heading, one action and nine visible words. Compare completion growth, the one-second song and a calm return cue across six settings.</p>
<nav aria-label="Theme families">${themes.map(t => `<a href="#${t.id}">${t.name}</a>`).join('')}</nav>
<p class="legend">Motion equivalent: with app or OS reduced motion, use a still perched bird and the same success text. Sound is off by default. All fireflies, rain and leaves are static.</p></header>
<section id="production" aria-labelledby="production-title"><h2 id="production-title">Production asset compositions</h2>
<p class="note">Refined original vector layers, rendered with the supplied high-DPI pack. These are composition previews, not the running Flutter app. The earlier journey and icon concepts follow below.</p>
<div class="grid">${themes.map(t => `<figure><img width="960" height="640" src="data:image/png;base64,${readFileSync(new URL(`./production-previews/${t.id}.png`, import.meta.url)).toString('base64')}" alt="${t.name}: refined production asset composition"><figcaption>${t.name} / all six included immediately</figcaption></figure>`).join('')}</div></section>
${themes.map(t => `<section id="${t.id}" aria-labelledby="${t.id}-title">
<div class="theme-heading"><div><h2 id="${t.id}-title">${t.name}</h2>
<p class="note">${t.bird} / ${t.unlockDays === 0 ? 'Included from the start' : `${t.unlockDays} lifetime practice days; need not be consecutive; never revoked or sold`}<br>${escape(t.background)}</p>
</div><figure class="icon">${image(t, 'icon')}<figcaption>${t.id === 'meadow-dawn' ? 'App mark proposal' : 'Theme badge'}</figcaption>${image(t, 'icon', 'small')}<figcaption>32px study</figcaption></figure></div>
<div class="grid">
<figure>${image(t, 'main')}<figcaption>Main / nine words, one heading, one action</figcaption></figure>
<figure>${image(t, 'completion')}<figcaption>Complete / bud to bloom, lark lands and sings for 1s; reduced motion uses this still frame</figcaption></figure>
<figure>${image(t, 'return')}<figcaption>Return / a still coffee-cup cue for the next anchor, not another task</figcaption></figure>
</div></section>`).join('\n')}
<footer>Owner-approved P15: all six themes are available immediately, with Meadow Dawn as default. No milestone gates or purchases. Seasonal artwork shows autumn. Native accessibility, reduced-motion behavior and small-icon legibility still require implementation review.</footer>
</main></body></html>
`;
}

export function generate() {
  for (const theme of themes) {
    for (const state of ['main', 'completion', 'return', 'icon']) {
      writeFileSync(new URL(`./${theme.id}-${state}.svg`, import.meta.url), renderSvg(theme, state));
    }
  }
  writeFileSync(new URL('./contact-sheet.html', import.meta.url), renderContactSheet());
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) generate();
