import { z } from 'zod';
import { createHash } from 'node:crypto';
import { eventRegistry, registryVersion } from './event_registry.g.mjs';

const id = z.uuid();
const text = z.string().trim().min(1).max(200);
const timestamp = z.iso.datetime()
  .refine(value => !/\.\d{7,}Z$/.test(value), 'Microsecond precision is the maximum.')
  .refine(value => Date.parse(value) <= Date.now() + 300000, 'Timestamp is too far in the future.');
export const eventNames = Object.keys(eventRegistry);
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
  body: z.string().trim().max(2000), rating: z.number().int().min(1).max(5).nullable(), ts: timestamp,
}).strict().refine(voice => voice.kind === 'Rating' ? voice.rating !== null : voice.body.length > 0,
  'Ratings require a score; other feedback requires text.');
/** @param {any} rule */
function propertySchema(rule) {
  if (rule.enum) return z.enum(rule.enum);
  if (rule.type === 'uuid') return z.uuid();
  if (rule.type === 'date') return z.iso.date();
  const number = z.number().min(rule.min).max(rule.max);
  return rule.type === 'integer' ? number.int() : number;
}
const propertySchemas = Object.fromEntries(Object.entries(eventRegistry).map(([name, entry]) => [
  name, z.object(Object.fromEntries(Object.entries(entry.properties).map(([key, rule]) => [key, propertySchema(rule).optional()]))).strict(),
]));
export const eventSchema = z.object({
  id, name: z.enum(eventNames), ts: timestamp, schemaVersion: z.literal(registryVersion).optional(),
  properties: z.record(z.string(), z.unknown()).optional(),
}).strict().superRefine((event, context) => {
  if (event.properties && !propertySchemas[event.name].safeParse(event.properties).success) {
    context.addIssue({ code: 'custom', message: 'Invalid event-specific properties.', path: ['properties'] });
  }
  if (event.properties?.measurementSource !== undefined) {
    const website = event.properties.measurementSource === 'website_receipt';
    const allowed = website ? ['landing_view', 'invite_link_open', 'download_click']
      : ['installer_started', 'install_completed', 'first_launch', 'signin_view'];
    if (!allowed.includes(event.name) || event.properties.platform !== (website ? 'web' : 'windows')
        || event.properties.channel !== (website ? 'website' : 'direct')) {
      context.addIssue({ code: 'custom', message: 'Receipt source metadata is inconsistent.', path: ['properties'] });
    }
  }
});
export const settingSchema = z.object({
  key: z.enum(['reducedMotion', 'reminderMinute', 'quietStart', 'quietEnd', 'fewerReminders', 'weeklyLast', 'ratingPromptedAt']),
  value: z.string().max(40), updated: timestamp,
}).strict().refine(setting =>
  ['weeklyLast', 'ratingPromptedAt'].includes(setting.key)
    ? timestamp.safeParse(setting.value).success
    : ['reducedMotion', 'fewerReminders'].includes(setting.key)
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
  deletions: z.array(z.object({
    id, type: z.enum(['habits', 'voice']), recordId: id, ts: timestamp,
  }).strict()).max(100).default([]),
}).strict();
export const replySchema = z.object({
  id, status: z.enum(['received', 'under review', 'planned', 'in progress', 'shipped', 'not planned']),
  reply: z.string().trim().min(1).max(2000),
  requestId: id.optional(),
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
