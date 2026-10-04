import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInvitation, rememberInvitation, savedInvitation, nativeInvitationUrl } from '../invitation-landing.mjs';

const token = 'A'.repeat(43);
test('landing hands off only opaque canonical invitation parameters', () => {
  const intent = parseInvitation(`?invite=${token}&channel=qr`);
  assert.equal(nativeInvitationUrl(intent), `bloomstep://invite?code=${token}&channel=qr`);
  assert.equal(parseInvitation(''), null);
  assert.equal(parseInvitation('?invite=garden').generic, true);
  for (const query of [`?invite=${token}&channel=evil`, `?invite=${token}&invite=${token}`,
    `?invite=${token}&email=private`, '?invite=invalid']) assert.throws(() => parseInvitation(query));
});
test('optional functional browser storage survives install without account metadata', () => {
  let raw = null;
  const storage = { setItem: (_, value) => raw = value, getItem: () => raw, removeItem: () => raw = null };
  const now = Date.parse('2026-10-04T00:00:00Z');
  rememberInvitation(storage, { code: token, channel: 'email' }, now);
  assert.equal(savedInvitation(storage, now + 86400000).code, token);
  assert.equal(raw.includes('email@'), false);
  assert.throws(() => savedInvitation(storage, now + 7 * 86400000));
  assert.equal(raw, null);
});
test('corrupt browser state is rejected, not treated as a valid referral', () => {
  const storage = { getItem: () => '{"version":1,"code":"invalid"}', removeItem: () => {} };
  assert.throws(() => savedInvitation(storage, Date.now()));
});
