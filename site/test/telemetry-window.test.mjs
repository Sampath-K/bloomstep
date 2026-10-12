import assert from 'node:assert/strict';
import test from 'node:test';
import { telemetryWindowStart } from '../telemetry-window.mjs';

const span = 2 * 60 * 60 * 1000;
const utcDay = ms => new Date(ms).toISOString().slice(0, 10);

test('keeps the real clock when the simulated acceptance window stays inside one UTC day', () => {
  const real = Date.parse('2026-10-10T08:00:00.000Z');
  assert.equal(telemetryWindowStart(real, span), real);
});

test('never lets the one-day persisted readback window cross UTC midnight', () => {
  for (const real of [Date.parse('2026-10-10T23:34:46.000Z'), Date.parse('2026-10-10T23:59:31.000Z'),
    Date.parse('2026-10-10T22:00:00.001Z')]) {
    const start = telemetryWindowStart(real, span);
    assert.ok(start <= real, 'simulated clock must not move into the future');
    assert.equal(utcDay(start), utcDay(real));
    assert.equal(utcDay(start + span), utcDay(start));
  }
});

test('rejects windows that cannot fit inside a UTC day', () => {
  assert.throws(() => telemetryWindowStart(Date.now(), 24 * 60 * 60 * 1000));
});
