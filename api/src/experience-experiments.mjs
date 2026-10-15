import { createHash } from 'node:crypto';
import { eventSchema } from './contracts.mjs';
import { canonicalJson, twoProportion, chiSquare1Survival } from './experiment-policy.mjs';
import { experiencePolicy, experiencePolicyHash } from './experience-policy.g.mjs';
export { experiencePolicy, experiencePolicyHash };

/** @typedef {{userId:string, record:unknown}} Row */
/** @typedef {{study:string,version:number,startAt:string,policyHash:string}} Plan */
/** @typedef {{syntheticOnly:boolean,accessibility:string,optOut:string,burden:string,errors:string,captureComplete:boolean}} Evidence */
const DAY = 86400000;
const hash = (/** @type {unknown} */ value) => createHash('sha256').update(canonicalJson(value)).digest('hex');

/** Closed-schema deduplication; identity stays inside the authenticated account aggregate.
 * @param {Row[]} rows */
function observations(rows) {
  const unique = new Map();
  let invalid = false;
  for (const row of rows) {
    if (!row.record || typeof row.record !== 'object' || !('name' in row.record)
        || row.record.name !== 'experience_observation') continue;
    const parsed = eventSchema.safeParse(row.record);
    if (!parsed.success) { invalid = true; continue; }
    const key = `${row.userId}:${parsed.data.id}`;
    const value = { userId: row.userId, record: parsed.data };
    if (unique.has(key) && canonicalJson(unique.get(key)) !== canonicalJson(value)) invalid = true;
    unique.set(key, value);
  }
  return { events: [...unique.values()].sort((a, b) => a.record.ts.localeCompare(b.record.ts) || a.record.id.localeCompare(b.record.id)), invalid };
}

