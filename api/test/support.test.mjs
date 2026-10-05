import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { supportMetrics } from '../src/support.mjs';

const startDay = '2026-08-20', endDay = '2026-08-31', observedAt = '2026-09-01T12:00:00.000Z';
const account = n => n.toString(16).padStart(64, '0');
const row = (n, overrides = {}) => {
  const value = {
  userId: account(n), id: `voice:${randomUUID()}`, kind: 'Rating', rating: 2,
  support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: '2026-08-31T12:00:00.000Z' },
  ...overrides,
  };
  return { ...value, hasResponses: overrides.hasResponses ?? value.support?.firstRespondedAt !== null };
};
const cohort = count => Array.from({ length: count }, (_, i) => row(i + 1));
const measure = rows => supportMetrics(rows, startDay, endDay, observedAt);

test('server-backed answered elapsed tracking preserves exact48h threshold without inventing a rate target', () => {
  const result = measure(cohort(50));
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.source, 'server_voice_receipts');
  assert.deepEqual(result.firstResponses, { reason: null, contributingAccounts: 50, records: 50, medianHours: 48, maximumHours: 48 });
  assert.equal(result.lowRatings48h.thresholdHours, 48);
  assert.equal(result.lowRatings48h.matureRecords, 50);
  assert.equal(result.lowRatings48h.within48, 50);
  assert.equal(result.lowRatings48h.complianceFraction, 1);
  assert.equal(Object.hasOwn(result.lowRatings48h, 'target'), false);
  assert.deepEqual(result.businessDays, { target: 2, value: null, reason: 'calendar_not_configured' });
  assert.equal(JSON.stringify(result).includes(account(1)), false);
});

test('matured unanswered and late ratings remain in compliance denominator; immature ratings are separate', () => {
  const timely = cohort(50);
  const late = Array.from({ length: 50 }, (_, i) => row(i + 51, {
    support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: observedAt },
  }));
  const unanswered = Array.from({ length: 50 }, (_, i) => row(i + 101, {
    support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: null },
  }));
  const immature = Array.from({ length: 50 }, (_, i) => row(i + 151, {
    support: { schemaVersion: 1, receivedAt: '2026-08-31T12:00:00.000Z', firstRespondedAt: null },
  }));
  const result = measure([...timely, ...late, ...unanswered, ...immature]);
  assert.equal(result.lowRatings48h.matureRecords, 150);
  assert.equal(result.lowRatings48h.contributingAccounts, 150);
  assert.equal(result.lowRatings48h.within48, 50);
  assert.equal(result.lowRatings48h.respondedLate, 50);
  assert.equal(result.lowRatings48h.overdueUnanswered, 50);
  assert.equal(result.lowRatings48h.immatureRecords, 50);
  assert.equal(result.lowRatings48h.complianceFraction, 1 / 3);
  assert.equal(result.firstResponses.maximumHours, 72);
  assert.equal(result.firstResponses.records, 100);
});

test('exact deadline is still open until it closes; exact48h responses are on time', () => {
  const closed = cohort(50);
  const boundary = Array.from({ length: 50 }, (_, i) => row(i + 51, {
    support: { schemaVersion: 1, receivedAt: '2026-08-30T12:00:00.000Z', firstRespondedAt: null },
  }));
  const result = measure([...closed, ...boundary]);
  assert.equal(result.lowRatings48h.matureRecords, 50);
  assert.equal(result.lowRatings48h.immatureRecords, 50);
  assert.equal(result.lowRatings48h.within48, 50);
});

test('legacy receipts are unavailable rather than now or client time; observed source cohort stays explicit', () => {
  const legacy = Array.from({ length: 50 }, (_, i) => row(i + 51, { support: undefined }));
  const result = measure([...cohort(50), ...legacy]);
  assert.equal(result.coverage.legacyRecords, 50);
  assert.equal(result.lowRatings48h.matureRecords, 50);
  assert.match(result.definition, /Legacy/);
  assert.match(result.definition, /not an all-feedback census/);
  const absent = measure(legacy);
  assert.equal(absent.firstResponses.medianHours, null);
  assert.equal(absent.lowRatings48h.complianceFraction, null);
  assert.notEqual(absent.lowRatings48h.matureRecords, 0);
});

