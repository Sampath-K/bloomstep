import { z } from 'zod';
import { voiceSchema } from './contracts.mjs';
import { addDays } from './dashboards.mjs';

export const supportReceiptSchema = z.object({
  schemaVersion: z.literal(1),
  receivedAt: z.iso.datetime({ precision: 3 }),
  firstRespondedAt: z.iso.datetime({ precision: 3 }).nullable(),
}).strict().refine(value => value.firstRespondedAt === null || value.firstRespondedAt >= value.receivedAt,
  'First response must not predate the server receipt.');

const sourceRowSchema = z.object({
  userId: z.string().regex(/^[a-f0-9]{64}$/),
  id: z.string().refine(value => value.startsWith('voice:') && z.uuid().safeParse(value.slice(6)).success),
  kind: voiceSchema.shape.kind,
  rating: voiceSchema.shape.rating,
  hasResponses: z.boolean(),
  support: supportReceiptSchema.optional(),
}).strict().refine(value => (value.kind !== 'Rating' || value.rating !== null) &&
  (!value.support?.firstRespondedAt || value.hasResponses));

const definition = 'Private operational server receipt/first committed operator reply facts, not product-event analytics. Legacy receipts are excluded without inferring client times, reply prefixes or now; this is not an all-feedback census. Answered elapsed median/maximum are descriptive, not business-day SLA or customer-read/delivery proof. Closed48h low-rating receipt cohorts include overdue unanswered records in the denominator; immature records remain separate. No100% compliance target is invented.';

/**
 * @param {unknown[]} rows
 * @param {string} startDay
 * @param {string} endDay
 * @param {string} observedAt
 */
export function supportMetrics(rows, startDay, endDay, observedAt) {
  if (![startDay, endDay].every(day => z.iso.date().safeParse(day).success) ||
      startDay > endDay || endDay > addDays(startDay, 29) ||
      !z.iso.datetime({ precision: 3 }).safeParse(observedAt).success) throw new Error('Invalid support metric window.');
  if (endDay >= observedAt.slice(0, 10)) throw new Error('Support metrics require completed UTC receipt days.');
  if (rows.length > 10000) throw new Error('Support metrics scan cap exceeded.');
  /** @type {Map<string, z.infer<typeof sourceRowSchema>>} */
  const unique = new Map();
  let sourceReason = null;
  for (const row of rows) {
    const parsed = sourceRowSchema.safeParse(row);
    if (!parsed.success) { sourceReason = 'invalid_receipts'; continue; }
    const value = parsed.data;
    const key = `${value.userId}:${value.id}`;
    const previous = unique.get(key);
    const canonical = (/** @type {z.infer<typeof sourceRowSchema>} */ entry) => JSON.stringify([entry.kind, entry.rating, entry.hasResponses, entry.support]);
    if (previous && canonical(previous) !== canonical(value)) {
      if (sourceReason !== 'invalid_receipts') sourceReason = 'conflicting_receipts';
    } else unique.set(key, value);
  }
  const records = [...unique.values()];
  if (new Set(records.map(row => row.userId)).size > 200) throw new Error('Support account scan cap exceeded.');
  const legacy = records.filter(row => !row.support);
  const selected = records.flatMap(row => {
    const support = row.support;
    return support && support.receivedAt.slice(0, 10) >= startDay && support.receivedAt.slice(0, 10) <= endDay
      ? [{ ...row, support }] : [];
  });
  if (!sourceReason && selected.some(row =>
      row.support.receivedAt > observedAt || row.support.firstRespondedAt && row.support.firstRespondedAt > observedAt)) {
    sourceReason = 'server_clock_unavailable';
  }
  if (!sourceReason && selected.some(row => row.hasResponses && row.support.firstRespondedAt === null)) {
    sourceReason = 'first_response_unavailable';
  }
  /** @param {typeof records} entries */
  const owners = entries => new Set(entries.map(row => row.userId)).size;
  /** @param {typeof records} entries */
  const shown = entries => !sourceReason && owners(entries) >= 50 ? entries.length : null;
  const answered = selected.flatMap(row => row.support.firstRespondedAt === null ? []
    : [{ ...row, support: { ...row.support, firstRespondedAt: row.support.firstRespondedAt } }]);
  const responseReason = sourceReason ?? (owners(answered) < 50 ? 'cohort_below_50' : null);
  const elapsed = answered.map(row => (Date.parse(row.support.firstRespondedAt) -
    Date.parse(row.support.receivedAt)) / 3600000).sort((a, b) => a - b);
  const middle = Math.floor(elapsed.length / 2);
  const median = !elapsed.length ? null : elapsed.length % 2 ? elapsed[middle] : (elapsed[middle - 1] + elapsed[middle]) / 2;
  const low = selected.filter(row => row.kind === 'Rating' && row.rating !== null && row.rating <= 3);
  const mature = low.filter(row => Date.parse(row.support.receivedAt) + 48 * 3600000 < Date.parse(observedAt));
  const immature = low.filter(row => Date.parse(row.support.receivedAt) + 48 * 3600000 >= Date.parse(observedAt));
  const timely = mature.filter(row => row.support.firstRespondedAt !== null &&
    Date.parse(row.support.firstRespondedAt) - Date.parse(row.support.receivedAt) <= 48 * 3600000);
  const late = mature.filter(row => row.support.firstRespondedAt !== null &&
    Date.parse(row.support.firstRespondedAt) - Date.parse(row.support.receivedAt) > 48 * 3600000);
  const unanswered = mature.filter(row => row.support.firstRespondedAt === null);
  const ratingReason = sourceReason ?? (owners(mature) < 50 ? 'cohort_below_50'
    : owners(timely) < 50 ? 'contributors_below_50' : null);
  return {
    schemaVersion: 1, source: 'server_voice_receipts', startDay, endDay, observedAt, minimumCohort: 50, definition,
    firstResponses: {
      reason: responseReason, contributingAccounts: responseReason ? null : owners(answered), records: shown(answered),
      medianHours: responseReason ? null : median, maximumHours: responseReason || !elapsed.length ? null : elapsed[elapsed.length - 1],
    },
    lowRatings48h: {
      thresholdHours: 48, reason: ratingReason,
      contributingAccounts: sourceReason || owners(mature) < 50 ? null : owners(mature),
      matureRecords: shown(mature), within48: shown(timely), respondedLate: shown(late),
      overdueUnanswered: shown(unanswered), immatureRecords: shown(immature),
      complianceFraction: ratingReason ? null : timely.length / mature.length,
    },
    businessDays: { target: 2, value: null, reason: 'calendar_not_configured' },
    coverage: { legacyRecords: shown(legacy), legacyReason: owners(legacy) < 50 ? 'contributors_below_50' : 'legacy_receipt_unavailable' },
  };
}
