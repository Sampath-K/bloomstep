import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { accountKey, isAdmin, syncSchema, eventSchema, voiceSchema, checkinSchema, reflectionSchema, newerRecipe, settingSchema } from '../src/contracts.mjs';

test('settings exclude remote consent and validate quiet hours', () => {
  const setting = { key: 'quietStart', value: '1200', updated: new Date().toISOString() };
  assert.equal(settingSchema.safeParse(setting).success, true);
  assert.equal(settingSchema.safeParse({...setting, value: '1500'}).success, false);
  assert.equal(settingSchema.safeParse({...setting, key: 'analytics', value: 'true'}).success, false);
});
test('cadence settings accept only strict UTC timestamps without loosening boolean/minute validation', () => {
  const updated = new Date().toISOString();
  for (const key of ['weeklyLast', 'ratingPromptedAt']) {
    for (const value of ['2026-09-01T12:00:00Z', '2026-09-01T12:00:00.123456Z']) {
      assert.equal(settingSchema.safeParse({ key, value, updated }).success, true);
    }
    for (const value of ['true', '1200', '2026-09-01', '2026-09-01T12:00:00', '2026-09-01T12:00:00+00:00',
      '2026-02-30T12:00:00Z', '2026-09-01T12:00:00.1234567Z', 'x'.repeat(41), new Date(Date.now() + 600000).toISOString()]) {
      assert.equal(settingSchema.safeParse({ key, value, updated }).success, false, `${key}: ${value}`);
    }
    assert.equal(settingSchema.safeParse({ key, value: updated, updated, consent: true }).success, false);
  }
  for (const [key, value] of [['quietStart', updated], ['reducedMotion', updated], ['quietEnd', 'true'], ['fewerReminders', '1']]) {
    assert.equal(settingSchema.safeParse({ key, value, updated }).success, false);
  }
});

test('cadence telemetry accepts only envelopes, never reflection text or rating values', () => {
  for (const name of ['weekly_reflection', 'rating_prompted']) {
    const event = { id: randomUUID(), name, ts: new Date().toISOString() };
    assert.equal(eventSchema.safeParse(event).success, true);
    for (const extra of [{ body: 'Private reflection' }, { rating: 5 }, { habitId: randomUUID() }, { consent: true }]) {
      assert.equal(eventSchema.safeParse({ ...event, ...extra }).success, false);
    }
  }
});
test('recipe ties use the same field ordering and preserve microsecond precedence', () => {
  const first = {aspiration:'Calm',anchor:'coffee',behavior:'breathe',celebration:'smile',species:'Fern',status:'active',updated:'2026-09-01T12:00:00.000000Z'};
  const second = {...first,anchor:'zzz'};
  assert.equal(newerRecipe(second,first),true);
  assert.equal(newerRecipe(first,second),false);
  assert.equal(newerRecipe({...first,updated:'2026-09-01T12:00:00.000001Z'},second),true);
});

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
test('rating feedback permits optional text only with a valid rating', () => {
  const voice = { id: randomUUID(), kind: 'Rating', body: '', rating: 5, ts: new Date().toISOString() };
  assert.equal(voiceSchema.safeParse(voice).success, true);
  assert.equal(voiceSchema.safeParse({ ...voice, body: '   ', rating: 1 }).success, true);
  assert.equal(voiceSchema.safeParse({ ...voice, body: 'Helpful', rating: 3 }).success, true);
  for (const rating of [null, 0, 6, 2.5, '5']) {
    assert.equal(voiceSchema.safeParse({ ...voice, rating }).success, false);
    assert.equal(voiceSchema.safeParse({ ...voice, body: 'Helpful', rating }).success, false);
  }
  for (const kind of ['Idea', 'Bug', 'Question', 'Praise', 'This felt wrong']) {
    assert.equal(voiceSchema.safeParse({ ...voice, kind, rating: null }).success, false);
    assert.equal(voiceSchema.safeParse({ ...voice, kind, body: '  ', rating: 5 }).success, false);
    assert.equal(voiceSchema.safeParse({ ...voice, kind, body: 'Useful', rating: null }).success, true);
  }
  assert.equal(voiceSchema.safeParse({ ...voice, body: 'x'.repeat(2001) }).success, false);
  assert.equal(voiceSchema.safeParse({ ...voice, status: 'received' }).success, false);
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
