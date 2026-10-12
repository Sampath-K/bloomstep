// Shared, dependency-free website experiment policy. Bundled into the customer page and used by the API,
// so assignment, catalog content and definition hashes are computed identically on both sides.

export const POLICY_VERSION = 'bloomstep-web-experiments/v1';
/** Unit = one consented page visit (page memory only). Reloads/new tabs are new units; not a person. */
export const ATTRIBUTION_VERSION = 'web-consented-visit/v1';
export const OUTCOMES = /** @type {const} */ (['primary_cta_click', 'download_click']);
export const ARMS = /** @type {const} */ (['control', 'candidate']);

/** Only these page surfaces may ever vary. Download links, installer help, consent, receipts, privacy,
 * sign-in, security and payment copy are deliberately not representable. */
export const SURFACES = Object.freeze({
  hero_cta_label: Object.freeze({ selector: '#primary-cta', kind: 'text', maxLength: 48 }),
  download_heading: Object.freeze({ selector: '#download-title', kind: 'text', maxLength: 80 }),
  hero_note_position: Object.freeze({ selector: '.hero .small', kind: 'position', values: ['after_cta', 'before_cta'] }),
});

const bannedClaims = /\b(?:proven|prove[sn]?|guarantee[ds]?|clinical(?:ly)?|scien(?:ce|tific(?:ally)?)|research|stud(?:y|ies)|doctor|cure[sd]?|heal|therapy|treat(?:ment)?|best|#1|number one|instant(?:ly)?|forever|safe|secure|signed|verified|virus|malware|warning|smartscreen|account|sign[ -]?in|password|pay(?:ment)?|price|subscription|consent|privacy|track(?:ing)?|streak|don't miss|last chance|hurry|only today|limited time)\b|\d\s*%|!/i;

/** Finite curated catalog: truthful, low-risk wording/layout only. Primary metric is download intent per
 * consented visit, never the clicked button itself; button clicks are secondary diagnostics only. */
export const CATALOG = Object.freeze([
  Object.freeze({
    key: 'download-heading-v1',
    stage: Object.freeze({ from: 'primary_cta_click', to: 'download_click' }),
    surface: 'download_heading',
    hypothesis: 'Visitors who reach the download section more often start the download when its heading plainly names the action instead of a garden metaphor.',
    control: Object.freeze({ id: 'garden-heading', value: 'Bring a tiny garden to your Windows day.' }),
    candidate: Object.freeze({ id: 'plain-heading', value: 'Download Bloomstep for your Windows PC.' }),
  }),
  Object.freeze({
    key: 'hero-cta-label-v1',
    stage: Object.freeze({ from: 'landing_view', to: 'primary_cta_click' }),
    surface: 'hero_cta_label',
    hypothesis: 'Saying the main button leads to the free Windows download sets an accurate expectation and increases download intent per consented visit.',
    control: Object.freeze({ id: 'get-label', value: 'Get Bloomstep for Windows' }),
    candidate: Object.freeze({ id: 'see-download-label', value: 'See the free Windows download' }),
  }),
  Object.freeze({
    key: 'hero-note-position-v1',
    stage: Object.freeze({ from: 'landing_view', to: 'primary_cta_click' }),
    surface: 'hero_note_position',
    hypothesis: 'Showing the free preview facts before the main button sets expectations earlier and increases download intent per consented visit.',
    control: Object.freeze({ id: 'note-after', value: 'after_cta' }),
    candidate: Object.freeze({ id: 'note-before', value: 'before_cta' }),
  }),
]);

/** Pre-registered design shared by every catalog entry (frozen into each instance hash). */
export const DESIGN = Object.freeze({
  primaryMetric: 'download_click',
  secondaryMetrics: Object.freeze(['primary_cta_click']),
  allocation: Object.freeze({ control: 5000, candidate: 5000 }),
  horizonDays: 14,
  minSamplePerArm: 400,
  minExpectedCell: 10,
  maxSubjectsPerArm: 5000,
  alpha: 0.05,
  method: 'fixed-horizon two-sided two-proportion z test, single final analysis at endAt',
  harm: Object.freeze({
    looksAtFraction: Object.freeze([0.25, 0.5, 0.75]),
    alphaPerLook: 0.001,
    method: 'Bonferroni-bounded one-sided harm-only interim looks (max 3 × 0.001); interim looks can only stop for harm, never promote',
  }),
  srmAlpha: 0.001,
  maxVariantErrorRate: 0.02,
  minExposedForOperationalGuardrail: 50,
  unobservable: Object.freeze(['install_completed', 'first_launch', 'activation', 'retention']),
});

/** @param {unknown} value @returns {string} */
export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(/** @type {Record<string,unknown>} */ (value)[key])}`).join(',')}}`;
  }
  if (typeof value === 'number' && !Number.isFinite(value)) throw Error('Non-finite number in canonical JSON.');
  return JSON.stringify(value);
}

