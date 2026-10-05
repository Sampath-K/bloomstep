import { eventSchema } from './contracts.mjs';
import { registryVersion } from './event_registry.g.mjs';

/** @param {string} day @param {number} offset */
export function addDays(day, offset) {
  return new Date(Date.parse(`${day}T00:00:00Z`) + offset * 86400000).toISOString().slice(0, 10);
}
/** @param {string} value */
export const timestampKey = value => value.replace(/(?:\.(\d+))?Z$/, (_, digits = '') => `.${digits.padEnd(6, '0')}Z`);
/**
 * No identity linkage across web/install/broker boundaries is inferred.
 * @param {{userId: string, record: unknown}[]} rows
 */
export function normalizedEvents(rows) {
  /** @type {Map<string, {userId:string, record:import('zod').infer<typeof eventSchema>} | null>} */
  const unique = new Map();
  for (const row of rows) {
    const parsed = eventSchema.safeParse(row.record);
    if (!parsed.success) continue;
    const key = `${row.userId}:${parsed.data.id}`;
    const previous = unique.get(key);
    if (previous === null) continue;
    // Parsed property objects are normalized for deterministic immutable union.
    const normalize = (/** @type {import('zod').infer<typeof eventSchema>} */ r) => JSON.stringify([r.name, r.ts, Object.entries(r.properties ?? {}).sort(([a], [b]) => a.localeCompare(b))]);
    unique.set(key, previous && normalize(previous.record) !== normalize(parsed.data) ? null : { userId: row.userId, record: parsed.data });
  }
  return [...unique.values()].filter(value => value !== null).sort((a, b) =>
    timestampKey(a.record.ts).localeCompare(timestampKey(b.record.ts)) || a.record.id.localeCompare(b.record.id) || a.userId.localeCompare(b.userId));
}
/** @param {ReturnType<typeof normalizedEvents>} events */
export function effectiveCheckins(events) {
  const effective = new Map();
  for (const row of events) {
    if (!['checkin','first_checkin'].includes(row.record.name)
      || typeof row.record.properties?.localDay !== 'string' || typeof row.record.properties?.result !== 'string') continue;
    effective.set(`${row.userId}:${row.record.properties.habitId ?? '__unidentified'}:${row.record.properties.localDay}`, row);
  }
  return [...effective.values()].filter(row => ['did','didMore'].includes(String(row.record.properties?.result)));
}
/**
 * @param {{userId: string, record: unknown}[]} rows
 * @param {string} startDay @param {string} endDay @param {string} observedThrough
 */
