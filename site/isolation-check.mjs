const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);

export function isolationIdentity(value) {
  if (!value || !hash(value.userId)) throw Error('Caller identity is unavailable.');
  return value.userId;
}

export function isolationPayload(userId, peer) {
  const peerUserId = peer.trim();
  if (!hash(userId) || !hash(peerUserId) || peerUserId === userId) {
    throw Error('Show my account hash first, then paste the different account hash from the other signed-in tab.');
  }
  return { peerUserId };
}

export function isolationSummary(value, expectedUserId) {
  const keys = ['habits', 'checkins', 'reflections', 'voice', 'settings'];
  if (!value || !hash(expectedUserId) || value.userId !== expectedUserId ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value.auditId ?? '') ||
      keys.some(key => !Number.isSafeInteger(value.counts?.[key]) || value.counts[key] < 0) ||
      value.checks?.ownRead !== 200 || value.checks?.ownEmptySync !== 200 ||
      value.checks?.foreignRead !== 400 || value.checks?.foreignWrite !== 400 ||
      ![403, 'admin-authorized-not-tested'].includes(value.checks?.teamFeedback)) {
    throw Error('Isolation evidence is incomplete or failed. No acceptance claimed.');
  }
  const team = value.checks.teamFeedback === 403 ? 'Ordinary-account team feedback access denied (403).'
    : 'Admin team access is intentionally authorized; this check covers customer sync only.';
  return `Verified customer sync boundary. Own userId: ${value.userId}. Own habits: ${value.counts.habits}; own checkins: ${value.counts.checkins}; own reflections: ${value.counts.reflections}; Own feedback: ${value.counts.voice}; own settings: ${value.counts.settings}. Own read and empty sync succeeded (200); peer-account read/write selectors rejected (400). ${team} Audit ID: ${value.auditId}. No peer data or feedback content was returned; no garden records were changed.`;
}
