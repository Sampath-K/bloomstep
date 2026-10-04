import { app } from '@azure/functions';
import { CosmosClient } from '@azure/cosmos';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { accountKey, isAdmin } from './contracts.mjs';
import { createHandlers, ServiceError } from './backend.mjs';

const issuer = process.env.OIDC_ISSUER;
const audience = process.env.OIDC_API_AUDIENCE;
const jwks = process.env.OIDC_JWKS_URI;
const cosmosConnection = process.env.COSMOS_CONNECTION_STRING;
const configuredContainer = cosmosConnection ? new CosmosClient(cosmosConnection).database('bloomstep').container('data') : null;
function container() {
  if (!configuredContainer) throw new ServiceError(503, 'Database is not provisioned.');
  return configuredContainer;
}
const keys = jwks?.startsWith('https://') ? createRemoteJWKSet(new URL(jwks)) : null;

/** @param {import('@azure/functions').HttpRequest} request */
async function authenticate(request) {
  if (!issuer || !audience || !keys || !configuredContainer) throw new ServiceError(503, 'Service is not provisioned.');
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) throw new ServiceError(401, 'Sign in required.');
  try {
    const { payload } = await jwtVerify(authorization.slice(7), keys, { issuer, audience, algorithms: ['RS256'], requiredClaims: ['sub', 'iss', 'exp', 'iat'] });
    if (!payload.sub || !payload.iss) throw new Error('Missing subject');
    const scopes = typeof payload.scp === 'string' ? payload.scp.split(' ') : [];
    if (!scopes.includes('Garden.ReadWrite') && !isAdmin(payload.roles)) throw new ServiceError(403, 'Required API scope is missing.');
    return { userId: accountKey(payload.iss, payload.sub), roles: payload.roles };
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    throw new ServiceError(401, 'Identity token could not be validated.');
  }
}

const handlers = createHandlers({ container, authenticate });
/**
 * @param {(request: import('@azure/functions').HttpRequest) => Promise<import('@azure/functions').HttpResponseInit>} handler
 */
function guarded(handler) {
  /** @param {import('@azure/functions').HttpRequest} request @param {import('@azure/functions').InvocationContext} context */
  return async (request, context) => {
    const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
    try { return { ...await handler(request), headers }; }
    catch (error) {
      if (error instanceof ServiceError) return { status: error.status, jsonBody: { error: error.message }, headers };
      context.error('Request failed; request body and tokens intentionally omitted.');
      return { status: 500, jsonBody: { error: 'The request failed. Your local garden is safe; retry later.' }, headers };
    }
  };
}

app.http('sync', { route: 'sync', methods: ['GET', 'POST'], authLevel: 'anonymous', handler: guarded(handlers.sync) });
app.http('deleteAccount', { route: 'account', methods: ['DELETE'], authLevel: 'anonymous', handler: guarded(handlers.deleteAccount) });
app.http('adminFeedback', { route: 'admin/feedback/{userId?}', methods: ['GET', 'POST'], authLevel: 'anonymous', handler: guarded(handlers.admin) });
app.http('adminMetrics', { route: 'admin/metrics', methods: ['GET'], authLevel: 'anonymous', handler: guarded(handlers.metrics) });
