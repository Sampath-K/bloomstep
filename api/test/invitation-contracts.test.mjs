import test from 'node:test';
import assert from 'node:assert/strict';
import { sharedRecipeSchema } from '../src/invitation-contracts.mjs';

const card = { explicitChoice: true, aspiration: 'Calm', anchor: 'After tea',
  behavior: 'One breath', celebration: 'Smile', species: 'Fern' };

test('approved existing recipes need no category and never acquire an inferred category', () => {
  assert.deepEqual(sharedRecipeSchema.parse(card), card);
  assert.equal(Object.hasOwn(sharedRecipeSchema.parse(card), 'templateCategory'), false);
  for (const templateCategory of ['calm', 'focus', 'health', 'learning', 'connection']) {
    const legacy = { ...card, templateCategory };
    assert.deepEqual(sharedRecipeSchema.parse(legacy), legacy);
  }
});

test('optional category does not relax exact approval, required recipe fields or private-field rejection', () => {
  for (const invalid of [
    { ...card, templateCategory: null },
    { ...card, templateCategory: 'inferred' },
    { ...card, templateCategory: '' },
    { ...card, explicitChoice: false },
    { ...card, behavior: '' },
    { ...card, habitId: 'private-id' },
    { ...card, account: 'private-account' },
  ]) assert.equal(sharedRecipeSchema.safeParse(invalid).success, false);
  for (const field of Object.keys(card)) {
    const incomplete = { ...card };
    delete incomplete[field];
    assert.equal(sharedRecipeSchema.safeParse(incomplete).success, false, field);
  }
});