test('counts and elapsed/rate results require50 distinct contributing owners, not50 records from one owner', () => {
  const repeated = cohort(100).map(item => ({ ...item, userId: account(1) }));
  const result = measure(repeated);
  assert.equal(result.firstResponses.reason, 'cohort_below_50');
  assert.equal(result.firstResponses.records, null);
  assert.equal(result.lowRatings48h.reason, 'cohort_below_50');
  assert.equal(result.lowRatings48h.complianceFraction, null);
  const tinyLateSubset = measure([...cohort(50), row(51, {
    support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: null },
  })]);
  assert.equal(tinyLateSubset.lowRatings48h.overdueUnanswered, null);
  assert.equal(tinyLateSubset.lowRatings48h.complianceFraction, 50 / 51);
});

test('no answered contributors is unavailable, not zero elapsed or100% compliance', () => {
  const result = measure(cohort(50).map(item => ({ ...item,
    hasResponses: false, support: { ...item.support, firstRespondedAt: null } })));
  assert.equal(result.firstResponses.medianHours, null);
  assert.equal(result.lowRatings48h.complianceFraction, null);
  assert.equal(result.lowRatings48h.reason, 'contributors_below_50');
  assert.equal(result.lowRatings48h.matureRecords, 50);
  assert.equal(result.lowRatings48h.overdueUnanswered, 50);
});

test('malformed or conflicting provenance makes timing unavailable rather than partial/corrected success', () => {
  for (const support of [
    { schemaVersion: 1, receivedAt: 'invalid', firstRespondedAt: null },
    { schemaVersion: 2, receivedAt: observedAt, firstRespondedAt: null },
    { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: '2026-08-28T12:00:00.000Z' },
    { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: null, privateBody: 'Forbidden private payload' },
  ]) {
    const result = measure([...cohort(50), row(51, { support })]);
    assert.equal(result.lowRatings48h.reason, 'invalid_receipts');
    assert.equal(result.firstResponses.medianHours, null);
    assert.equal(JSON.stringify(result).includes('Forbidden private payload'), false);
  }
  const rows = cohort(50);
  assert.deepEqual(measure([...rows, ...rows]), measure(rows));
  const conflict = { ...rows[0], hasResponses: false, support: { ...rows[0].support, firstRespondedAt: null } };
  const result = measure([...rows, conflict]);
  assert.equal(result.lowRatings48h.reason, 'conflicting_receipts');
  assert.equal(result.lowRatings48h.complianceFraction, null);
});

test('first-response provenance lost by compatible older writer is unknown, not unanswered or late-inferred', () => {
  const result = measure([...cohort(50), row(51, {
    hasResponses: true,
    support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: null },
  })]);
  assert.equal(result.lowRatings48h.reason, 'first_response_unavailable');
  assert.equal(result.lowRatings48h.complianceFraction, null);
  assert.equal(result.lowRatings48h.overdueUnanswered, null);
  assert.equal(result.firstResponses.medianHours, null);
});

test('future server facts are unavailable without clock clamping or negative elapsed', () => {
  const result = measure([...cohort(50), row(51, {
    support: { schemaVersion: 1, receivedAt: '2026-08-29T12:00:00.000Z', firstRespondedAt: '2026-09-02T12:00:00.000Z' },
  })]);
  assert.equal(result.firstResponses.reason, 'server_clock_unavailable');
  assert.equal(result.lowRatings48h.complianceFraction, null);
});

test('non-rating and high-rating notes do not enter the low-rating denominator', () => {
  const result = measure([...cohort(50), ...cohort(50).map((item, i) => ({ ...item, userId: account(i + 51), kind: 'Idea', rating: null })),
    ...cohort(50).map((item, i) => ({ ...item, userId: account(i + 101), rating: 5 }))]);
  assert.equal(result.firstResponses.records, 150);
  assert.equal(result.lowRatings48h.matureRecords, 50);
});

test('receipt UTC window, not client dates or response day, selects records; unresolved calendar stays unavailable', () => {
  const rows = cohort(50).map(item => ({ ...item, support: {
    ...item.support, receivedAt: '2026-08-19T23:59:59.999Z' } }));
  const excluded = measure(rows);
  assert.equal(excluded.firstResponses.records, null);
  assert.equal(excluded.lowRatings48h.matureRecords, null);
  assert.equal(excluded.businessDays.reason, 'calendar_not_configured');
  assert.throws(() => supportMetrics([], '2026-09-01', '2026-09-01', observedAt), /completed UTC/);
  assert.throws(() => supportMetrics([], '2026-07-01', endDay, observedAt), /window/);
});
