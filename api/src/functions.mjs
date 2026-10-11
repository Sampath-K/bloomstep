import azureFunctions from '@azure/functions';
import { CosmosClient } from '@azure/cosmos';
import { createRemoteJWKSet } from 'jose';
import { createHandlers, ServiceError } from './backend.mjs';
import { createPrimaryAuthenticator } from './primary-auth.mjs';
import { createAggregateAuthenticator } from './aggregate-auth.mjs';
import { createSpendAuthenticator } from './spend-auth.mjs';
import { createWebsiteHandlers } from './website-funnel.mjs';
const { app } = azureFunctions;

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
const authenticate = createPrimaryAuthenticator({
  issuer,
  audience,
  keys,
  databaseConfigured: () => configuredContainer !== null,
});

const authenticateAggregate = createAggregateAuthenticator({
  issuer: process.env.AGGREGATE_OIDC_ISSUER,
  audience: process.env.AGGREGATE_OIDC_AUDIENCE,
  jwksUri: process.env.AGGREGATE_OIDC_JWKS_URI,
}, authenticate);
const authenticateSpend = createSpendAuthenticator({
  issuer: process.env.SPEND_GUARD_OIDC_ISSUER, audience: process.env.SPEND_GUARD_OIDC_AUDIENCE,
  jwksUri: process.env.SPEND_GUARD_OIDC_JWKS_URI,
});
const handlers = createHandlers({ container, authenticate, authenticateAggregate, authenticateSpend });
const website = createWebsiteHandlers({ container, authenticate, authenticateProof: authenticateAggregate, operationalEnabled: async () => {
  if (['true','1'].includes((process.env.BLOOMSTEP_API_DISABLED ?? '').toLowerCase()) ||
      ['true','1'].includes((process.env.BLOOMSTEP_WEBSITE_DISABLED ?? '').toLowerCase())) {
    throw new ServiceError(503, 'Website observations are paused.');
  }
  const gate = (await container().item('budget', '__preview_budget').read()).resource;
  if (gate?.operationalPause?.paused === true) throw new ServiceError(503, 'Website observations paused for spending review.');
} });
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
app.http('adminFeedback', { route: 'team/feedback/{userId?}', methods: ['GET', 'POST'], authLevel: 'anonymous', handler: guarded(handlers.admin) });
app.http('adminMetrics', { route: 'team/metrics', methods: ['GET'], authLevel: 'anonymous', handler: guarded(handlers.metrics) });
app.http('internalAggregates', { route: 'internal/aggregates', methods: ['POST'], authLevel: 'anonymous', handler: guarded(handlers.aggregates) });
app.http('createInvitation', { route: 'invitations', methods: ['POST'], authLevel: 'anonymous', handler: guarded(handlers.createInvitation) });
app.http('redeemInvitation', { route: 'invitations/redeem', methods: ['POST'], authLevel: 'anonymous', handler: guarded(handlers.redeemInvitation) });
app.http('invitationStatus', { route: 'invitations/status', methods: ['GET'], authLevel: 'anonymous', handler: guarded(handlers.invitationStatus) });
app.http('operationalPause', { route: 'internal/operational-pause', methods: ['POST'], authLevel: 'anonymous', handler: guarded(handlers.operationalPause) });
app.http('operationalResume', { route: 'team/operational-resume', methods: ['POST'], authLevel: 'anonymous', handler: guarded(handlers.operationalResume) });
app.http('operationalStatus', { route: 'team/operational-status', methods: ['GET'], authLevel: 'anonymous', handler: guarded(handlers.operationalStatus) });
app.http('websiteEvents', { route: 'web/events', methods: ['POST'], authLevel: 'anonymous', handler: guarded(website.ingest) });
app.http('websiteMetrics', { route: 'team/website', methods: ['GET'], authLevel: 'anonymous', handler: guarded(website.metrics) });
app.http('websiteSyntheticProof', { route: 'internal/website-proof', methods: ['GET'], authLevel: 'anonymous', handler: guarded(website.proof) });
