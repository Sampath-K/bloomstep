import { eventSchema } from './contracts.mjs';

/**
 * Closed-schema observations, not an all-user sign-in funnel.
 * @param {{userId:string, record:unknown}[]} rows
 * @param {string} startDay @param {string} endDay
 */
export function authObservationSummary(rows, startDay, endDay) {
  /** @type {Map<string, {userId:string, record:import('zod').infer<typeof eventSchema>} | null>} */
  const unique = new Map();
  const invalidAttempts = new Set();
  const canonical = (/** @type {import('zod').infer<typeof eventSchema>} */ r) =>
    JSON.stringify([r.ts, Object.entries(r.properties ?? {}).sort(([a], [b]) => a.localeCompare(b))]);
  for (const row of rows) {
    const parsed = eventSchema.safeParse(row.record);
    if (!parsed.success || parsed.data.name !== 'auth_observation') continue;
    const key = `${row.userId}:${parsed.data.id}`;
    const old = unique.get(key);
    if (old === null || old && canonical(old.record) !== canonical(parsed.data)) {
      invalidAttempts.add(`${row.userId}:${parsed.data.properties?.attemptId}`);
      if (old) invalidAttempts.add(`${old.userId}:${old.record.properties?.attemptId}`);
    }
    unique.set(key, old === null || old && canonical(old.record) !== canonical(parsed.data)
      ? null : { userId: row.userId, record: parsed.data });
  }
  /** @type {Map<string, Map<string, import('zod').infer<typeof eventSchema> | null>>} */
  const attempts = new Map();
  for (const row of unique.values()) {
    if (row === null) continue;
    const record = row.record;
    const key = `${row.userId}:${record.properties?.attemptId}`;
    const observations = attempts.get(key) ?? new Map();
    const old = observations.get(record.id);
    observations.set(record.id, old === null || old && canonical(old) !== canonical(record) ? null : record);
    attempts.set(key, observations);
  }
  const stages = Object.fromEntries(['session_entry', 'api_token'].map(stage => {
    const observed = new Set(), succeeded = new Set(), failed = new Set();
    const kinds = Object.fromEntries(['timeout', 'network', 'validation', 'unavailable', 'unknown']
      .map(kind => [kind, new Set()]));
    for (const [key, observations] of attempts) {
      if (invalidAttempts.has(key)) continue;
      const records = [...observations.values()];
      if (records.some(row => row === null) || records.length > 2) continue;
      const start = records.find(row => row?.properties?.outcome === 'started');
      if (!start || start.properties?.authStage !== stage ||
          start.ts.slice(0, 10) < startDay || start.ts.slice(0, 10) > endDay) continue;
      const user = key.slice(0, key.lastIndexOf(':'));
      observed.add(user);
      const terminal = records.find(row => row?.properties?.outcome !== 'started');
      if (!terminal || terminal.properties?.authStage !== stage ||
          terminal.ts.slice(0, 10) < startDay || terminal.ts.slice(0, 10) > endDay) continue;
      const duration = Date.parse(terminal.ts) - Date.parse(start.ts);
      const reported = Number(terminal.properties?.elapsedMs);
      // Clock corrections or delayed writes cannot manufacture a valid pair.
      if (duration < 0 || duration > 180000 || Math.abs(duration - reported) > 2000 ||
          duration > 0 && reported === 0) continue;
      if (terminal.properties?.outcome === 'succeeded') succeeded.add(user);
      if (terminal.properties?.outcome === 'failed') {
        failed.add(user);
        kinds[String(terminal.properties.authErrorKind)]?.add(user);
      }
    }
    const publish = (/** @type {Set<string>} */ users) => users.size >= 50 ? users.size : null;
    // No subtractable small subsets: publish all three only when both
    // terminal groups and the remaining group are empty or independently >=50.
    const remaining = new Set([...observed].filter(user => !succeeded.has(user) && !failed.has(user)));
    const successOnly = new Set([...succeeded].filter(user => !failed.has(user)));
    const failureOnly = new Set([...failed].filter(user => !succeeded.has(user)));
    const both = new Set([...succeeded].filter(user => failed.has(user)));
    const safe = [successOnly, failureOnly, both, remaining].every(group => group.size === 0 || group.size >= 50);
    const kindPartitions = new Map();
    for (const user of failed) {
      const membership = Object.entries(kinds).filter(([, users]) => users.has(user)).map(([kind]) => kind).join(',');
      kindPartitions.set(membership, (kindPartitions.get(membership) ?? 0) + 1);
    }
    const safeKinds = safe && [...kindPartitions.values()].every(count => count >= 50);
    return [stage, { observedUsers: safe ? publish(observed) : null,
      succeededUsers: safe ? publish(succeeded) : null, failedUsers: safe ? publish(failed) : null,
      failureKinds: Object.fromEntries(Object.entries(kinds).map(([kind, users]) =>
        [kind, safeKinds ? publish(users) : null])) }];
  }));
  return { stages, allUserSigninSuccessRate: null, preAuthFailures: null,
    providerBreakdown: null,
    definition: 'Opt-in account-consented post-auth session_entry and api_token attempts only; same-owner ordered pairs within 3 minutes and this UTC window. Retries are distinct, users may occur in both outcomes. Missing, conflicting, expired or clock-inconsistent evidence is unknown, not failure or success. Fresh pre-auth browser/callback failures, signup, cancellation and Microsoft/Google attribution are NOT covered. Source is external_unattributed. No all-user denominator or global sign-in success rate; zero observations is unavailable, not zero failures. Counts below 50 and subtractable small subsets are suppressed. Token failures may remain local until later successful sync.' };
}
