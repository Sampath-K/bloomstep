import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { reminderPreferenceCohorts } from '../src/reminder-cohorts.mjs';

const at = '2026-08-01T12:00:00.000Z';
const deadline = '2026-08-31T12:00:00.000Z';
const project = rows => reminderPreferenceCohorts(rows, '2026-08-31', '2026-08-31', '2026-09-02T00:00:00.000Z');
function episode(index, outcome = 'followup') {
  const userId = (index + 1).toString(16).padStart(64, '0');
  const properties = { disclosureVersion: 1, cohortId: randomUUID(), consentEpoch: randomUUID(), platform: 'windows', localDay: '2026-08-01' };
  return [
    { userId, record: { id: randomUUID(), name: 'reminder_preference_started', ts: at, properties } },
    { userId, record: { id: randomUUID(), name: `reminder_preference_${outcome}`,
      ts: outcome === 'disabled' ? '2026-08-05T12:00:00.000Z' : deadline,
      properties: { ...properties, localDay: outcome === 'disabled' ? '2026-08-05' : '2026-08-31' } } },
  ];
}

test('narrow preference projection includes explicit disabled and confirmed followup owners, never original OS target', () => {
  const rows = Array.from({ length: 100 }, (_, index) => episode(index, index < 50 ? 'disabled' : 'followup')).flat();
  const result = project(rows);
  assert.equal(result.observedDisableFraction, .5);
  assert.equal(result.matureAccounts, 100);
  assert.equal(result.disabledAccounts, 50);
  assert.equal(result.confirmedEnabledAccounts, 50);
  assert.equal(result.originalGoalReason, 'not_observable');
  assert.equal(result.reason, null);
});

test('missing or foreign epoch followup is unknown, not a successful non-disable outcome', () => {
  for (const mismatch of [false, true]) {
    const rows = Array.from({ length: 100 }, (_, index) => {
      const pair = episode(index, 'disabled');
      if (index < 50) return pair;
      if (!mismatch) return [pair[0]];
      pair[1].record.properties.consentEpoch = randomUUID();
      return pair;
    }).flat();
    const result = project(rows);
    assert.equal(result.observedDisableFraction, null);
    assert.equal(result.unknownFollowupAccounts, 50);
    assert.equal(result.reason, 'followup_unavailable');
  }
});

test('sub50 owners or contributing disable subset are suppressed; no inferred zero or100percent', () => {
  const rows = Array.from({ length: 60 }, (_, index) => episode(index)).flat();
  assert.equal(project(rows).observedDisableFraction, null);
  assert.equal(project(rows).disabledAccounts, null);
  const oneOwner = rows.map(row => ({ ...row, userId: 'a'.repeat(64) }));
  assert.equal(project(oneOwner).matureAccounts, null);
});

test('parent totals and ratios cannot reveal a suppressed nonempty outcome subset by subtraction', () => {
  for (const disabledCount of [49, 51]) {
    const rows = Array.from({ length: 100 }, (_, index) => episode(index, index < disabledCount ? 'disabled' : 'followup')).flat();
    const result = project(rows);
    assert.equal(result.matureAccounts, null);
    assert.equal(result.observedDisableFraction, null);
    assert.equal(result.reason, 'contributors_below_50');
  }
  const rows = Array.from({ length: 101 }, (_, index) => index === 100
    ? [episode(index)[0]] : episode(index, index < 50 ? 'disabled' : 'followup')).flat();
  const result = project(rows);
  assert.equal(result.matureAccounts, null);
  assert.equal(result.disabledAccounts, 50);
  assert.equal(result.confirmedEnabledAccounts, 50);
  assert.equal(result.unknownFollowupAccounts, null);
  assert.equal(result.observedDisableFraction, null);
});

