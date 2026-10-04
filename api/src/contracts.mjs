import { z } from 'zod';
import { createHash } from 'node:crypto';

const id = z.uuid();
const text = z.string().trim().min(1).max(200);
const timestamp = z.iso.datetime()
  .refine(value => !/\.\d{7,}Z$/.test(value), 'Microsecond precision is the maximum.')
  .refine(value => Date.parse(value) <= Date.now() + 300000, 'Timestamp is too far in the future.');
export const eventNames = ['recipe_created', 'checkin', 'reflection', 'habit_graduated', 'feedback_submitted', 'share_initiated', 'reminder_sent', 'signin_succeeded'];
export const habitSchema = z.object({
  id, aspiration: text, anchor: text, behavior: text, celebration: text,
  species: z.enum(['Cosmos', 'Sunflower', 'Fern']),
  stage: z.number().int().min(0).max(4), status: z.enum(['active', 'graduated', 'archived']),
  updated: timestamp,
}).strict();
export const checkinSchema = z.object({
  id, habitId: id,
  day: z.iso.date(), result: z.enum(['did', 'didMore', 'notToday']).nullable(),
  reason: z.enum(['forgot', 'too hard', 'anchor', 'motivation']).nullable(),
  ts: timestamp,
}).strict();
export const reflectionSchema = z.object({
  id, habitId: id, items: z.string().transform((s, context) => {
    try { return JSON.parse(s); }
    catch { context.addIssue({ code: 'custom', message: 'Invalid reflection JSON' }); return z.NEVER; }
  }).pipe(z.array(z.number().int().min(1).max(7)).length(4)),
  score: z.number().min(1).max(7), ts: timestamp,
}).strict().refine(r => Math.abs(r.items.reduce((a, b) => a + b, 0) / 4 - r.score) < .001);
export const voiceSchema = z.object({
  id, kind: z.enum(['Idea', 'Bug', 'Question', 'Praise', 'This felt wrong', 'Rating']),
  body: z.string().trim().min(1).max(2000), rating: z.number().int().min(1).max(5).nullable(), ts: timestamp,
}).strict();
export const eventSchema = z.object({ id, name: z.enum(eventNames), ts: timestamp }).strict();
export const settingSchema = z.object({
  key: z.enum(['reducedMotion', 'reminderMinute', 'quietStart', 'quietEnd', 'fewerReminders']),
  value: z.string().max(5), updated: timestamp,
}).strict().refine(setting =>
  ['reducedMotion', 'fewerReminders'].includes(setting.key)
    ? ['true', 'false'].includes(setting.value)
    : /^\d{1,4}$/.test(setting.value) && Number(setting.value) < 1440,
);
export const syncSchema = z.object({
  habits: z.array(habitSchema).max(100),
  checkins: z.array(checkinSchema).max(1000),
  reflections: z.array(reflectionSchema).max(100),
  voice: z.array(voiceSchema).max(100),
  events: z.array(eventSchema).max(1000),
  settings: z.array(settingSchema).max(20).default([]),
}).strict();
export const replySchema = z.object({
  id, status: z.enum(['received', 'under review', 'planned', 'in progress', 'shipped', 'not planned']),
  reply: z.string().trim().min(1).max(2000),
}).strict();

/** @param {string} issuer @param {string} subject */
export function accountKey(issuer, subject) {
  return createHash('sha256').update(`${issuer}|${subject}`).digest('hex');
}

/** @param {unknown} roles */
export function isAdmin(roles) {
  return Array.isArray(roles) && roles.includes('Bloomstep.Admin');
}

/** @param {string} value */
function timestampKey(value) {
  return value.replace(/(?:\.(\d+))?Z$/, (_, digits = '') => `.${digits.padEnd(6, '0')}Z`);
}
/** @param {Record<string, unknown>} incoming @param {Record<string, unknown>} existing @param {string[]} fields */
function newerVersion(incoming, existing, fields) {
  const a = timestampKey(String(incoming.updated));
  const b = timestampKey(String(existing.updated));
  return a !== b ? a > b : JSON.stringify(fields.map(key => incoming[key])) > JSON.stringify(fields.map(key => existing[key]));
}
/** @param {Record<string, unknown>} incoming @param {Record<string, unknown>} existing */
export function newerRecipe(incoming, existing) {
  return newerVersion(incoming, existing, ['aspiration', 'anchor', 'behavior', 'celebration', 'species', 'status']);
}
/** @param {Record<string, unknown>} incoming @param {Record<string, unknown>} existing */
export function newerSetting(incoming, existing) {
  return newerVersion(incoming, existing, ['value']);
}
