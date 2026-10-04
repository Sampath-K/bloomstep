import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT, exportJWK } from 'jose';
import { createAggregateAuthenticator } from '../src/aggregate-auth.mjs';
import { ServiceError } from '../src/backend.mjs';

test('worker verifier pins separate issuer/audience/keys/role and leaves primary admin fallback strict', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'test-key', alg: 'RS256', use: 'sig' };
  const config = { issuer: 'https://resource.example.invalid/tenant/v2.0', audience: 'worker-api', jwksUri: `https://keys.example.invalid/jwks` };
  // Tests inject the verifier's trusted key resolver; production uses HTTPS remote JWKS.
  const { createLocalJWKSet } = await import('jose');
  const primary = async () => { throw new ServiceError(401, 'Primary token rejected.'); };
  const authenticate = createAggregateAuthenticator(config, primary, createLocalJWKSet({ keys: [jwk] }));
  const token = (overrides = {}) => new SignJWT({ roles: ['Bloomstep.AggregateWriter'], ...overrides })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer(config.issuer).setAudience(config.audience)
    .setSubject('worker-subject').setIssuedAt().setExpirationTime('5m').sign(privateKey);
  const request = value => ({ headers: new Headers({ 'X-Bloomstep-Authorization': `Bearer ${value}` }) });
    const actor = await authenticate(request(await token()));
    assert.deepEqual(actor.roles, ['Bloomstep.AggregateWriter']);
    assert.equal(actor.userId.length, 64);
    for (const overrides of [{ roles: ['Owner'] }, { roles: ['Bloomstep.Admin'] }, { iss: 'https://other.invalid' }, { aud: 'wrong' }]) {
      // Explicit setters below avoid overriding reserved claims before defaults.
      const builder = new SignJWT({ roles: overrides.roles ?? ['Bloomstep.AggregateWriter'] })
        .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer(overrides.iss ?? config.issuer)
        .setAudience(overrides.aud ?? config.audience).setSubject('worker').setIssuedAt().setExpirationTime('5m');
      await assert.rejects(authenticate(request(await builder.sign(privateKey))), error => [401,403].includes(error.status));
    }
});

test('missing worker settings fail closed while real primary Admin can run manually', async () => {
  const request = { headers: new Headers({ 'X-Bloomstep-Authorization': 'Bearer token' }) };
  const admin = createAggregateAuthenticator({}, async () => ({ userId: 'a'.repeat(64), roles: ['Bloomstep.Admin'] }));
  assert.equal((await admin(request)).roles[0], 'Bloomstep.Admin');
  const customer = createAggregateAuthenticator({}, async () => ({ userId: 'a'.repeat(64), roles: ['User'] }));
  await assert.rejects(customer(request), error => error.status === 403);
  const unavailable = createAggregateAuthenticator({}, async () => { throw new ServiceError(401, 'Primary rejected'); });
  await assert.rejects(unavailable(request), error => error.status === 503);
});
