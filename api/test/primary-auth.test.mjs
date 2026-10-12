import test from 'node:test';
import assert from 'node:assert/strict';
import { createSecretKey } from 'node:crypto';
import { generateKeyPair, SignJWT } from 'jose';
import { ServiceError } from '../src/backend.mjs';
import { createPrimaryAuthenticator } from '../src/primary-auth.mjs';

const issuer = 'https://identity.example.test/tenant/v2.0';
const audience = 'bloomstep-api';

test('production garden authentication accepts RS256 and rejects test HS256 keys and unprovisioned paths', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const sign = async ({
    iss = issuer,
    aud = audience,
    exp = '2m',
    claims = { scp: 'Garden.ReadWrite' },
  } = {}) => new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(iss)
    .setSubject('opaque-subject')
    .setAudience(aud)
    .setIssuedAt()
    .setExpirationTime(exp)
    .sign(privateKey);
  const valid = await sign();
  const secret = createSecretKey(Buffer.alloc(32, 7));
  const synthetic = await new SignJWT({ scp: 'Garden.ReadWrite' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(issuer)
    .setSubject('synthetic-a')
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime('2m')
    .sign(secret);
  const syntheticAdmin = await new SignJWT({
    scp: 'Garden.ReadWrite',
    roles: ['Bloomstep.Admin'],
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(issuer)
    .setSubject('synthetic-a')
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime('2m')
    .sign(secret);
  const unsignedPayload = Buffer.from(JSON.stringify({
    iss: issuer,
    sub: 'synthetic-a',
    aud: audience,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 120,
    scp: 'Garden.ReadWrite',
  })).toString('base64url');
  const unsigned = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${unsignedPayload}.`;
  const authenticate = createPrimaryAuthenticator({
    issuer,
    audience,
    keys: publicKey,
    databaseConfigured: () => true,
  });
  const request = token => ({
    headers: new Headers({
      'x-bloomstep-authorization': `Bearer ${token}`,
    }),
  });
  const actor = await authenticate(request(valid));
  assert.equal(actor.userId.length, 64);
  assert.deepEqual(actor.scopes, ['Garden.ReadWrite']);
  for (const rejected of [
    synthetic,
    syntheticAdmin,
    unsigned,
    await sign({ aud: 'other-api' }),
    await sign({ iss: 'https://wrong-issuer.example.test' }),
    await sign({ exp: '0s' }),
  ]) {
    await assert.rejects(authenticate(request(rejected)), error =>
      error instanceof ServiceError && error.status === 401,
    );
  }
  const noScope = createPrimaryAuthenticator({
    issuer,
    audience,
    keys: publicKey,
    databaseConfigured: () => true,
  });
  await assert.rejects(
    noScope(request(await sign({ claims: { scp: 'User.Read' } }))),
    error => error instanceof ServiceError && error.status === 403,
  );

  const unavailable = createPrimaryAuthenticator({
    issuer,
    audience,
    keys: publicKey,
    databaseConfigured: () => false,
  });
  await assert.rejects(unavailable(request(valid)), error =>
    error instanceof ServiceError && error.status === 503,
  );
});

test('release entrypoint does not import the test auth harness or contain a test-key branch', async () => {
  const { readFile } = await import('node:fs/promises');
  const root = new URL('../', import.meta.url);
  const [main, workflow, productionAuth] = await Promise.all([
    readFile(new URL('../lib/main.dart', root), 'utf8'),
    readFile(new URL('../.github/workflows/ci.yml', root), 'utf8'),
    readFile(new URL('../src/primary-auth.mjs', import.meta.url), 'utf8'),
  ]);
  const functions = await readFile(
    new URL('../src/functions.mjs', import.meta.url),
    'utf8',
  );
  const functionIgnore = await readFile(
    new URL('.funcignore', root),
    'utf8',
  );
  assert.doesNotMatch(main, /test_only_app|test_auth_contract|local_test_api/);
  assert.doesNotMatch(productionAuth, /BLOOMSTEP_TEST|HS256|testIssuer|testAudience/);
  assert.match(functionIgnore, /^test\/$/m);
  assert.match(productionAuth, /algorithms:\s*\[\s*'RS256'\s*\]/);
  assert.match(functions, /createRemoteJWKSet\(new URL\(jwks\)\)/);
  assert.match(functions, /jwks\?\.startsWith\('https:\/\/'\)/);
  assert.match(workflow, /BLOOMSTEP_TEST_BUILD=true/);
  const releaseStep = workflow.indexOf('name: Build real provider-backed release');
  assert.notEqual(releaseStep, -1, 'Production build step must exist.');
  const releaseBuild = workflow.slice(releaseStep);
  assert.doesNotMatch(releaseBuild, /BLOOMSTEP_TEST_BUILD|BLOOMSTEP_TEST_AUTH_SECRET/);
  assert.match(releaseBuild, /build\/windows\/\$\{\{ matrix\.arch \}\}\/runner\/Release/);
  assert.doesNotMatch(releaseBuild, /integration_test|testkit|BLOOMSTEP_TEST/);
});
