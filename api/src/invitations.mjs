import { createHash, randomBytes } from 'node:crypto';
import { createInvitationSchema, redeemInvitationSchema, invitationStatusQuerySchema, invitationLimits, sharedRecipeSchema } from './invitation-contracts.mjs';

const partition = '__invitations';
/** @param {string} value */
const hash = value => createHash('sha256').update(value).digest('hex');
/** @param {string} owner @param {string} direction @param {string} codeHash */
const rewardId = (owner, direction, codeHash) => `referral:reward:${hash(`${owner}|${direction}|${codeHash}`)}`;
/** @param {string} ts */
const timestampKey = ts => ts.replace(/(?:\.(\d+))?Z$/, (_, digits = '') => `.${digits.padEnd(6, '0')}Z`);

/** The hooks use the same authenticated account ETag gates and preview ledger as sync.
 * @param {any} hooks */
export function createInvitations(hooks) {
  const { container, clock, active, batch, reserve, gateBody, ServiceError, actor, body, rateLimit } = hooks;
  const read = async (/** @type {string} */ id, /** @type {string} */ owner) => (await container().item(id, owner).read()).resource;
  const expires = (/** @type {number} */ seconds) => new Date(clock().getTime() + seconds * 1000).toISOString();
  const remaining = (/** @type {string} */ expiry) => Math.max(1, Math.ceil((Date.parse(expiry) - clock().getTime()) / 1000));
  const gone = (/** @type {any} */ error) => error?.status === 410;
  /** @param {string} owner @param {string} type @param {number} maximum */
  async function list(owner, type, maximum) {
    const { resources } = await container().items.query({
      query: `SELECT TOP ${maximum + 1} * FROM c WHERE c.type = "${type}"`,
    }, { partitionKey: owner }).fetchAll();
    if (resources.length > maximum) throw new ServiceError(429, 'Invitation preview volume exceeded.');
    return resources;
  }
  /** @param {string} owner @param {string[]} ids */
  async function remove(owner, ids) {
    const gate = await read('account', owner);
    const existing = (await Promise.all(ids.map(id => read(id, owner)))).filter(Boolean);
    if (!existing.length) return;
    if (!gate || gate.deleted) {
      for (const row of existing) await container().item(row.id, owner).delete();
      return;
    }
    await batch([
      { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: gateBody(gate) },
      ...existing.map(row => ({ operationType: 'Delete', id: row.id })),
    ], owner);
  }
  /** @param {any} receipt */
  async function purge(receipt) {
    const index = await read(receipt.hash, partition);
    const peer = receipt.peer ?? index?.invitee;
    if (index) await container().item(index.id, partition).delete();
    if (peer) {
      const otherDirection = receipt.direction === 'incoming' ? 'outgoing' : 'incoming';
      const otherReceipt = otherDirection === 'incoming' ? 'invitation:incoming' : `invitation:receipt:${receipt.invitationId}`;
      const related = await read(otherReceipt, peer);
      await remove(peer, [...(related?.hash === receipt.hash ? [otherReceipt] : []),
        ...(otherDirection === 'outgoing' ? [`invitation:secret:${receipt.invitationId}`] : []),
        rewardId(peer, otherDirection, receipt.hash)]);
    }
    await remove(receipt.userId, [receipt.id,
      ...(receipt.direction === 'outgoing' ? [`invitation:secret:${receipt.invitationId}`] : []),
      rewardId(receipt.userId, receipt.direction, receipt.hash)]);
  }
  /** @param {string} owner @param {any[]} checkins */
  async function observePractice(owner, checkins) {
    const gate = await active(owner, false);
    if (gate.firstPracticeAt) return;
    const effective = new Map();
    const ordered = [...checkins].sort((a, b) => timestampKey(a.ts).localeCompare(timestampKey(b.ts)) || a.id.localeCompare(b.id));
    for (const row of ordered) effective.set(`${row.habitId}:${row.day}`, row);
    const candidates = [...effective.values()].filter(row => ['did', 'didMore'].includes(row.result) &&
      row.day <= clock().toISOString().slice(0, 10) && Date.parse(row.ts) <= clock().getTime() + 300000)
      .sort((a, b) => timestampKey(a.ts).localeCompare(timestampKey(b.ts)) || a.id.localeCompare(b.id));
    let positive;
    for (const candidate of candidates) {
      const stored = await read(`checkins:${candidate.id}`, owner);
      if (stored?.referralEligible === true) { positive = candidate; break; }
    }
    if (!positive) return;
    await reserve();
    await batch([{ operationType: 'Replace', id: 'account', ifMatch: gate._etag,
      resourceBody: { ...gateBody(gate), firstPracticeAt: clock().toISOString(), firstPracticeCheckin: positive.id } }], owner);
  }
  /** @param {any} incoming */
  async function mirror(incoming) {
    await active(incoming.peer, false);
    const id = `invitation:receipt:${incoming.invitationId}`;
    const outgoing = await read(id, incoming.peer);
    if (!outgoing || outgoing.hash !== incoming.hash) throw new ServiceError(410, 'Invitation data is unavailable.');
    if (outgoing.peer && outgoing.peer !== incoming.userId) throw new ServiceError(409, 'Invitation has already been accepted.');
    if (!outgoing.peer) {
      const gate = await active(incoming.peer, false);
      await reserve();
      await batch([
        { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: gateBody(gate) },
        { operationType: 'Replace', id, ifMatch: outgoing._etag, resourceBody: {
          ...outgoing, peer: incoming.userId, acceptedAt: incoming.acceptedAt, expiresAt: incoming.expiresAt,
          state: 'accepted', ttl: remaining(incoming.expiresAt),
        } },
      ], incoming.peer);
    }
  }
  /** @param {any} incoming */
  async function reconcile(incoming) {
    try {
      const invitedGate = await active(incoming.userId, false);
      await mirror(incoming);
      await active(incoming.peer, false);
      if (!invitedGate.firstPracticeAt || invitedGate.firstPracticeAt < incoming.acceptedAt) return;
      if (invitedGate.firstPracticeAt >= incoming.expiresAt) return;
      const stored = await read(`checkins:${invitedGate.firstPracticeCheckin}`, incoming.userId);
      if (!stored || !['did', 'didMore'].includes(stored.record.result) ||
          typeof stored.receivedAt !== 'string' || !Number.isFinite(Date.parse(stored.receivedAt)) ||
          stored.referralEligible !== true || stored.receivedAt < incoming.acceptedAt ||
          timestampKey(stored.record.ts) < timestampKey(incoming.acceptedAt)) return;
      for (const [owner, direction] of [[incoming.userId, 'incoming'], [incoming.peer, 'outgoing']]) {
        await active(incoming.userId, false);
        await active(incoming.peer, false);
        const id = rewardId(owner, direction, incoming.hash);
        if (await read(id, owner)) continue;
        const gate = await active(owner, false);
        const earned = Number(gate.referralRewards ?? 0);
        if (earned >= invitationLimits.rewards) throw new ServiceError(429, 'Cosmetic reward preview cap reached.');
        await reserve(1);
        await batch([
          { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: { ...gateBody(gate), referralRewards: earned + 1 } },
          { operationType: 'Create', resourceBody: { id, userId: owner, type: 'referral_reward',
            cosmetic: 'rare_flower', state: 'pending', grantedAt: clock().toISOString(), ttl: remaining(incoming.expiresAt) } },
        ], owner);
      }
      for (const [owner, id] of [[incoming.userId, 'invitation:incoming'], [incoming.peer, `invitation:receipt:${incoming.invitationId}`]]) {
        const receipt = await read(id, owner);
        if (!receipt || receipt.state === 'rewarded') continue;
        const direction = owner === incoming.userId ? 'incoming' : 'outgoing';
        const grant = await read(rewardId(owner, direction, incoming.hash), owner);
        if (!grant) throw new ServiceError(409, 'Reward preparation changed; retry status.');
        const gate = await active(owner, false);
        await reserve();
        await batch([
          { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: gateBody(gate) },
          { operationType: 'Replace', id, ifMatch: receipt._etag, resourceBody: { ...receipt, state: 'rewarded', ttl: remaining(receipt.expiresAt) } },
          { operationType: 'Replace', id: grant.id, ifMatch: grant._etag, resourceBody: { ...grant, state: 'granted', ttl: -1 } },
        ], owner);
      }
      await active(incoming.userId, false);
      await active(incoming.peer, false);
    } catch (error) {
      if (gone(error)) await purge(incoming);
      throw error;
    }
  }
  /** @param {string} owner */
  async function resume(owner) {
    const incoming = await read('invitation:incoming', owner);
    if (incoming) await reconcile(incoming);
  }
  /** @param {any} request */
  async function createInvitation(request) {
    const { userId } = await actor(request);
    const parsed = createInvitationSchema.safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Invitation payload failed validation.');
    const data = parsed.data;
    const digest = hash(JSON.stringify(data));
    const id = `invitation:secret:${data.requestId}`;
    await reserve();
    await rateLimit(userId);
    const gate = await active(userId);
    let secret = await read(id, userId);
    if (secret) {
      if (secret.digest !== digest) throw new ServiceError(409, 'Invitation request ID was reused with different data.');
      if (secret.expiresAt <= clock().toISOString()) throw new ServiceError(410, 'Invitation has expired.');
    } else {
      const prior = gate.invitationRequests?.[data.requestId];
      if (prior) throw new ServiceError(prior === digest ? 410 : 409, 'Invitation request ID cannot be reused.');
      const old = await read(`invitation:receipt:${data.requestId}`, userId);
      if (old) throw new ServiceError(410, 'Invitation code is no longer available.');
      const created = Number(gate.invitationCreated ?? 0);
      const day = clock().toISOString().slice(0, 10);
      const daily = gate.invitationDay === day ? Number(gate.invitationDaily ?? 0) : 0;
      if (created >= invitationLimits.created || daily >= invitationLimits.createdPerDay) throw new ServiceError(429, 'Invitation preview cap reached.');
      const token = randomBytes(32).toString('base64url');
      secret = { id, userId, type: 'invitation_secret', invitationId: data.requestId, digest,
        token, hash: hash(token), channel: data.channel, recipeCard: data.recipeCard ?? null,
        createdAt: clock().toISOString(), expiresAt: expires(invitationLimits.codeSeconds), ttl: invitationLimits.codeSeconds };
      await reserve(3);
      await batch([
        { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: { ...gateBody(gate),
          invitationCreated: created + 1, invitationDay: day, invitationDaily: daily + 1,
          invitationRequests: { ...gate.invitationRequests, [data.requestId]: digest } } },
        { operationType: 'Create', resourceBody: secret },
        { operationType: 'Create', resourceBody: { id: `invitation:receipt:${data.requestId}`, userId, type: 'invitation_receipt',
          invitationId: data.requestId, hash: secret.hash, channel: data.channel, direction: 'outgoing',
          createdAt: secret.createdAt, expiresAt: secret.expiresAt, state: 'created', ttl: invitationLimits.receiptSeconds } },
      ], userId);
    }
    const index = await read(secret.hash, partition);
    if (!index) {
      try { await active(userId, false); }
      catch (error) {
        if (gone(error)) await purge({ id: `invitation:receipt:${secret.invitationId}`, userId, invitationId: secret.invitationId, hash: secret.hash, direction: 'outgoing' });
        throw error;
      }
      try {
        await container().items.create({ id: secret.hash, userId: partition, type: 'invitation_code',
          inviter: userId, invitationId: secret.invitationId, expiresAt: secret.expiresAt,
          ttl: remaining(secret.expiresAt) });
      } catch (error) {
        if (/** @type {any} */ (error)?.code !== 409) throw error;
      }
    }
    await active(userId, false);
    return { jsonBody: { invitationId: secret.invitationId, token: secret.token, channel: secret.channel,
      expiresAt: secret.expiresAt, recipeCard: secret.recipeCard } };
  }
  /** @param {any} request */
  async function redeemInvitation(request) {
    const { userId } = await actor(request);
    const parsed = redeemInvitationSchema.safeParse(await body(request));
    if (!parsed.success) throw new ServiceError(400, 'Invitation redemption failed validation.');
    const data = parsed.data;
    const key = hash(data.token);
    await reserve();
    await rateLimit(userId);
    let gate = await active(userId);
    let incoming = await read('invitation:incoming', userId);
    if (incoming) {
      if (incoming.requestId !== data.requestId || incoming.hash !== key) throw new ServiceError(409, 'Account has already accepted an invitation.');
      await reconcile(incoming);
    } else {
      if (gate.invitationUsed || gate.firstPracticeAt || gate.gardenPositiveSeen) throw new ServiceError(409, 'Invitation attribution is only available before first practice.');
      const garden = await hooks.readGarden(userId);
      if (garden.checkins.some((/** @type {any} */ row) => ['did', 'didMore'].includes(row.result))) throw new ServiceError(409, 'Prior practice cannot be attributed.');
      const index = await read(key, partition);
      if (!index || index.expiresAt <= clock().toISOString()) throw new ServiceError(410, 'Invitation is unavailable or expired.');
      if (index.inviter === userId) throw new ServiceError(400, 'Self invitations are not eligible.');
      await active(index.inviter, false);
      if (index.invitee && (index.invitee !== userId || index.requestId !== data.requestId)) throw new ServiceError(409, 'Invitation has already been accepted.');
      if (!index.invitee) {
        await reserve();
        try { await container().item(key, partition).replace({ ...index, invitee: userId, requestId: data.requestId, ttl: remaining(index.expiresAt) },
          { accessCondition: { type: 'IfMatch', condition: index._etag } }); }
        catch (error) {
          if ([409, 412].includes(Number(/** @type {any} */ (error)?.code))) throw new ServiceError(409, 'Concurrent redemption; retry the same request.');
          throw error;
        }
      }
      gate = await active(userId, false);
      if (gate.invitationUsed || gate.firstPracticeAt || gate.gardenPositiveSeen) throw new ServiceError(409, 'Account is no longer eligible.');
      incoming = { id: 'invitation:incoming', userId, type: 'invitation_receipt', direction: 'incoming',
        hash: key, invitationId: index.invitationId, requestId: data.requestId, peer: index.inviter,
        channel: (await read(`invitation:secret:${index.invitationId}`, index.inviter))?.channel ?? 'link',
        acceptedAt: clock().toISOString(), expiresAt: expires(invitationLimits.receiptSeconds),
        state: 'accepted', ttl: invitationLimits.receiptSeconds };
      await reserve(1);
      await batch([
        { operationType: 'Replace', id: 'account', ifMatch: gate._etag, resourceBody: { ...gateBody(gate), invitationUsed: true } },
        { operationType: 'Create', resourceBody: incoming },
      ], userId);
      await reconcile(incoming);
    }
    const secret = await read(`invitation:secret:${incoming.invitationId}`, incoming.peer);
    await active(userId, false);
    await active(incoming.peer, false);
    return { jsonBody: { invitationId: incoming.invitationId, channel: incoming.channel,
      acceptedAt: incoming.acceptedAt, expiresAt: incoming.expiresAt,
      recipeCard: secret && secret.expiresAt > clock().toISOString() ? secret.recipeCard : null,
      status: (await read('invitation:incoming', userId))?.state ?? 'unavailable' } };
  }
  /** @param {any} request */
  async function invitationStatus(request) {
    const { userId } = await actor(request);
    if (!invitationStatusQuerySchema.safeParse(Object.fromEntries(request.query)).success) throw new ServiceError(400, 'Invalid invitation status query.');
    await reserve();
    await rateLimit(userId);
    const receipts = await list(userId, 'invitation_receipt', invitationLimits.receipts);
    for (const receipt of receipts) {
      try {
        if (receipt.direction === 'incoming') await reconcile(receipt);
        else if (receipt.peer) {
          const incoming = await read('invitation:incoming', receipt.peer);
          if (incoming?.hash === receipt.hash) await reconcile(incoming);
          else {
            const peerGate = await read('account', receipt.peer);
            if (!peerGate || peerGate.deleted) await purge(receipt);
          }
        }
      } catch (error) { if (!gone(error)) throw error; }
    }
    const current = await list(userId, 'invitation_receipt', invitationLimits.receipts);
    const rewards = await list(userId, 'referral_reward', invitationLimits.rewards);
    const secrets = request.query.get('export') === 'true' ? await list(userId, 'invitation_secret', invitationLimits.created) : [];
    for (const receipt of current) if (receipt.peer) await active(receipt.peer, false);
    await active(userId, false);
    return { jsonBody: {
      invitations: current.map((/** @type {any} */ row) => ({
        invitationId: row.invitationId, direction: row.direction, channel: row.channel,
        acceptedAt: row.acceptedAt ?? null, expiresAt: row.expiresAt,
        status: row.state === 'rewarded' ? 'rewarded' : row.expiresAt <= clock().toISOString() ? 'expired' : row.state,
      })).sort((/** @type {any} */ a, /** @type {any} */ b) => a.invitationId.localeCompare(b.invitationId)),
      rewards: rewards.filter((/** @type {any} */ row) => row.state === 'granted')
        .map((/** @type {any} */ row) => ({ id: hash(row.id), cosmetic: row.cosmetic, grantedAt: row.grantedAt }))
        .sort((/** @type {any} */ a, /** @type {any} */ b) => a.id.localeCompare(b.id)),
      ...(request.query.get('export') === 'true' ? { sharedRecipes: secrets.filter((/** @type {any} */ row) => row.recipeCard && row.expiresAt > clock().toISOString())
        .map((/** @type {any} */ row) => ({ invitationId: row.invitationId, expiresAt: row.expiresAt, recipeCard: sharedRecipeSchema.parse(row.recipeCard) })) } : {}),
      definition: 'Cosmetic-only rare flowers for server-observed first positive garden check-in after acceptance. Two account-partition grants are a retryable saga, never a cross-partition atomic transaction.',
    } };
  }
  /** @param {string} owner */
  async function deleteLinks(owner) {
    for (const receipt of await list(owner, 'invitation_receipt', invitationLimits.receipts)) await purge(receipt);
  }
  return { createInvitation, redeemInvitation, invitationStatus, observePractice, resume, deleteLinks };
}