test('retries coalesce; conflicts, early followup and clock regression fail closed', () => {
  const rows = Array.from({ length: 100 }, (_, index) => episode(index, index < 50 ? 'disabled' : 'followup')).flat();
  assert.equal(project([...rows, structuredClone(rows[0])]).observedDisableFraction, .5);
  const duplicate = structuredClone(rows[0]);
  duplicate.record.properties.consentEpoch = randomUUID();
  assert.equal(project([...rows, duplicate]).reason, 'conflicting_observations');
  const early = episode(0);
  early[1].record.ts = '2026-08-31T11:59:59.999Z';
  assert.equal(project(early).reason, 'invalid_observations');
  const regressed = episode(0, 'disabled');
  regressed[1].record.ts = '2026-07-31T12:00:00.000Z';
  assert.equal(project(regressed).reason, 'invalid_observations');
});

test('legacy events cannot enroll; caps and invalid dates/windows fail explicitly', () => {
  assert.equal(project([{ userId: 'a'.repeat(64), record: { id: randomUUID(), name: 'notif_disabled', ts: deadline } }]).reason, 'cohort_below_50');
  assert.throws(() => project(Array.from({ length: 10001 }, () => episode(0)[0])));
  assert.throws(() => reminderPreferenceCohorts([], '2026-02-30', '2026-03-01', '2026-09-02T00:00:00.000Z'));
  assert.throws(() => reminderPreferenceCohorts([], '2026-08-31', '2026-09-02', '2026-09-02T00:00:00.000Z'));
});

test('terminal disabled episode cannot subsequently claim continued preference; malformed new properties fail closed', () => {
  const pair = episode(0, 'disabled');
  const followup = structuredClone(pair[1]);
  followup.record.id = randomUUID();
  followup.record.name = 'reminder_preference_followup';
  followup.record.ts = deadline;
  assert.equal(project([...pair, followup]).reason, 'invalid_observations');
  const privateExtra = structuredClone(pair[0]);
  privateExtra.record.properties.email = 'synthetic-private-field';
  assert.equal(project([privateExtra]).reason, 'invalid_observations');
  const laterDisable = episode(1, 'disabled');
  laterDisable[1].record.ts = '2026-09-01T12:00:00.000Z';
  assert.equal(project(laterDisable).confirmedEnabledAccounts, null);
  assert.equal(project(laterDisable).observedDisableFraction, null);
});

test('conflicting repeated phase facts cannot choose an arbitrary successful closure', () => {
  const pair = episode(0);
  const later = structuredClone(pair[1]);
  later.record.id = randomUUID();
  later.record.ts = '2026-09-01T12:00:00.000Z';
  later.record.properties.localDay = '2026-09-01';
  assert.equal(project([...pair, later]).reason, 'conflicting_observations');
  const exactDuplicate = structuredClone(pair[1]);
  exactDuplicate.record.id = randomUUID();
  assert.notEqual(project([...pair, exactDuplicate]).reason, 'conflicting_observations');
});

test('new observation events require exact current disclosure marker; names or legacy analytics cannot imply fresh consent', () => {
  for (const version of [undefined, 0, 2]) {
    const pair = episode(0);
    for (const row of pair) {
      if (version === undefined) delete row.record.properties.disclosureVersion;
      else row.record.properties.disclosureVersion = version;
    }
    assert.equal(project(pair).reason, 'invalid_observations');
    assert.equal(project(pair).observedDisableFraction, null);
  }
});

test('microsecond start/deadline and contradictory phase facts never collapse to millisecond equality', () => {
  const pair = episode(0);
  pair[0].record.ts = '2026-08-01T12:00:00.000999Z';
  pair[1].record.ts = '2026-08-31T12:00:00.000998Z';
  assert.equal(project(pair).reason, 'invalid_observations');
  pair[1].record.ts = '2026-08-31T12:00:00.000999Z';
  assert.equal(project(pair).reason, 'cohort_below_50');
  const duplicate = structuredClone(pair[1]);
  duplicate.record.id = randomUUID();
  duplicate.record.ts = '2026-08-31T12:00:00.000997Z';
  assert.equal(project([...pair, duplicate]).observedDisableFraction, null);
  assert.notEqual(project([...pair, duplicate]).reason, 'cohort_below_50');
});
