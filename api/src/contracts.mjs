import { z } from 'zod';
import { createHash } from 'node:crypto';

const id = z.uuid();
const text = z.string().trim().min(1).max(200);
const timestamp = z.iso.datetime();
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
  id, habitId: id, items: z.string().transform(s => JSON.parse(s)).pipe(z.array(z.number().int().min(1).max(7)).length(4)),
  score: z.number().min(1).max(7), ts: timestamp,
}).strict().refine(r => Math.abs(r.items.reduce((a, b) => a + b, 0) / 4 - r.score) < .001);
export const voiceSchema = z.object({
  id, kind: z.enum(['Idea', 'Bug', 'Question', 'Praise', 'This felt wrong', 'Rating']),
  body: z.string().trim().min(1).max(2000), rating: z.number().int().min(1).max(5).nullable(), ts: timestamp,
}).strict();
export const eventSchema = z.object({ id, name: z.enum(eventNames), ts: timestamp }).strict();
export const syncSchema = z.object({
  habits: z.array(habitSchema).max(100),
  checkins: z.array(checkinSchema).max(1000),
  reflections: z.array(reflectionSchema).max(100),
  voice: z.array(voiceSchema).max(100),
  events: z.array(eventSchema).max(1000),
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
