import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

// Public routes answer without storage: production experiments are OFF (200 disabled config), bodies need JSON.
const publicStatus = /** @type {Record<string, number>} */ ({ 'web/events': 400, 'web/experiments': 200,
  'web/experiments/exposure': 400, 'web/experiments/outcome': 400, 'web/experiments/forget': 400 });

test('actual ESM entrypoint registers only host-valid routes and guarded handlers', () => {
  const script = `
    import azureFunctions from '@azure/functions';
    const { app, HttpRequest } = azureFunctions;
    for (const key of ['OIDC_ISSUER','OIDC_API_AUDIENCE','OIDC_JWKS_URI','COSMOS_CONNECTION_STRING']) delete process.env[key];
    const registrations = [];
    app.http = (name, options) => registrations.push({ name, ...options });
    await import('./src/functions.mjs');
    const results = [];
    for (const entry of registrations) {
      const response = await entry.handler(new HttpRequest({ url: 'https://example.invalid/api/' + entry.route, method: entry.methods[0] }), { error() {} });
      results.push({ name:entry.name,route:entry.route,methods:entry.methods,authLevel:entry.authLevel,status:response.status,cache:response.headers['Cache-Control'] });
    }
    console.log(JSON.stringify(results));
  `;
  const results = JSON.parse(execFileSync(process.execPath, ['--input-type=module', '-e', script], {
    cwd: new URL('../', import.meta.url), encoding: 'utf8',
  }));
  assert.equal(results.length, 21);
  for (const entry of results) {
    // Mirrors ScriptHost.ValidateHttpFunction: prefix check precedes host api prefix.
    assert.equal(/^(admin|runtime)/i.test(entry.route.replace(/^\/+|\/+$/g, '')), false, entry.route);
    assert.equal(entry.status, publicStatus[entry.route] ?? (entry.route.startsWith('internal/') ? 401 : 503), entry.route);
    assert.equal(entry.cache, 'no-store');
    assert.equal(entry.authLevel, 'anonymous');
  }
  assert.deepEqual(results.map(entry => entry.route), [
    'sync', 'account', 'team/feedback/{userId?}', 'team/metrics', 'internal/aggregates',
    'invitations', 'invitations/redeem', 'invitations/status',
    'internal/operational-pause',
    'team/operational-resume',
    'web/events', 'team/website', 'internal/website-proof',
    'web/experiments', 'web/experiments/exposure', 'web/experiments/outcome', 'web/experiments/forget',
    'internal/experiments/tick', 'team/experiments', 'team/experiments/kill', 'team/experiments/acceptance',
  ]);
});

test('configured entrypoint rejects platform-only auth on every served handler before network access', () => {
  const script = `
    import azureFunctions from '@azure/functions';
    const { app, HttpRequest } = azureFunctions;
    process.env.OIDC_ISSUER = 'https://broker.example.invalid/tenant/v2.0';
    process.env.OIDC_API_AUDIENCE = 'test-api';
    process.env.OIDC_JWKS_URI = 'https://broker.example.invalid/keys';
    process.env.COSMOS_CONNECTION_STRING = 'AccountEndpoint=https://database.example.invalid/;AccountKey=' + Buffer.alloc(32).toString('base64') + ';';
    const registrations = [];
    app.http = (name, options) => registrations.push({ name, ...options });
    await import('./src/functions.mjs');
    const results = [];
    for (const entry of registrations) {
      for (const headers of [{}, { Authorization:'Bearer platform-token', 'x-ms-client-principal':'platform-principal' }]) {
        const response = await entry.handler(new HttpRequest({ url:'https://example.invalid/api/' + entry.route, method:entry.methods[0], headers }), { error() {} });
        results.push({route:entry.route,status:response.status,error:response.jsonBody?.error});
      }
    }
    console.log(JSON.stringify(results));
  `;
  const results = JSON.parse(execFileSync(process.execPath, ['--input-type=module', '-e', script], {
    cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 30000,
  }));
  assert.equal(results.length, 42);
  for (const entry of results) {
    assert.equal(entry.status, publicStatus[entry.route] ?? 401, entry.route);
    assert.equal(entry.error, entry.route === 'web/experiments' ? undefined : publicStatus[entry.route] ? 'JSON required.' : 'Sign in required.', entry.route);
  }
});
