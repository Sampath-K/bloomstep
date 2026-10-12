import { normalizedEvents, effectiveCheckins, addDays, timestampKey } from './dashboards.mjs';

const minimumContributors = 50;
const horizonDays = 7;
const dayPattern = /^\d{4}-\d{2}-\d{2}$/;
/** @param {string} day */
const midnight = day => Date.parse(`${day}T00:00:00Z`);
/** @param {number[]} values */
const publishable = values => values.every(value => value === 0 || value >= minimumContributors);
/** @typedef {ReturnType<typeof normalizedEvents>[number]} Observation */
/** @param {Observation} row */
const positive = row => ['did', 'didMore'].includes(String(row.record.properties?.result));
/** @param {Observation} row */
const savedHabit = row => typeof row.record.properties?.habitId === 'string';
/** @param {Observation} before @param {Observation} after */
const ordered = (before, after) => timestampKey(before.record.ts) <= timestampKey(after.record.ts);

/**
 * Account keys are the sole join boundary. Input must be the backend's bounded,
 * active-account/deleted-record-filtered projection, never anonymous web counts.
 * @param {{userId:string,record:unknown}[]} rows
 * @param {string} startDay @param {string} endDay @param {string} observedThrough
 */
export function aarrrSummary(rows, startDay, endDay, observedThrough) {
  if (![startDay, endDay, observedThrough].every(day => dayPattern.test(day) &&
      Number.isFinite(midnight(day)) && new Date(midnight(day)).toISOString().slice(0, 10) === day) ||
      startDay > endDay || endDay >= observedThrough || midnight(endDay) - midnight(startDay) > 29 * 86400000) {
    throw Error('Invalid completed AARRR window.');
  }
  const events = normalizedEvents(rows).filter(row => row.record.ts.slice(0, 10) < observedThrough);
  const inWindow = events.filter(row => row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay);
  /** @type {Map<string, Observation[]>} */
  const byAccount = new Map();
  for (const row of events) {
    const observations = byAccount.get(row.userId) ?? [];
    observations.push(row); byAccount.set(row.userId, observations);
  }
  /** @param {Observation[]} observations */
  function chain(observations) {
    const sign = observations.find(row => row.record.name === 'signin_succeeded');
    const recipes = sign ? observations.filter(row => row.record.name === 'recipe_created' && savedHabit(row) && ordered(sign, row)) : [];
    const firstRecipe = recipes[0];
    const firstPractice = observations.find(row => row.record.name === 'first_checkin' &&
      positive(row) && savedHabit(row) && typeof row.record.properties?.localDay === 'string' &&
      recipes.some(recipe => recipe.record.properties?.habitId === row.record.properties?.habitId && ordered(recipe, row)));
    return [sign, firstRecipe, firstPractice];
  }
  const chains = [...byAccount.values()].map(observations => chain(observations.filter(row =>
    row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay)));
  const counts = [0, 1, 2].map(index => chains.filter(stages => stages[index]).length);
  const safeChain = counts[0] > 0 && publishable([counts[2], counts[1] - counts[2], counts[0] - counts[1]]);
  const names = ['signin_succeeded', 'recipe_created', 'first_checkin'];
  const stages = names.map((name, index) => ({
    name, accounts: safeChain && counts[index] > 0 ? counts[index] : null,
    status: counts[index] === 0 ? 'unknown' : safeChain ? 'measured' : 'suppressed',
  }));
  const transitions = [0, 1].map(index => {
    let converted = 0, lagged = 0, pending = 0, censored = 0;
    for (const chain of chains) {
      const before = chain[index], after = chain[index + 1];
      if (!before) continue;
      const deadline = timestampKey(addDays(before.record.ts.slice(0, 10), horizonDays) + before.record.ts.slice(10));
      if (after && timestampKey(after.record.ts) <= deadline) converted++;
      else if (deadline >= timestampKey(`${observedThrough}T00:00:00Z`)) pending++;
      else if (deadline >= timestampKey(`${addDays(endDay, 1)}T00:00:00Z`)) censored++;
      else lagged++;
    }
    const eligible = counts[index];
    const safe = safeChain && eligible >= minimumContributors && publishable([converted, lagged, pending, censored]);
    return { from: names[index], to: names[index + 1], horizonDays,
      eligibleAccounts: safe ? eligible : null, convertedAccounts: safe ? converted : null,
      laggedAccounts: safe ? lagged : null, pendingAccounts: safe ? pending : null, censoredAccounts: safe ? censored : null,
      rate: safe ? converted / eligible : null, status: safe ? 'measured' : eligible === 0 ? 'unknown' : 'suppressed' };
  });
  /** @type {Map<string,string>} */
  const firstPractice = new Map();
  for (const [account, observations] of byAccount) {
    const first = chain(observations)[2];
    if (first) firstPractice.set(account, String(first.record.properties?.localDay));
  }
  const practicing = effectiveCheckins(events);
  const cohortStartDay = addDays(startDay, -30);
  const cohortDays = [...new Set([...firstPractice.values()].filter(day => day >= cohortStartDay && day <= endDay))].sort();
  const cohorts = cohortDays.map(cohortDay => {
    const eligible = new Set([...firstPractice].filter(([, day]) => day === cohortDay).map(([account]) => account));
    const retention = (/** @type {number} */ offset) => {
      const targetDay = addDays(cohortDay, offset);
      const matured = targetDay < observedThrough;
      const active = new Set(practicing.filter(row => eligible.has(row.userId) && row.record.properties?.localDay === targetDay).map(row => row.userId));
      const safe = eligible.size >= minimumContributors && publishable([active.size, eligible.size - active.size]);
      return { targetDay, eligibleAccounts: safe ? eligible.size : null,
        practicingAccounts: safe && matured ? active.size : null,
        rate: safe && matured ? active.size / eligible.size : null,
        status: !matured ? 'pending' : safe ? 'measured' : 'suppressed' };
    };
    const d1 = retention(1), d7 = retention(7), d30 = retention(30);
    // Withhold cohort totals if any mature subset is small: prevent subtraction.
    const safe = eligible.size >= minimumContributors && [d1, d7, d30].every(value => value.status !== 'suppressed');
    /** @param {ReturnType<typeof retention>} value */
    const project = value => safe ? value : { ...value, eligibleAccounts: null, practicingAccounts: null, rate: null,
      status: value.status === 'pending' ? 'pending' : 'suppressed' };
    return { cohortDay, accounts: safe ? eligible.size : null, d1: project(d1), d7: project(d7), d30: project(d30) };
  });
  const observed = (/** @type {string} */ name) => {
    const accounts = new Set(inWindow.filter(row => row.record.name === name).map(row => row.userId)).size;
    return { accounts: accounts >= minimumContributors ? accounts : null,
      status: accounts === 0 ? 'unknown' : accounts < minimumContributors ? 'suppressed' : 'measured' };
  };
  const unsupported = { accounts: null, status: 'unsupported' };
  return {
    schemaVersion: 1, unit: 'consented_account', minimumContributors,
    startDay, endDay, observedThrough,
    coverage: 'Partial opt-in observations; no all-customer ingestion watermark. Deleted accounts/records excluded by the read path; account rotation never joins. Late/offline facts revise this on-demand report. Missing facts are unknown, not failures. No production synthetic subject convention is authorized.',
    acquisition: { status: 'unsupported', accountAttributionRate: null,
      definition: 'Anonymous page-consent event counts and touch margins are a separate unit. No unique visitor denominator or automatic anonymous-to-account attribution; voluntary imported receipts are self-selected.' },
    funnel: { stages, transitions,
      definition: 'Cumulative ordered distinct accounts within the completed UTC window: observed sign-in, actually saved recipe with habit UUID, positive first_checkin after creation of that same habit. Transition rate uses eligible stage accounts and conversion within seven elapsed days. Pending = deadline beyond observation cutoff; censored = deadline outside selected window; lagged = no next observation within the horizon, never abandonment. Zero is only a mature observed eligible subset, not population absence. Small disjoint subsets suppress the whole chain/transition.' },
    retention: { cohorts, cohortStartDay,
      definition: 'First observed ordered saved activation in bounded history, not lifetime first-ever. Cohort date is reported localDay; D1/D7/D30 is effective positive check-in on exactly that local date, latest timestamp/UUID per habit/day wins. Target local date must precede observedThrough UTC date; device timezone/offset and ingestion completeness unavailable. This is an observation-cutoff heuristic, not fully matured timezone-adjusted population retention. Lookback is bounded; absent historical activation cannot be inferred.' },
    referral: { initiated: observed('share_initiated'), linkOpened: observed('invite_link_open'),
      accepted: observed('invite_accepted'), sent: { ...unsupported }, referredActivation: { ...unsupported },
      definition: 'Distinct accounts independently observed initiating share, explicitly importing invitation-view receipt, or redeeming invitation. These are separate populations, not one referral funnel. Share click is not invitation sent/delivered; link open is not accepted; no privacy-safe sender-to-activated-recipient join.' },
    revenue: { status: 'unsupported', value: null,
      definition: 'Verified payment receipts, revenue, payer conversion and lifetime value are not implemented. Reserved purchase/paywall events do not verify payment; never revenue zero.' },
    experiment: { eligible: false, reason: 'Exposure and population/guardrail completeness are unverified. Historical experiment remains OFF.' },
  };
}
