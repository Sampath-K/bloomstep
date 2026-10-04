import test from 'node:test';
import assert from 'node:assert/strict';
import { LocalMeasurement, validateReceipt, measurementKey } from '../measurement.mjs';

function fixture() {
  let now = Date.UTC(2026, 9, 5, 12), serial = 0;
  const values = new Map();
  const storage = {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: key => values.delete(key),
  };
  const measurement = new LocalMeasurement(storage, {
    clock: () => now,
    uuid: () => `00000000-0000-4000-8000-${String(++serial).padStart(12, '0')}`,
  });
  return { measurement, values, advance: delta => now += delta };
}

test('no storage or history before explicit consent; only actual later gestures', () => {
  const { measurement, values, advance } = fixture();
  assert.equal(measurement.record('download_click'), false);
  assert.equal(values.size, 0);
  measurement.consent();
  advance(1000);
  measurement.record('download_click');
  const receipt = validateReceipt(measurement.export(), Date.UTC(2026, 9, 5, 12, 0, 1));
  assert.deepEqual(receipt.events.map(e => e.name), ['landing_view', 'download_click']);
  assert.equal(receipt.events[1].ts, '2026-10-05T12:00:01.000Z');
  assert.deepEqual(Object.keys(receipt.events[1]).sort(), ['id', 'name', 'ts']);
  measurement.clear();
  assert.equal(values.size, 0);
  assert.equal(measurement.record('download_click'), false);
});

test('seven-day expiry purges only owned key and does not retroactively restart', () => {
  const { measurement, values, advance } = fixture();
  values.set('unrelated', 'keep');
  measurement.consent();
  advance(7 * 86400000);
  assert.equal(measurement.current(), null);
  assert.equal(values.has(measurementKey), false);
  assert.equal(values.get('unrelated'), 'keep');
  assert.equal(measurement.record('download_click'), false);
});

test('privacy, clocks, bounds and storage failures are explicit', () => {
  const { measurement, advance } = fixture();
  measurement.consent();
  const receipt = JSON.parse(measurement.export());
  assert.throws(() => validateReceipt(JSON.stringify({ ...receipt, email: 'private' })), /receipt/i);
  const privateEvent = structuredClone(receipt);
  privateEvent.events[0].url = 'private';
  assert.throws(() => validateReceipt(JSON.stringify(privateEvent)), /receipt/i);
  const impossibleDate = structuredClone(receipt);
  impossibleDate.consentedAt = '2026-02-30T12:00:00.000Z';
  assert.throws(() => validateReceipt(JSON.stringify(impossibleDate)), /receipt/i);
  assert.throws(() => measurement.record('signin_succeeded'), /observation/i);
  for (let i = 0; i < 31; i++) measurement.record('download_click');
  assert.throws(() => measurement.record('download_click'), /limit/i);
  advance(-1000);
  assert.throws(() => measurement.current(), /clock/i);
  const broken = new LocalMeasurement({
    getItem() { throw Error('private URL'); },
    setItem() { throw Error('private URL'); },
    removeItem() { throw Error('private URL'); },
  });
  assert.throws(() => broken.consent(), /could not be saved/i);
  assert.throws(() => broken.current(), /could not be read/i);
  assert.throws(() => broken.clear(), /could not be removed/i);
});
