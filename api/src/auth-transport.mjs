import { ServiceError } from './backend.mjs';

/** @param {{headers: {get: (name: string) => string | null}}} request */
export function requestBearer(request) {
  // Managed SWA owns Authorization; platform identity is not our broker token.
  const authorization = request.headers.get('x-bloomstep-authorization');
  if (!authorization || !/^Bearer [^\s,]+$/.test(authorization)) throw new ServiceError(401, 'Sign in required.');
  return authorization.slice(7);
}
