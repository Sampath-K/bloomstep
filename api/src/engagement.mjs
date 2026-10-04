import { z } from 'zod';
import { eventNames, eventSchema } from './contracts.mjs';
import { eventRegistry } from './event_registry.g.mjs';

export const previewLimits = Object.freeze({
  accounts: 200, lifetimeOperations: 20000, operationsPerDay: 2000,
  lifetimeRecords: 10000, eventsPerDay: 30, replies: 20,
  records: Object.freeze({ habits: 100, checkins: 1000, reflections: 100, voice: 100, events: 3000, settings: 7 }),
  feedbackPage: 20, metricRecords: 10000, gardenRecords: 1307,
  adminActions: Object.freeze({
    metrics_read: Object.freeze({ daily: 12, lifetime: 120 }),
    feedback_read: Object.freeze({ daily: 60, lifetime: 600 }),
    feedback_reply: Object.freeze({ daily: 60, lifetime: 600 }),
    aggregates_write: Object.freeze({ daily: 2, lifetime: 60 }),
  }),
});
export const feedbackQuerySchema = z.object({
  limit: z.string().regex(/^[1-9]\d?$/).transform(Number).pipe(z.number().max(previewLimits.feedbackPage)).optional(),
  cursor: z.string().max(256).optional(),
}).strict();
export const metricsQuerySchema = z.object({
  days: z.string().regex(/^[1-9]\d?$/).transform(Number).pipe(z.number().max(30)).optional(),
}).strict();

/** @param {string | undefined} cursor */
export function decodeCursor(cursor) {
  if (!cursor) return '';
  const decoded = Buffer.from(cursor, 'base64url').toString('utf8');
  if (!/^[a-f0-9]{64}:voice:[a-zA-Z0-9-]{1,64}$/.test(decoded)
      || Buffer.from(decoded).toString('base64url') !== cursor) throw new Error('Invalid cursor.');
  return decoded;
}

/**
 * Aggregates only validated opt-in event envelopes; private garden/voice records
 * are never inputs. IDs are used only for immutable union within one account.
 * @param {{userId: string, record: unknown}[]} rows
 * @param {string} startDay
 * @param {string} endDay
 */
export function aggregateEvents(rows, startDay, endDay) {
  const minimumCohort = 50;
  /** @type {Map<string, { users: Set<string>, counts: Record<string, number>, cohorts: Map<string, Set<string>> }>} */
  const buckets = new Map();
  for (let day = new Date(`${startDay}T00:00:00Z`); day.toISOString().slice(0, 10) <= endDay; day.setUTCDate(day.getUTCDate() + 1)) {
    buckets.set(day.toISOString().slice(0, 10), { users: new Set(), counts: Object.fromEntries(eventNames.map(name => [name, 0])), cohorts: new Map() });
  }
  /** @type {Map<string, {userId: string, event: z.infer<typeof eventSchema>} | null>} */
  const envelopes = new Map();
  for (const row of rows) {
    const parsed = eventSchema.safeParse(row.record);
    if (!parsed.success) continue;
    const key = `${row.userId}:${parsed.data.id}`;
    const previous = envelopes.get(key);
    if (previous === null) continue;
    const canonical = (/** @type {z.infer<typeof eventSchema>} */ event) =>
      JSON.stringify([event.name, event.ts, Object.entries(event.properties ?? {}).sort(([a], [b]) => a.localeCompare(b))]);
    envelopes.set(key, previous && canonical(previous.event) !== canonical(parsed.data)
      ? null : { userId: row.userId, event: parsed.data });
  }
  /** @type {Map<string, Set<string>>} */
  const practiceDays = new Map();
  for (const row of envelopes.values()) {
    if (!row) continue;
    const event = row.event;
    const bucket = buckets.get(event.ts.slice(0, 10));
    if (!bucket) continue;
    bucket.users.add(row.userId);
    bucket.counts[event.name]++;
    const cohort = bucket.cohorts.get(event.name) ?? new Set();
    cohort.add(row.userId);
    bucket.cohorts.set(event.name, cohort);
    if (event.name === 'checkin') {
      const days = practiceDays.get(row.userId) ?? new Set();
      days.add(event.ts.slice(0, 10));
      practiceDays.set(row.userId, days);
    }
  }
  const daily = [...buckets.entries()].map(([day, bucket]) => ({
    day, suppressed: bucket.users.size < minimumCohort,
    users: bucket.users.size >= minimumCohort ? bucket.users.size : null,
    counts: bucket.users.size >= minimumCohort
      ? Object.fromEntries(eventNames.map(name => [name,
        eventRegistry[/** @type {keyof typeof eventRegistry} */ (name)].observable && (bucket.cohorts.get(name)?.size ?? 0) >= minimumCohort ? bucket.counts[name] : null]))
      : null,
  }));
  /** @param {string} name */
  const total = name => daily.some(day => !day.counts || day.counts[name] === null)
    ? null : daily.reduce((sum, day) => sum + Number(day.counts?.[name] ?? 0), 0);
  const returning = [...practiceDays.values()].filter(days => days.size >= 2).length;
  return {
    startDay, endDay, minimumCohort, daily,
    categories: {
      activationRetention: { signins: total('signin_succeeded'), recipesCreated: total('recipe_created'), checkins: total('checkin'), graduations: total('habit_graduated'), returningCheckinUsers: returning >= minimumCohort ? returning : null },
      reminderLearning: { remindersSent: total('reminder_sent'), reflections: total('reflection'), weeklyReflections: total('weekly_reflection') },
      voiceRatings: { feedbackSubmitted: total('feedback_submitted'), ratingPrompts: total('rating_prompted'), ratings: total('rated') },
      sharingExperiment: { sharesInitiated: total('share_initiated'), experiments: null },
    },
    limitations: [
      'Opt-in allowlisted event counts, not all-user activation rates or production dashboards.',
      'A returning check-in user has events on at least two UTC days in this window; this is not D7/D30 retention.',
      'Small daily and per-event cohorts are suppressed; null is unavailable, not zero.',
      'Missing, sparse or future/unobservable measures are null, never assumed zero. Rating prompts are not submissions. Registered event names do not prove complete acquisition, OS delivery or experiment capture.',
    ],
  };
}
