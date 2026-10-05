import { z } from 'zod';

const names = ['reminder_preference_started', 'reminder_preference_disabled', 'reminder_preference_followup'];
const timestamp = z.iso.datetime().refine(value => !/\.\d{7,}Z$/.test(value));
const schema = z.object({
  userId: z.string().regex(/^[a-f0-9]{64}$/),
  record: z.object({
    id: z.uuid(), name: z.enum(names), ts: timestamp,
    schemaVersion: z.literal(1).optional(),
    properties: z.object({
      disclosureVersion: z.literal(1),
      cohortId: z.uuid(), consentEpoch: z.uuid(),
      platform: z.literal('windows'), localDay: z.iso.date(),
    }).strict(),
  }).strict(),
}).strict();
const horizonMs = 30 * 86400000;
/** @param {string} value */
const micros = value => BigInt(Date.parse(value)) * 1000n +
  BigInt((/\.(\d+)Z$/.exec(value)?.[1] ?? '').padEnd(6, '0').slice(3));

/**
 * Pure projection of fresh-consent app-preference observations.
 * Missing followup is unknown, not evidence of an enabled OS notification.
 * @param {unknown[]} rows
 * @param {string} startDay
 * @param {string} endDay
 * @param {string} observedAt
 */
export function reminderPreferenceCohorts(rows, startDay, endDay, observedAt) {
  if (![startDay, endDay].every(day => z.iso.date().safeParse(day).success) ||
      startDay > endDay || Date.parse(endDay) - Date.parse(startDay) > 29 * 86400000 ||
      !timestamp.safeParse(observedAt).success || endDay >= observedAt.slice(0, 10)) {
    throw new Error('Invalid completed reminder preference observation window.');
  }
  if (rows.length > 10000) throw new Error('Reminder preference scan cap exceeded.');
  /** @type {Map<string,z.infer<typeof schema>>} */
  const unique = new Map();
  let sourceReason = null;
  const seenOwners = new Set();
  for (const raw of rows) {
    if (raw && typeof raw === 'object' && 'userId' in raw) seenOwners.add(raw.userId);
    if (seenOwners.size > 200) throw new Error('Reminder preference account cap exceeded.');
    if (!raw || typeof raw !== 'object' || !('record' in raw) ||
        !raw.record || typeof raw.record !== 'object' || !('name' in raw.record) ||
        !names.includes(String(raw.record.name))) continue;
    const parsed = schema.safeParse(raw);
    if (!parsed.success) { sourceReason = 'invalid_observations'; continue; }
    const row = parsed.data;
    if (micros(row.record.ts) > micros(observedAt)) {
      sourceReason = 'invalid_observations'; continue;
    }
    const key = `${row.userId}:${row.record.id}`;
    const previous = unique.get(key);
    const canonical = (/** @type {z.infer<typeof schema>} */ entry) =>
      JSON.stringify([entry.record.name, micros(entry.record.ts).toString(),
        entry.record.properties.disclosureVersion,
        entry.record.properties.cohortId, entry.record.properties.consentEpoch,
        entry.record.properties.platform, entry.record.properties.localDay]);
    if (previous && canonical(previous) !== canonical(row)) {
      sourceReason = 'conflicting_observations';
    } else unique.set(key, row);
  }
  const events = [...unique.values()].sort((a, b) => {
    const left = micros(a.record.ts), right = micros(b.record.ts);
    return left < right ? -1 : left > right ? 1 : a.record.id.localeCompare(b.record.id);
  });
  /** @type {Map<string,z.infer<typeof schema>[]>} */
  const episodes = new Map();
  /** @type {Map<string,Map<string,z.infer<typeof schema>>>} */
  const phases = new Map();
  /** @param {z.infer<typeof schema>} row */
  const episodeKey = row => `${row.userId}:${row.record.properties.consentEpoch}:${row.record.properties.cohortId}`;
  for (const row of events) {
    const key = episodeKey(row);
    const entries = episodes.get(key) ?? [];
    entries.push(row);
    episodes.set(key, entries);
    const phase = phases.get(key) ?? new Map();
    const previous = phase.get(row.record.name);
    if (previous && (micros(previous.record.ts) !== micros(row.record.ts) ||
        previous.record.properties.localDay !== row.record.properties.localDay)) {
      sourceReason = 'conflicting_observations';
    } else phase.set(row.record.name, row);
    phases.set(key, phase);
  }
  /** @type {Map<string,z.infer<typeof schema>>} */
  const starts = new Map();
  const allStarts = new Map();
  for (const row of events.filter(entry => entry.record.name === names[0])) {
    const key = episodeKey(row);
    const previous = allStarts.get(key);
    if (previous && micros(previous.record.ts) !== micros(row.record.ts)) sourceReason = 'conflicting_observations';
    else allStarts.set(key, row);
    if (!starts.has(row.userId)) starts.set(row.userId, row);
  }
  for (const row of events.filter(entry => entry.record.name !== names[0])) {
    const start = allStarts.get(episodeKey(row));
    if (start && (micros(row.record.ts) < micros(start.record.ts) ||
        row.record.name === names[2] && micros(row.record.ts) < micros(start.record.ts) + BigInt(horizonMs) * 1000n)) {
      sourceReason = 'invalid_observations';
    }
    const disabledPhase = phases.get(episodeKey(row))?.get(names[1]);
    if (row.record.name === names[2] && disabledPhase &&
        micros(disabledPhase.record.ts) <= micros(row.record.ts)) {
      sourceReason = 'invalid_observations';
    }
  }
  const mature = [], disabled = [], confirmed = [], unknown = [], immature = [];
  for (const [userId, start] of starts) {
    const deadline = micros(start.record.ts) + BigInt(horizonMs) * 1000n;
    const closes = new Date(Number(deadline / 1000n)).toISOString().slice(0, 10);
    if (closes < startDay || closes > endDay) continue;
    if (deadline > micros(observedAt)) { immature.push(userId); continue; }
    mature.push(userId);
    const linked = episodes.get(episodeKey(start)) ?? [];
    if (linked.some(row => row.record.name === names[1] && micros(row.record.ts) >= micros(start.record.ts) &&
        micros(row.record.ts) <= deadline)) disabled.push(userId);
    else if (linked.some(row => row.record.name === names[2] && micros(row.record.ts) >= deadline)) confirmed.push(userId);
    else unknown.push(userId);
  }
  /** @param {string[]} owners */
  const shown = owners => !sourceReason && owners.length >= 50 ? owners.length : null;
  const smallOutcome = [disabled, confirmed, unknown].some(owners => owners.length > 0 && owners.length < 50);
  const reason = sourceReason ?? (mature.length < 50 ? 'cohort_below_50'
    : unknown.length ? 'followup_unavailable'
      : disabled.length < 50 || confirmed.length < 50 ? 'contributors_below_50' : null);
  return {
    schemaVersion: 1, source: 'observed_app_reminder_preference', horizonDays: 30,
    startDay, endDay, observedAt, minimumCohort: 50,
    definition: 'Fresh explicit versioned consent, observed post-consent app reminder-preference episodes only; not OS permission/delivery, lifetime enablement or an all-user census. One first observed episode per owner in the bounded input, never inferred lifetime uniqueness. Missing same-epoch followup remains unknown. Original full-coverage goal is not substituted.',
    matureAccounts: smallOutcome ? null : shown(mature), disabledAccounts: shown(disabled),
    confirmedEnabledAccounts: shown(confirmed), unknownFollowupAccounts: shown(unknown),
    immatureAccounts: shown(immature), observedDisableFraction: reason ? null : disabled.length / mature.length,
    reason, originalGoalReason: 'not_observable',
  };
}