export function dashboardSummaries(rows, startDay, endDay, observedThrough) {
  const minimumCohort = 50;
  const events = normalizedEvents(rows);
  const window = events.filter(row => row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay);
  const practicing = effectiveCheckins(events);
  /** @param {string[]} names */
  const users = names => new Set(window.filter(row => names.includes(row.record.name)).map(row => row.userId));
  /** @param {Set<string>} group */
  const count = group => group.size >= minimumCohort ? group.size : null;
  /** @param {Set<string>} denominator @param {Set<string>} numerator */
  const rate = (denominator, numerator) => {
    const retained = new Set([...numerator].filter(user => denominator.has(user)));
    const suppressed = denominator.size < minimumCohort || retained.size < minimumCohort;
    return { eligibleUsers: count(denominator), convertedUsers: count(retained), rate: suppressed ? null : retained.size / denominator.size, suppressed };
  };
  const signins = window.filter(row => row.record.name === 'signin_succeeded');
  const firsts = window.filter(row => row.record.name === 'first_checkin' && ['did','didMore'].includes(String(row.record.properties?.result)));
  const activated = new Set(firsts.filter(first => signins.some(signin => signin.userId === first.userId
    && timestampKey(signin.record.ts) <= timestampKey(first.record.ts) && (signin.record.properties?.localDay ?? signin.record.ts.slice(0, 10)) === (first.record.properties?.localDay ?? first.record.ts.slice(0, 10)))).map(row => row.userId));
  const stages = ['landing_view','download_click','install_completed','first_launch','signin_succeeded','first_checkin','habit_graduated','share_initiated','invite_accepted'];
  /** @param {string} before @param {string} after */
  const transition = (before, after) => {
    const eligible = window.filter(row => row.record.name === before);
    const converted = window.filter(row => row.record.name === after && eligible.some(first => first.userId === row.userId && timestampKey(first.record.ts) <= timestampKey(row.record.ts)));
    return rate(new Set(eligible.map(row => row.userId)), new Set(converted.map(row => row.userId)));
  };
  const breakdowns = [];
  for (const field of ['channel','platform']) {
    const values = [...new Set(signins.map(row => row.record.properties?.[field]).filter(value => typeof value === 'string'))].sort();
    for (const value of values) {
      const eligible = new Set(signins.filter(row => row.record.properties?.[field] === value).map(row => row.userId));
      if (eligible.size >= minimumCohort) breakdowns.push({ dimension: field, value, ...rate(eligible, activated) });
    }
  }
  /** @type {Map<string, string>} */
  const firstPractice = new Map();
  for (const row of events) {
    if (row.record.name !== 'first_checkin' || !['did','didMore'].includes(String(row.record.properties?.result)) || typeof row.record.properties?.localDay !== 'string') continue;
    const day = row.record.properties.localDay;
    const previous = firstPractice.get(row.userId);
    if (!previous || day < previous) firstPractice.set(row.userId, day);
  }
  const cohortDays = [...new Set([...firstPractice.values()].filter(day => day >= addDays(startDay, -30) && day <= endDay))].sort();
  const cohorts = cohortDays.map(day => {
    const eligible = new Set([...firstPractice].filter(([, value]) => value === day).map(([user]) => user));
    /** @param {number} offset */
    const retention = offset => {
      const target = addDays(day, offset);
      const matured = target < observedThrough;
      const practice = new Set(practicing.filter(row => row.record.properties?.localDay === target).map(row => row.userId));
      const measured = rate(eligible, practice);
      return { targetDay: target, matured, eligibleUsers: measured.eligibleUsers,
        practicingUsers: matured ? measured.convertedUsers : null, rate: matured ? measured.rate : null,
        suppressed: !matured || measured.suppressed };
    };
    return { cohortDay: day, cohortUsers: count(eligible), suppressed: eligible.size < minimumCohort, d1: retention(1), d7: retention(7), d30: retention(30) };
  });
  const daily = [];
  for (let day = startDay; day <= endDay; day = addDays(day, 1)) {
    const entries = window.filter(row => row.record.ts.slice(0, 10) === day);
    const dayUsers = new Set(entries.map(row => row.userId));
    const scoreEntries = entries.filter(row => ['automaticity_score','reflection'].includes(row.record.name) && typeof row.record.properties?.score === 'number');
    // Latest score per contributing user/day avoids heavy users weighting medians.
    const scores = new Map(scoreEntries.map(row => [row.userId, Number(row.record.properties?.score)]));
    const values = [...scores.values()].sort((a, b) => a - b);
    const median = values.length >= minimumCohort ? (values[Math.floor((values.length - 1) / 2)] + values[Math.floor(values.length / 2)]) / 2 : null;
    daily.push({ day, suppressed: dayUsers.size < minimumCohort, scoreUsers: count(new Set(scores.keys())), medianAutomaticity: median,
      practicingUsers: count(new Set(practicing.filter(row => row.record.properties?.localDay === day).map(row => row.userId))),
      graduatedUsers: count(new Set(entries.filter(row => row.record.name === 'habit_graduated').map(row => row.userId))),
      graduationCount: new Set(entries.filter(row => row.record.name === 'habit_graduated').map(row => row.userId)).size >= minimumCohort ? entries.filter(row => row.record.name === 'habit_graduated').length : null });
  }
  const delivered = window.filter(row => row.record.name === 'notif_delivered' && typeof row.record.properties?.notificationId === 'string');
  const acted = new Set(window.filter(row => row.record.name === 'notif_actioned' && row.record.properties?.notificationId
    && delivered.some(before => before.userId === row.userId && before.record.properties?.notificationId === row.record.properties?.notificationId && timestampKey(before.record.ts) <= timestampKey(row.record.ts))).map(row => row.userId));
  const reminderUsers = users(['notif_sent','reminder_sent']);
  const healthSessions = window.filter(row => row.record.name === 'session_started' && row.record.properties?.sessionId);
  const crashed = window.filter(row => row.record.name === 'crash' && row.record.properties?.sessionId);
  // Absence of a crash event does not prove complete diagnostic capture.
  return {
    registryVersion, minimumCohort, startDay, endDay, observedThrough,
    funnel: { stages: Object.fromEntries(stages.map(name => [name, { users: count(users([name])), suppressed: users([name]).size < minimumCohort }])),
      visitToDownload: transition('landing_view','download_click'), downloadToLaunch: transition('download_click','first_launch'),
      launchToSignin: transition('first_launch','signin_succeeded'), sameDayActivation: rate(users(['signin_succeeded']), activated), breakdowns,
      definition: 'Same authenticated account, original ordered observation times in the window; same-day activation uses reported localDay or UTC fallback. Web/installer receipts are self-selected, explicitly account-linked under independent consent, not authenticated installer proof or automatic browser-to-broker attribution. Source/IDs do not prove unique visitors or complete capture; missing cohorts are unavailable.' },
    retention: { cohorts, cohortStartDay: addDays(startDay, -30), cohortEndDay: endDay, definition: 'Opt-in explicit first_checkin with did/didMore and localDay, including 30-day cohort lookback; exact local-day +1/+7/+30 effective did/didMore checkin, not rolling retention. Latest microsecond/UUID-ordered result per account/habit/localDay wins; omitted habit IDs form one unidentified stream. Mature only after target UTC date closes. Missing result/date or <50 numerator/denominator yields null. Late/offline events can revise snapshots.' },
    outcomes: { daily, definition: 'UTC score/graduation event trends and effective local-date practicing users; median latest numeric 1–7 score per user/day; counts only publishable cohorts, not clinical outcomes or all-user graduation rate.' },
    reminderHealth: { sentUsers: count(reminderUsers), deliveredUsers: count(users(['notif_delivered'])), actionRate: rate(new Set(delivered.map(row => row.userId)), acted),
      disableRate: rate(reminderUsers, users(['notif_disabled'])),
      openedUsers: count(users(['notif_opened'])), dismissedUsers: count(users(['notif_dismissed'])),
      definition: 'User-level observed delivered→actioned with same notification UUID; disable rate is sent users with disable event in window. Event absence is not OS delivery or opt-out evidence.' },
    appHealth: { observedSessionUsers: count(new Set(healthSessions.map(row => row.userId))), observedCrashUsers: count(new Set(crashed.map(row => row.userId))), crashFreeRate: null,
      definition: 'Opt-in bounded Dart/Flutter observed errors may be nonfatal; no messages/stacks or native/process-death census. Event absence cannot establish crash-free sessions.' },
    experiment: { enabled: false, reason: 'No verified exposure/guardrail completeness; taxonomy does not enable the experiment.' },
  };
}
