import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { goalMetrics } from '../src/goals.mjs';

const habit = randomUUID();
const event = (userId, name, localDay, properties = {}, ts = `${localDay}T12:00:00Z`) =>
  ({ userId, record: { id: randomUUID(), name, ts, properties: { ...(name === 'first_launch' ? {} : { localDay }), ...properties } } });
const cohort = (count = 50) => Array.from({ length: count }, (_, i) =>
  event(String(i), 'first_checkin', '2026-06-01', { habitId: habit, result: 'did' }));
const measure = (rows, start = '2026-06-08', end = start) =>
  goalMetrics(rows, start, end, '2026-09-01');
const goal = (data, id) => data.goals.find(row => row.id === id);

test('D7 counts effective habit/local-day checkins, not exact day7; edits, undo, aliases and duplicates do not inflate', () => {
  const rows = cohort();
  for (let i = 0; i < 50; i++) {
    for (const day of ['2026-06-02', '2026-06-03', '2026-06-04']) {
      const row = event(String(i), 'checkin', day, { habitId: habit, result: 'didMore' });
      rows.push(row, row);
    }
  }
  assert.equal(goal(measure(rows), 'd7').value, 1);
  rows.push(event('0', 'checkin', '2026-06-04', { habitId: habit, result: 'undo' }, '2026-06-09T01:00:00.000001Z'));
  const value = goal(measure(rows), 'd7');
  assert.equal(value.denominator, 50);
  assert.equal(value.value, null);
  assert.equal(value.reason, 'contributors_below_50');
});

test('D30 requires four distinct days23-30; several habits on one day do not meet frequency', () => {
  const rows = cohort();
  for (let i = 0; i < 50; i++) {
    for (const day of ['2026-06-24', '2026-06-25', '2026-06-26', '2026-07-01']) {
      rows.push(event(String(i), 'checkin', day, { habitId: habit, result: 'did' }));
    }
  }
  assert.equal(goal(measure(rows, '2026-07-01'), 'd30').value, 1);
  const oneDay = cohort();
  for (let i = 0; i < 50; i++) for (let j = 0; j < 4; j++) {
    oneDay.push(event(String(i), 'checkin', '2026-06-24', { habitId: randomUUID(), result: 'did' }));
  }
  assert.equal(goal(measure(oneDay, '2026-07-01'), 'd30').value, null);
});

test('graduation north star deduplicates habit IDs and rejects pre-activation/out-of-horizon events', () => {
  const rows = cohort();
  for (let i = 0; i < 50; i++) {
    const properties = { habitId: habit };
    rows.push(event(String(i), 'habit_graduated', '2026-06-10', properties),
      event(String(i), 'habit_graduated', '2026-06-11', properties),
      event(String(i), 'habit_graduated', '2026-05-31', { habitId: randomUUID() }),
      event(String(i), 'habit_graduated', '2026-07-02', { habitId: randomUUID() }));
  }
  const data = measure(rows, '2026-07-01');
  assert.equal(goal(data, 'north_star_30').value, 1);
  assert.equal(goal(data, 'north_star_30').numerator, 50);
  assert.equal(goal(measure(rows, '2026-08-30'), 'graduated_d90').value, 1);
  assert.equal(goal(data, 'north_star_30').target, null);
});

test('incomplete clock, sparse cohort and unobservable goals stay unavailable without identities', () => {
  const rows = cohort(49);
  assert.equal(goal(measure(rows), 'd7').reason, 'cohort_below_50');
  assert.throws(() => goalMetrics(rows, '2026-06-08', '2026-06-08', '2026-06-08'), /completed/);
  assert.throws(() => goalMetrics([], 'invalid', '2026-06-08', '2026-09-01'), /window/);
  const data = measure(cohort());
  for (const id of ['invites_30', 'feedback_response', 'low_rating_response', 'crash_free']) {
    assert.equal(goal(data, id).value, null);
    assert.equal(goal(data, id).reason, 'not_observable');
  }
  assert.equal(data.schemaVersion, 1);
  assert.match(data.coverage, /opt-in/i);
  const encoded = JSON.stringify(data);
  assert.equal(encoded.includes(habit), false);
  assert.equal(encoded.includes('"userId"'), false);
});

test('conflicting immutable envelopes are excluded deterministically and missing habit IDs never qualify', () => {
  const rows = cohort();
  for (let i = 0; i < 50; i++) {
    for (const day of ['2026-06-02', '2026-06-03', '2026-06-04']) rows.push(event(String(i), 'checkin', day, { result: 'did' }));
  }
  assert.equal(goal(measure(rows), 'd7').value, null);
  const first = rows[0];
  const conflict = { ...first, record: { ...first.record, name: 'checkin' } };
  assert.deepEqual(measure([...rows, conflict]), measure([conflict, ...rows]));
});

test('rates retain the full denominator and require50 contributing users, not50 raw events', () => {
  const rows = cohort(100);
  for (let i = 0; i < 50; i++) for (const day of ['2026-06-02', '2026-06-03', '2026-06-04']) {
    rows.push(event(String(i), 'checkin', day, { habitId: habit, result: 'did' }));
  }
  const data = measure(rows);
  assert.equal(goal(data, 'd7').value, .5);
  assert.equal(goal(data, 'd7').numerator, 50);
  assert.equal(goal(data, 'd7').denominator, 100);
});

test('original launch85% is not an attempt-success goal; day0 needs explicit matching local dates', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) {
    rows.push(event(String(i), 'first_launch', '2026-06-01', {}, '2026-06-01T10:00:00Z'),
      event(String(i), 'signin_succeeded', '2026-06-01', {}, '2026-06-01T11:00:00Z'),
      event(String(i), 'first_checkin', '2026-06-01', { habitId: habit, result: 'did' }));
  }
  const data = measure(rows, '2026-06-01');
  assert.equal(goal(data, 'launch_signin').target, .85);
  assert.equal(goal(data, 'launch_signin').value, 1);
  assert.match(goal(data, 'launch_signin').definition, /not an attempt-success/);
  assert.equal(goal(data, 'day0').value, 1);
  for (const row of rows) if (row.record.name === 'signin_succeeded') delete row.record.properties.localDay;
  assert.equal(goal(measure(rows, '2026-06-01'), 'day0').value, null);
});

test('60/90-day means permit multiple distinct graduated habits per user without inventing a target', () => {
  const rows = cohort();
  for (let i = 0; i < 50; i++) for (let j = 0; j < 2; j++) {
    rows.push(event(String(i), 'habit_graduated', '2026-06-30', { habitId: randomUUID() }));
  }
  for (const [id, day] of [['north_star_60', '2026-07-31'], ['north_star_90', '2026-08-30']]) {
    const row = goal(measure(rows, day), id);
    assert.equal(row.value, 2);
    assert.equal(row.numerator, 100);
    assert.equal(row.denominator, 50);
    assert.equal(row.target, null);
  }
  assert.equal(goal(measure(rows, '2026-06-07'), 'd7').value, null);
  assert.equal(goal(measure(rows, '2026-06-07'), 'd7').denominator, null);
});

test('day0 follows local dates across UTC midnight rather than clipping its conversion to a UTC window', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) {
    rows.push(event(String(i), 'signin_succeeded', '2026-06-02', {}, '2026-06-01T23:50:00Z'),
      event(String(i), 'first_checkin', '2026-06-02', { habitId: habit, result: 'did' }, '2026-06-02T00:10:00Z'));
  }
  assert.equal(goal(measure(rows, '2026-06-01'), 'day0').value, 1);
});
