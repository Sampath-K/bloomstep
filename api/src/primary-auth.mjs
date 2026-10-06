import { jwtVerify } from 'jose';
import { accountKey, isAdmin } from './contracts.mjs';
import { ServiceError } from './backend.mjs';
import { requestBearer } from './auth-transport.mjs';

/**
 * @param {{
 * issuer: string | undefined,
 * audience: string | undefined,
 * keys: import('jose').KeyInput | import('jose').JWTVerifyGetKey | null,
 * databaseConfigured: () => boolean
 * }} configuration
 */
export function createPrimaryAuthenticator({
  issuer,
  audience,
  keys,
  databaseConfigured,
}) {
  /** @param {{headers: {get: (name: string) => string | null}}} request */
  return async request => {
    if (!issuer || !audience || !keys || !databaseConfigured()) {
      throw new ServiceError(503, 'Service is not provisioned.');
    }
    const token = requestBearer(request);
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer,
        audience,
        algorithms: ['RS256'],
        requiredClaims: ['sub', 'iss', 'exp', 'iat'],
      });
      if (!payload.sub || !payload.iss) throw new Error('Missing subject');
      const scopes = typeof payload.scp === 'string' ? payload.scp.split(' ') : [];
      if (!scopes.includes('Garden.ReadWrite') && !isAdmin(payload.roles)) {
        throw new ServiceError(403, 'Required API scope is missing.');
      }
      return {
        userId: accountKey(payload.iss, payload.sub),
        roles: payload.roles,
        scopes,
      };
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError(401, 'Identity token could not be validated.');
    }
  };
}
