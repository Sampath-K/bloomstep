import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { accountKey, isAdmin, syncSchema, eventSchema, voiceSchema, checkinSchema, reflectionSchema } from '../src/contracts.mjs';

test('partition key binds issuer and subject, never email', () => {
  assert.equal(accountKey('https://issuer', 'alice').length, 64);
  assert.notEqual(accountKey('https://issuer', 'alice'), accountKey('https://issuer', 'bob'));
  assert.notEqual(accountKey('https://issuer', 'alice'), accountKey('https://other', 'alice'));
});
test('admin never inferred from email, name or a truthy value', () => {
  assert.equal(isAdmin(['Bloomstep.Admin']), true);
  for (const value of [true, 'Bloomstep.Admin', ['User'], { role: 'Bloomstep.Admin' }]) assert.equal(isAdmin(value), false);
});
test('telemetry rejects habit text and unregistered events', () => {
  const event = { id: randomUUID(), name: 'checkin', ts: new Date().toISOString() };
  assert.equal(eventSchema.safeParse(event).success, true);
  assert.equal(eventSchema.safeParse({ ...event, body: 'Private habit' }).success, false);
  assert.equal(eventSchema.safeParse({ ...event, name: 'secret' }).success, false);
});
test('clients cannot supply account, public visibility, replies or status', () => {
  const voice = { id: randomUUID(), kind: 'Idea', body: 'Good', rating: null, ts: new Date().toISOString() };
  assert.equal(voiceSchema.safeParse(voice).success, true);
  assert.equal(voiceSchema.safeParse({ ...voice, status: 'shipped' }).success, false);
  assert.equal(voiceSchema.safeParse({ ...voice, userId: 'victim' }).success, false);
});
test('strict limits and valid local dates preserve sync contract', () => {
  const input = { habits: [], checkins: [], reflections: [], voice: [], events: [] };
  assert.equal(syncSchema.safeParse(input).success, true);
  assert.equal(syncSchema.safeParse({ ...input, account: 'victim' }).success, false);
  assert.equal(checkinSchema.safeParse({ id: randomUUID(), habitId: randomUUID(), day: '2026-02-30', result: 'did', reason: null, ts: new Date().toISOString() }).success, false);
});
test('malformed reflection JSON and future timestamp reject safely', () => {
  assert.equal(reflectionSchema.safeParse({ id: randomUUID(), habitId: randomUUID(), items: '{invalid', score: 4, ts: new Date().toISOString() }).success, false);
  assert.equal(eventSchema.safeParse({ id: randomUUID(), name: 'checkin', ts: new Date(Date.now() + 600000).toISOString() }).success, false);
});
