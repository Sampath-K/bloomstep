import { z } from 'zod';

const text = z.string().trim().min(1).max(200);
export const sharedRecipeSchema = z.strictObject({
  explicitChoice: z.literal(true),
  templateCategory: z.enum(['calm', 'focus', 'health', 'learning', 'connection']),
  aspiration: text, anchor: text, behavior: text, celebration: text,
  species: z.enum(['Cosmos', 'Sunflower', 'Fern']),
});
export const invitationChannelSchema = z.enum(['link', 'email', 'qr', 'native']);
export const createInvitationSchema = z.strictObject({
  requestId: z.uuid(), channel: invitationChannelSchema, recipeCard: sharedRecipeSchema.optional(),
});
export const redeemInvitationSchema = z.strictObject({
  requestId: z.uuid(), token: z.string().regex(/^[A-Za-z0-9_-]{43}$/).refine(value =>
    Buffer.from(value, 'base64url').length === 32 && Buffer.from(value, 'base64url').toString('base64url') === value),
});
export const invitationStatusQuerySchema = z.strictObject({ export: z.literal('true').optional() });
export const invitationLimits = Object.freeze({ created: 10, createdPerDay: 2, codeSeconds: 604800, receiptSeconds: 2592000, receipts: 11, rewards: 11 });
