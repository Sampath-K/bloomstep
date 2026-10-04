import { createRemoteJWKSet, jwtVerify } from 'jose';
import { requestBearer } from './auth-transport.mjs';
import { accountKey } from './contracts.mjs';
import { ServiceError } from './backend.mjs';

/** Only wired to operational-pause, never a global alternate issuer.
 * @param {{issuer?:string,audience?:string,jwksUri?:string}} config
 * @param {import('jose').JWTVerifyGetKey|undefined} trustedKeys */
export function createSpendAuthenticator(config, trustedKeys = undefined) {
  const keys = config.issuer?.startsWith('https://') && config.audience && config.jwksUri?.startsWith('https://')
    ? trustedKeys ?? createRemoteJWKSet(new URL(config.jwksUri)) : null;
  return async (/** @type {import('@azure/functions').HttpRequest} */ request) => {
    const token = requestBearer(request);
    if (!keys) throw new ServiceError(503, 'Spend guard identity is not provisioned.');
    try {
      const { payload } = await jwtVerify(token, keys, { issuer: config.issuer, audience: config.audience,
        algorithms: ['RS256'], requiredClaims: ['iss', 'sub', 'iat', 'exp'] });
      if (payload.scp !== undefined || !Array.isArray(payload.roles) || payload.roles.length !== 1 || payload.roles[0] !== 'Bloomstep.SpendGuard') {
        throw new ServiceError(403, 'Explicit application SpendGuard role required.');
      }
      return { userId: accountKey(String(payload.iss), String(payload.sub)), roles: payload.roles };
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError(401, 'Spend guard token could not be validated.');
    }
  };
}
