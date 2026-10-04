import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT } from 'jose';
import { createSpendAuthenticator } from '../src/spend-auth.mjs';

test('spend verifier pins dedicated resource issuer/audience and application-only explicit role', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const config = { issuer: 'https://resource.invalid/tenant/v2.0', audience: 'guard-api', jwksUri: 'https://resource.invalid/keys' };
  const auth = createSpendAuthenticator(config, async () => publicKey);
  const sign = (claims = {}, issuer = config.issuer, audience = config.audience) =>
    new SignJWT({ roles: ['Bloomstep.SpendGuard'], ...claims }).setProtectedHeader({ alg: 'RS256' })
      .setIssuer(issuer).setAudience(audience).setSubject('guard').setIssuedAt().setExpirationTime('5m').sign(privateKey);
  const request = token => ({ headers: new Headers({ 'X-Bloomstep-Authorization': `Bearer ${token}` }) });
  assert.deepEqual((await auth(request(await sign()))).roles, ['Bloomstep.SpendGuard']);
  for (const claims of [{ roles: ['Bloomstep.AggregateWriter'] }, { roles: ['Bloomstep.Admin'] },
    { roles: ['Owner'] }, { scp: 'Garden.ReadWrite' }, { roles: ['Bloomstep.SpendGuard', 'Bloomstep.AggregateWriter'] }]) {
    await assert.rejects(auth(request(await sign(claims))), error => error.status === 403);
  }
  await assert.rejects(auth(request(await sign({}, 'https://customer.invalid/v2.0'))), error => error.status === 401);
  await assert.rejects(auth(request(await sign({}, config.issuer, 'aggregate-api'))), error => error.status === 401);
  await assert.rejects(createSpendAuthenticator({})(request(await sign())), error => error.status === 503);
});