/** @param {string} text */
export async function sha256Hex(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
  return [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

export async function policyHash() {
  return sha256Hex(canonicalJson({ POLICY_VERSION, ATTRIBUTION_VERSION, SURFACES, CATALOG, DESIGN }));
}

/** @typedef {typeof CATALOG[number]} CatalogEntry */
/** @param {CatalogEntry} entry @returns {string[]} problems */
export function lintEntry(entry) {
  const problems = [];
  const surface = /** @type {Record<string, {kind:string,maxLength?:number,values?:string[]}>} */ (SURFACES)[entry.surface];
  if (!surface) return [`${entry.key}: surface not allowed`];
  if (!['landing_view', 'primary_cta_click'].includes(entry.stage.from) || !OUTCOMES.includes(/** @type {any} */ (entry.stage.to))) problems.push(`${entry.key}: unknown stage`);
  if (String(entry.control.value) === String(entry.candidate.value)) problems.push(`${entry.key}: arms identical`);
  for (const arm of [entry.control, entry.candidate]) {
    if (surface.kind === 'text') {
      if (typeof arm.value !== 'string' || !arm.value.trim() || arm.value.length > Number(surface.maxLength) || /[<>&"]/.test(arm.value)) problems.push(`${entry.key}: invalid text ${arm.id}`);
      if (bannedClaims.test(arm.value)) problems.push(`${entry.key}: unsubstantiated or protected claim in ${arm.id}`);
    } else if (!surface.values?.includes(arm.value)) problems.push(`${entry.key}: invalid position ${arm.id}`);
  }
  if (bannedClaims.test(entry.hypothesis.replace(/download/gi, ''))) problems.push(`${entry.key}: hypothesis makes a protected claim`);
  return problems;
}

/** @param {string} key */
export function catalogEntry(key) {
  return CATALOG.find(entry => entry.key === key) ?? null;
}

/** @param {CatalogEntry} entry @param {{startAt:string, environment:'production'|'isolated'}} options */
export async function freezeInstance(entry, { startAt, environment }) {
  const problems = lintEntry(entry);
  if (problems.length) throw Error(problems.join('; '));
  const start = Date.parse(startAt);
  if (!Number.isFinite(start) || new Date(start).toISOString() !== startAt) throw Error('startAt must be an exact UTC ISO timestamp.');
  const horizon = DESIGN.horizonDays * 86400000;
  const body = {
    schemaVersion: 1, policyVersion: POLICY_VERSION, attributionVersion: ATTRIBUTION_VERSION, environment,
    experimentId: `${entry.key}.${startAt.replace(/[-:.]/g, '').slice(0, 15)}`,
    key: entry.key, hypothesis: entry.hypothesis, stage: entry.stage, surface: entry.surface,
    arms: { control: entry.control, candidate: entry.candidate },
    design: DESIGN, startAt, endAt: new Date(start + horizon).toISOString(),
    harmLookAt: DESIGN.harm.looksAtFraction.map(fraction => new Date(start + horizon * fraction).toISOString()),
    catalogPolicyHash: await policyHash(),
  };
  return { ...body, definitionHash: await sha256Hex(canonicalJson(body)) };
}
/** @typedef {Awaited<ReturnType<typeof freezeInstance>>} Instance */

/** Verifies the instance is unmodified AND still equals the bundled catalog entry (no injected content).
 * @param {unknown} value @returns {Promise<boolean>} */
export async function verifyInstance(value) {
  if (!value || typeof value !== 'object') return false;
  const { definitionHash, ...body } = /** @type {Instance} */ (value);
  if (typeof definitionHash !== 'string') return false;
  const entry = catalogEntry(String(body.key));
  if (!entry || canonicalJson(body.arms) !== canonicalJson({ control: entry.control, candidate: entry.candidate }) ||
      body.surface !== entry.surface || canonicalJson(body.design) !== canonicalJson(DESIGN) ||
      body.policyVersion !== POLICY_VERSION || body.attributionVersion !== ATTRIBUTION_VERSION ||
      body.catalogPolicyHash !== await policyHash()) return false;
  try { return await sha256Hex(canonicalJson(body)) === definitionHash; } catch { return false; }
}

/** Deterministic assignment for an eligible consented visit. @param {Instance} instance @param {string} subjectId */
export async function assignArm(instance, subjectId) {
  const digest = await sha256Hex(`${instance.experimentId}:${instance.definitionHash}:${subjectId}`);
  const bucket = parseInt(digest.slice(0, 8), 16) % 10000;
  return bucket < instance.design.allocation.control ? 'control' : 'candidate';
}

/** @param {string} subjectId */
export function subjectHash(subjectId) { return sha256Hex(`bloomstep-visit:${subjectId}`); }

/** Eligibility is explicit: consent on, no browser privacy signal, live experiment, not killed.
 * @param {{consent:boolean, dnt?:string|null, gpc?:boolean, killed?:boolean, enabled?:boolean}} input */
export function eligibility({ consent, dnt, gpc, killed, enabled }) {
  if (dnt === '1' || gpc === true) return { eligible: false, reason: 'privacy_signal' };
  if (!consent) return { eligible: false, reason: 'no_consent' };
  if (killed) return { eligible: false, reason: 'killed' };
  if (enabled === false) return { eligible: false, reason: 'disabled' };
  return { eligible: true, reason: null };
}

// ---------- statistics ----------
/** Abramowitz–Stegun 7.1.26 (|error| < 1.5e-7). @param {number} z */
export function normalCdf(z) {
  const x = Math.abs(z) / Math.SQRT2, t = 1 / (1 + 0.3275911 * x);
  const erf = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
  return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2;
}
/** @param {number} x chi-square statistic with 1 df */
export function chiSquare1Survival(x) { return 2 * (1 - normalCdf(Math.sqrt(Math.max(0, x)))); }

/** @typedef {{exposed:number, converted:{primary_cta_click:number, download_click:number}, errors:number}} ArmCounts */
/** @typedef {{control:ArmCounts, candidate:ArmCounts}} Counts */
/** Returns null when normal approximation would be misused (any expected success/failure cell < minimum).
 * @param {number} x0 @param {number} n0 @param {number} x1 @param {number} n1 @param {number} minCell */
export function twoProportion(x0, n0, x1, n1, minCell) {
  if (![x0, n0, x1, n1].every(value => Number.isInteger(value) && value >= 0) || x0 > n0 || x1 > n1) throw Error('Invalid counts.');
  if (!n0 || !n1) return null;
  const pooled = (x0 + x1) / (n0 + n1);
  const cells = [n0 * pooled, n0 * (1 - pooled), n1 * pooled, n1 * (1 - pooled), x0, n0 - x0, x1, n1 - x1];
  if (cells.some(cell => cell < minCell)) return null;
  const p0 = x0 / n0, p1 = x1 / n1;
  const se = Math.sqrt(pooled * (1 - pooled) * (1 / n0 + 1 / n1));
  const z = (p1 - p0) / se;
  const seDiff = Math.sqrt(p0 * (1 - p0) / n0 + p1 * (1 - p1) / n1);
  return { p0, p1, diff: p1 - p0, z, pTwoSided: 2 * (1 - normalCdf(Math.abs(z))), pHarmOneSided: normalCdf(z),
    ci95: [p1 - p0 - 1.959964 * seDiff, p1 - p0 + 1.959964 * seDiff] };
}

/** @param {Counts} counts @param {{control:number,candidate:number}} allocation */
export function sampleRatio(counts, allocation) {
  const n = counts.control.exposed + counts.candidate.exposed, share = allocation.control / (allocation.control + allocation.candidate);
  if (n < 100) return null;
  const e0 = n * share, e1 = n - e0;
  const statistic = (counts.control.exposed - e0) ** 2 / e0 + (counts.candidate.exposed - e1) ** 2 / e1;
  return { statistic, p: chiSquare1Survival(statistic) };
}

/** @param {unknown} counts @returns {counts is Counts} */
export function validCounts(counts) {
  const arm = (/** @type {any} */ value) => value && Number.isInteger(value.exposed) && value.exposed >= 0 && Number.isInteger(value.errors) &&
    value.errors >= 0 && value.errors <= value.exposed && OUTCOMES.every(name => Number.isInteger(value.converted?.[name]) &&
    value.converted[name] >= 0 && value.converted[name] <= value.exposed);
  return !!counts && typeof counts === 'object' && arm(/** @type {any} */ (counts).control) && arm(/** @type {any} */ (counts).candidate);
}

/**
 * Pure decision function. Promotion is only possible at the single final analysis.
 * @param {Instance} instance @param {unknown} counts @param {Date} now @param {number[]} looksDone
 * @returns {Promise<{status:string, terminal:boolean, promote:boolean, rollback:boolean, look?:number, stats?:unknown, reason:string}>}
 */
export async function evaluate(instance, counts, now, looksDone = []) {
  const done = (/** @type {string} */ status, /** @type {string} */ reason, extra = {}) =>
    ({ status, terminal: true, promote: false, rollback: status !== 'insufficient' && status !== 'no_data' && status !== 'inconclusive' && status !== 'candidate_worse', reason, ...extra });
  if (!await verifyInstance(instance)) return done('error_invalid_definition', 'Definition hash or catalog binding failed; control restored.');
  if (!validCounts(counts)) return done('error_invalid_counts', 'Persisted counts unreadable; no inference made, control restored.');
  const design = instance.design, total = counts.control.exposed + counts.candidate.exposed;
  for (const arm of ARMS) {
    const value = counts[arm];
    if (value.exposed >= design.minExposedForOperationalGuardrail && value.errors / value.exposed > design.maxVariantErrorRate) {
      return done('rollback_variant_errors', `${arm} variant application error rate exceeded ${design.maxVariantErrorRate}.`);
    }
  }
  const srm = sampleRatio(counts, design.allocation);
  if (srm && srm.p < design.srmAlpha) return done('invalid_sample_ratio', 'Sample ratio mismatch; assignment or exposure logging is unreliable.', { stats: srm });
  const atFinal = now.getTime() >= Date.parse(instance.endAt);
  const metric = (/** @type {'control'|'candidate'} */ arm) => counts[arm].converted.download_click;
  if (!atFinal) {
    const due = instance.harmLookAt.map((at, index) => ({ at, index })).filter(look => Date.parse(look.at) <= now.getTime() && !looksDone.includes(look.index));
    if (!due.length) return { status: 'running', terminal: false, promote: false, rollback: false, reason: 'No pre-registered look due; no statistics computed.' };
    const look = due[due.length - 1].index;
    const stats = twoProportion(metric('control'), counts.control.exposed, metric('candidate'), counts.candidate.exposed, design.minExpectedCell);
    if (stats && stats.diff < 0 && stats.pHarmOneSided < design.harm.alphaPerLook) {
      return done('rollback_harm', `Harm boundary crossed at pre-registered look ${look + 1}.`, { look, stats });
    }
    return { status: 'running', terminal: false, promote: false, rollback: false, look,
      reason: stats ? `Harm look ${look + 1}: no harm boundary crossed; efficacy is never tested before endAt.` : `Harm look ${look + 1}: insufficient cells; continuing.` };
  }
  if (!total) return done('no_data', 'No consented exposures by endAt; control retained, nothing promoted.');
  if (counts.control.exposed < design.minSamplePerArm || counts.candidate.exposed < design.minSamplePerArm) {
    return done('insufficient', `Fewer than ${design.minSamplePerArm} exposed visits in an arm; control retained.`);
  }
  const stats = twoProportion(metric('control'), counts.control.exposed, metric('candidate'), counts.candidate.exposed, design.minExpectedCell);
  if (!stats) return done('insufficient', `Expected success/failure cells below ${design.minExpectedCell}; normal approximation not valid; control retained.`);
  if (stats.pTwoSided < design.alpha && stats.diff > 0) {
    return { status: 'promote', terminal: true, promote: true, rollback: false, stats,
      reason: 'Final fixed-horizon analysis: candidate download intent per consented visit higher at α=0.05; activation remains unobservable.' };
  }
  if (stats.pTwoSided < design.alpha) return done('candidate_worse', 'Candidate significantly lower at final analysis; control retained.', { stats });
  return done('inconclusive', 'No significant difference at final analysis; control retained.', { stats });
}

/**
 * Prioritization only (never evaluation): weakest publishable website step, then first unrun catalog entry.
 * @param {{steps?:{from:string,to:string,rate:number|null}[]}|null} summary @param {string[]} concludedKeys @param {string[]} promotedSurfaces
 */
export function selectNext(summary, concludedKeys, promotedSurfaces) {
  const steps = summary?.steps;
  if (!Array.isArray(steps) || !steps.length) return { status: 'no_data', entry: null, stage: null };
  if (steps.some(step => typeof step.rate !== 'number' || !Number.isFinite(step.rate))) return { status: 'insufficient_data', entry: null, stage: null };
  const ordered = [...steps].sort((a, b) => Number(a.rate) - Number(b.rate));
  for (const step of ordered) {
    const entry = CATALOG.find(item => item.stage.from === step.from && item.stage.to === step.to &&
      !concludedKeys.includes(item.key) && !promotedSurfaces.includes(item.surface));
    if (entry) return { status: 'selected', entry, stage: step, weakest: ordered[0] };
  }
  return { status: 'catalog_exhausted', entry: null, stage: ordered[0] };
}

// ---------- page application (browser) and build-time promotion ----------
/** @param {Document} document @param {string} surfaceKey @param {string} from @param {string} to */
export function applyVariant(document, surfaceKey, from, to) {
  const surface = /** @type {Record<string,{selector:string,kind:string}>} */ (SURFACES)[surfaceKey];
  const node = surface && document.querySelector(surface.selector);
  if (!node) throw Error('Experiment surface missing.');
  if (surface.kind === 'text') {
    if (node.textContent !== from && node.textContent !== to) throw Error('Experiment surface no longer matches the reviewed copy.');
    node.textContent = to;
    return;
  }
  const cta = document.getElementById('primary-cta')?.parentElement;
  if (!cta || cta.parentElement !== node.parentElement) throw Error('Experiment layout anchor missing.');
  if (to === 'before_cta') cta.before(node); else cta.after(node);
}

/** Build-time promotion of concluded winners (never applied at runtime for unconsented visitors).
 * @param {string} html @param {{key:string, experimentId:string, definitionHash:string, decision:string}[]} promotions */
export function applyPromotionsToHtml(html, promotions) {
  let output = html;
  for (const promotion of promotions) {
    const entry = catalogEntry(promotion.key);
    if (!entry || promotion.decision !== 'promote' || !/^[a-f0-9]{64}$/.test(promotion.definitionHash) ||
        !promotion.experimentId?.startsWith(`${entry.key}.`)) throw Error('Invalid experiment promotion record.');
    const before = output;
    if (entry.surface === 'hero_cta_label') {
      const control = `id="primary-cta" href="#download">${entry.control.value}</a>`, candidate = `id="primary-cta" href="#download">${entry.candidate.value}</a>`;
      if (output.includes(candidate)) continue;
      output = output.replace(control, candidate);
    } else if (entry.surface === 'download_heading') {
      const control = `<h2 id="download-title">${entry.control.value}</h2>`, candidate = `<h2 id="download-title">${entry.candidate.value}</h2>`;
      if (output.includes(candidate)) continue;
      output = output.replace(control, candidate);
    } else {
      if (/<p class="small">[^\n]*<\/p>\s*<p><a class="button" id="primary-cta"/.test(output)) continue;
      output = output.replace(/(\s*<p><a class="button" id="primary-cta"[^\n]*<\/p>)(\s*<p class="small">[^\n]*<\/p>)/, '$2$1');
    }
    if (before === output) throw Error(`Promotion ${promotion.key} did not match the reviewed control markup.`);
  }
  return output;
}
