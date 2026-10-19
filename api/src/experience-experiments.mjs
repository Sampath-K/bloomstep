import { eventSchema } from './contracts.mjs';
import { experiencePolicy, experiencePolicyHash } from './experience-policy.g.mjs';
export { experiencePolicy, experiencePolicyHash };

/** Observation-only status. Statistical analysis belongs to the selected GrowthBook provider.
 * @param {{userId:string,record:any}[]} rows @param {string} startDay @param {string} endDay */
export function experienceObservationSummary(rows, startDay, endDay) {
  let invalid = false;
  const events = rows.filter(row => {
    if (row.record?.name !== 'experience_observation') return false;
    if (!eventSchema.safeParse(row.record).success) { invalid = true; return false; }
    return row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay;
  });
  return {
    policyHash: experiencePolicyHash, provider: 'growthbook',
    productionEnabled: false, minimumCohort: 50,
    studies: experiencePolicy.catalog.map(study => {
      const selected = events.filter(r => r.record.properties.experienceStudy === study.id &&
        r.record.properties.experienceOutcome === 'rendered');
      const owners = new Set(selected.map(r => r.userId));
      const units = new Set(selected.map(r =>
        `${r.userId}:${r.record.properties.consentEpoch}:${r.record.properties.cohortId}`));
      return { study: study.id, exposedUnits: owners.size >= 50 ? units.size : null,
        decision: 'inconclusive', reason: invalid ? 'invalid_observations' : 'growthbook_analysis_not_connected' };
    }),
    definition: 'Consented installation/account-scope observations, not unique people, web visits or referral deliveries. Fifty is a privacy floor, not power. No production winner is enabled.',
  };
}