/** @param {Row[]} rows @param {Plan} plan @param {string} observedThrough @param {Evidence | null} evidence */
export function evaluateExperience(rows, plan, observedThrough, evidence = null) {
  if (!experiencePolicy.catalog.some(e => e.id === plan.study) || plan.policyHash !== experiencePolicyHash ||
      !Number.isInteger(plan.version) || plan.version < 1 || !Number.isFinite(Date.parse(plan.startAt)) ||
      new Date(plan.startAt).toISOString() !== plan.startAt || !Number.isFinite(Date.parse(observedThrough))) {
    throw Error('Invalid frozen app experience plan.');
  }
  const end = Date.parse(plan.startAt) + experiencePolicy.design.enrollmentDays * DAY;
  const finalAt = end + (experiencePolicy.design.followupDays + experiencePolicy.design.lateArrivalDays) * DAY;
  const { events, invalid } = observations(rows);
  const selected = events.filter(r => r.record.properties?.experienceStudy === plan.study &&
    r.record.properties?.configVersion === plan.version);
  /** @type {Map<string, typeof selected>} */
  const units = new Map();
  const owners = new Map();
  let contaminated = invalid;
  for (const row of selected) {
    const p = row.record.properties;
    const key = `${row.userId}:${p?.consentEpoch}:${p?.cohortId}`;
    if (owners.has(row.userId) && owners.get(row.userId) !== key) contaminated = true;
    owners.set(row.userId, key);
    const group = units.get(key) ?? [];
    group.push(row);
    units.set(key, group);
  }
  const counts = {
    control: { exposed: 0, followed: 0, practice: 0, task: 0, error: 0, burden: 0 },
    candidate: { exposed: 0, followed: 0, practice: 0, task: 0, error: 0, burden: 0 },
  };
  for (const group of units.values()) {
    const arms = new Set(group.map(r => r.record.properties?.experienceArm));
    const exposures = group.filter(r => r.record.properties?.experienceOutcome === 'rendered');
    if (arms.size !== 1 || exposures.length !== 1) { contaminated = true; continue; }
    const exposure = exposures[0], at = Date.parse(exposure.record.ts);
    if (at < Date.parse(plan.startAt) || at >= end) { contaminated = true; continue; }
    const arm = counts[/** @type {'control'|'candidate'} */ (exposure.record.properties?.experienceArm)];
    arm.exposed++;
    const outcomes = new Set();
    for (const row of group) {
      const outcome = row.record.properties?.experienceOutcome, ts = Date.parse(row.record.ts);
      if (ts < at || ts > Date.parse(observedThrough)) { contaminated = true; continue; }
      if (outcomes.has(outcome)) { contaminated = true; continue; }
      outcomes.add(outcome);
      if (['practice', 'followup'].includes(String(outcome)) &&
          (ts < at + 7 * DAY || ts > at + 14 * DAY)) contaminated = true;
      if (outcome === 'task_completed' && ts > at + DAY) contaminated = true;
    }
    if (outcomes.has('practice') && !outcomes.has('followup')) contaminated = true;
    if (outcomes.has('followup')) arm.followed++;
    if (outcomes.has('practice')) arm.practice++;
    if (outcomes.has('task_completed')) arm.task++;
    if (outcomes.has('error')) arm.error++;
    if (outcomes.has('burden')) arm.burden++;
  }
  const c = counts.control, t = counts.candidate;
  const total = c.exposed + t.exposed;
  const suppressed = c.exposed < 50 || t.exposed < 50;
  const srmP = total ? chiSquare1Survival((c.exposed - total / 2) ** 2 / (total / 2) +
    (t.exposed - total / 2) ** 2 / (total / 2)) : null;
  const test = !suppressed ? twoProportion(c.practice, c.exposed, t.practice, t.exposed, 10) : null;
  const lift = c.exposed && t.exposed ? t.practice / t.exposed - c.practice / c.exposed : null;
  const se = c.exposed && t.exposed
    ? Math.sqrt((c.practice / c.exposed) * (1 - c.practice / c.exposed) / c.exposed +
      (t.practice / t.exposed) * (1 - t.practice / t.exposed) / t.exposed) : null;
  const lowerLift = lift !== null && se !== null ? lift - 2.241403 * se : null;
  let decision = 'inconclusive', reason = 'insufficient_sample';
  if (!total) reason = 'no_data';
  else if (contaminated) reason = 'contamination';
  else if (Date.parse(observedThrough) < finalAt) reason = 'not_final';
  else if (c.exposed < 2000 || t.exposed < 2000) reason = 'insufficient_sample';
  else if (srmP !== null && srmP < .001) reason = 'sample_ratio_mismatch';
  else if (c.followed !== c.exposed || t.followed !== t.exposed) reason = 'missing_followup';
  else if (!evidence?.captureComplete || evidence.accessibility !== 'pass' || evidence.optOut !== 'observed' ||
      evidence.burden !== 'observed' || evidence.errors !== 'observed') reason = 'guardrails_unobservable';
  else if (t.error / t.exposed > c.error / c.exposed + .01 || t.burden / t.exposed > c.burden / c.exposed ||
      t.task / t.exposed < c.task / c.exposed - .02 || lift !== null && lift < -.05) {
    decision = 'rollback_harm'; reason = 'harm_or_task_guardrail';
  } else if (test && lowerLift !== null && lowerLift > .05 && test.pTwoSided < .025) {
    decision = evidence.syntheticOnly ? 'candidate_review' : 'inconclusive';
    reason = evidence.syntheticOnly ? 'isolated_lift_only' : 'production_evidence_not_source_approved';
  } else { decision = 'retain_control'; reason = test ? 'no_practically_certain_lift' : 'uncertainty'; }
  const body = {
    schemaVersion: 1, kind: 'app-experience-decision', policyHash: experiencePolicyHash,
    plan, observedThrough, finalAt: new Date(finalAt).toISOString(), decision, reason,
    syntheticOnly: evidence?.syntheticOnly === true, productionEligible: false, promotion: null,
    rollback: { arm: 'control', activation: 'existing reviewed build/release gates only' },
    counts: suppressed ? null : counts,
    statistics: suppressed ? null : { ...test, lift, lowerLift, srmP, alpha: .025 },
    evidenceHash: evidence ? hash(evidence) : null,
    inputHash: hash(selected.map(row => hash(row)).sort()),
    limitations: ['Installation units are not people; no cross-device linkage.',
      'No missing-followup abandonment inference; opt-out cannot be inferred from absence.',
      'Synthetic recommendations never authorize production promotion.'],
  };
  return { ...body, receiptHash: hash(body) };
}

/** @param {Row[]} rows @param {string} startDay @param {string} endDay */
export function experienceObservationSummary(rows, startDay, endDay) {
  const { events, invalid } = observations(rows);
  return {
    policyHash: experiencePolicyHash, productionEnabled: false, minimumCohort: 50,
    studies: experiencePolicy.catalog.map(study => {
      const selected = events.filter(r => r.record.properties?.experienceStudy === study.id &&
        r.record.ts.slice(0, 10) >= startDay && r.record.ts.slice(0, 10) <= endDay);
      const exposed = new Set(selected.filter(r => r.record.properties?.experienceOutcome === 'rendered')
        .map(r => `${r.userId}:${r.record.properties?.cohortId}`));
      return { study: study.id, exposedUnits: exposed.size >= 50 ? exposed.size : null,
        decision: 'inconclusive', reason: invalid ? 'invalid_observations' : 'no_source_approved_plan_or_guardrail_completeness' };
    }),
    definition: 'Consented installation/account-scope observations, not unique people, web visits or referral deliveries. Fifty is a privacy floor, not power. No production winner is enabled.',
  };
}
