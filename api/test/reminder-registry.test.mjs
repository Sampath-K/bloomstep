import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { eventSchema } from '../src/contracts.mjs';
import { eventRegistry, eventJsonSchema } from '../src/event_registry.g.mjs';

test('generated wire schema narrows Windows preference properties without changing other event platforms', () => {
  for (const name of ['reminder_preference_started', 'reminder_preference_disabled', 'reminder_preference_followup']) {
    assert.deepEqual(eventRegistry[name].properties.platform.enum, ['windows']);
    const schema = eventJsonSchema.oneOf.find(row => row.properties.name.const === name);
    assert.deepEqual(schema.properties.properties.properties.platform.enum, ['windows']);
    assert.deepEqual(schema.properties.properties.required, eventRegistry[name].required);
  }
  assert.ok(eventRegistry.checkin.properties.platform.enum.includes('web'));
});

test('new preference facts require exact fresh-disclosure fields; legacy analytics never substitute', () => {
  const properties = { disclosureVersion: 1, consentEpoch: randomUUID(), cohortId: randomUUID(),
    platform: 'windows', localDay: '2026-08-01' };
  for (const name of ['reminder_preference_started', 'reminder_preference_disabled', 'reminder_preference_followup']) {
    const event = { id: randomUUID(), name, ts: '2026-08-01T12:00:00.000Z', properties };
    assert.equal(eventSchema.safeParse(event).success, true);
    for (const key of Object.keys(properties)) {
      const missing = { ...properties };
      delete missing[key];
      assert.equal(eventSchema.safeParse({ ...event, properties: missing }).success, false);
    }
    for (const invalid of [{ ...properties, disclosureVersion: 0 }, { ...properties, platform: 'web' },
      { ...properties, enabled: true }, { ...properties, email: 'synthetic@example.test' }]) {
      assert.equal(eventSchema.safeParse({ ...event, properties: invalid }).success, false);
    }
    assert.equal(eventSchema.safeParse({ ...event, properties: undefined }).success, false);
  }
});
