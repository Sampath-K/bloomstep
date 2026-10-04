import { createRemoteJWKSet, jwtVerify } from 'jose';
import { accountKey, isAdmin } from './contracts.mjs';
import { requestBearer } from './auth-transport.mjs';
import { ServiceError } from './backend.mjs';

/**
 * This verifier is wired only to the internal aggregate handler.
 * @param {{issuer?:string,audience?:string,jwksUri?:string}} config
 * @param {(request:import('@azure/functions').HttpRequest)=>Promise<{userId:string,roles:unknown}>} primary
 * @param {import('jose').JWTVerifyGetKey | undefined} trustedKeys Test-only injection.
 */
export function createAggregateAuthenticator(config, primary, trustedKeys = undefined) {
  const configured = !!config.issuer && !!config.audience
    && !!config.jwksUri?.startsWith('https://') && config.issuer.startsWith('https://');
  const keys = configured ? trustedKeys ?? createRemoteJWKSet(new URL(/** @type {string} */ (config.jwksUri))) : null;
  /** @param {import('@azure/functions').HttpRequest} request */
  return async request => {
    const token = requestBearer(request);
    try {
      const actor = await primary(request);
      if (isAdmin(actor.roles)) return actor;
      throw new ServiceError(403, 'Manual aggregation requires customer Admin role.');
    } catch (error) {
      if (!(error instanceof ServiceError) || ![401,503].includes(error.status)) throw error;
    }
    if (!keys) throw new ServiceError(503, 'Aggregate worker identity is not provisioned.');
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer: config.issuer, audience: config.audience, algorithms: ['RS256'],
        requiredClaims: ['sub','iss','exp','iat'],
      });
      if (!payload.sub || !payload.iss) throw new Error('Missing worker subject.');
      if (!Array.isArray(payload.roles) || !payload.roles.includes('Bloomstep.AggregateWriter')) throw new ServiceError(403, 'Explicit aggregate writer role required.');
      return { userId: accountKey(payload.iss, payload.sub), roles: payload.roles };
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError(401, 'Aggregate worker token could not be validated.');
    }
  };
}
