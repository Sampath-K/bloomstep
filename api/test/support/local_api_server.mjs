import { createServer } from 'node:http';
import { normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { jwtVerify } from 'jose';
import { accountKey } from '../../src/contracts.mjs';
import { createHandlers, ServiceError } from '../../src/backend.mjs';
import { FileBackedCosmosContainer, isWithinDisposableTestDirectory } from './file_backed_cosmos.mjs';

const testIssuer = 'https://bloomstep.test';
const testAudience = 'bloomstep-test-api';
const maxBodyBytes = 512 * 1024;

function validateKey(key) {
  if (!Buffer.isBuffer(key) || key.length < 32) {
    throw new Error('test authentication unavailable');
  }
}

export async function createLocalTestServer({
  databasePath,
  key,
  port = 0,
  reuseDatabase = false,
}) {
  validateKey(key);
  const path = normalize(databasePath);
  if (!isWithinDisposableTestDirectory(path)) {
    throw new Error('database must be inside a disposable test directory');
  }
  const container = reuseDatabase
    ? await FileBackedCosmosContainer.openExisting(path)
    : await FileBackedCosmosContainer.openFresh(path);
  const environment = { BLOOMSTEP_INVITATIONS_DISABLED: 'true' };
  const handlers = createHandlers({
    container: () => container,
    authenticate: async request => {
      const authorization = request.headers.get('x-bloomstep-authorization') ?? '';
      const match = /^Bearer ([A-Za-z0-9_.-]+)$/.exec(authorization);
      if (!match) throw new ServiceError(401, 'Sign in required.');
      try {
        const { payload, protectedHeader } = await jwtVerify(match[1], key, {
          issuer: testIssuer,
          audience: testAudience,
          algorithms: ['HS256'],
          requiredClaims: ['sub', 'iss', 'iat', 'exp', 'scp'],
        });
        const claims = Object.keys(payload);
        if (protectedHeader.alg !== 'HS256' ||
            claims.some(claim => !['iss', 'sub', 'aud', 'iat', 'exp', 'scp'].includes(claim)) ||
            typeof payload.sub !== 'string' ||
            !/^synthetic-[a-z0-9][a-z0-9_-]{0,23}$/.test(payload.sub) ||
            payload.scp !== 'Garden.ReadWrite') {
          throw new Error('invalid synthetic claims');
        }
        return {
          userId: accountKey(testIssuer, payload.sub),
          roles: [],
          scopes: ['Garden.ReadWrite'],
        };
      } catch {
        throw new ServiceError(401, 'Identity token could not be validated.');
      }
    },
    environment: () => environment,
  });

  const server = createServer(async (incoming, response) => {
    const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
    if (incoming.url === '/healthz' && incoming.method === 'GET') {
      response.writeHead(200, { ...headers, 'Content-Type': 'application/json' });
      response.end('{"ready":true}');
      return;
    }
    if (incoming.url !== '/api/sync' ||
        !['GET', 'POST'].includes(incoming.method ?? '')) {
      response.writeHead(incoming.url === '/api/sync' ? 405 : 404, headers);
      response.end();
      return;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of incoming) {
      size += chunk.length;
      if (size > maxBodyBytes) {
        response.writeHead(413, headers);
        response.end('{"error":"Request is too large."}');
        return;
      }
      chunks.push(chunk);
    }
    const rawBody = Buffer.concat(chunks).toString('utf8');
    const request = {
      method: incoming.method,
      headers: new Headers(incoming.headers),
      query: new URLSearchParams(new URL(incoming.url ?? '/', 'http://127.0.0.1').search),
      params: {},
      text: async () => rawBody,
    };
    try {
      const result = await handlers.sync(request);
      const status = result.status ?? 200;
      response.writeHead(status, {
        ...headers,
        ...(result.jsonBody === undefined ? {} : { 'Content-Type': 'application/json' }),
      });
      response.end(result.jsonBody === undefined ? '' : JSON.stringify(result.jsonBody));
    } catch (error) {
      const status = error instanceof ServiceError ? error.status : 500;
      const body = error instanceof ServiceError
        ? { error: error.message }
        : { error: 'The request failed. Your local garden is safe; retry later.' };
      response.writeHead(status, { ...headers, 'Content-Type': 'application/json' });
      response.end(JSON.stringify(body));
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Local test API did not bind a TCP port.');
  return {
    url: `http://127.0.0.1:${address.port}`,
    databasePath: path,
    async close() {
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      await container.close();
    },
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const keyText = process.env.BLOOMSTEP_TEST_AUTH_SECRET;
  const databasePath = process.env.BLOOMSTEP_TEST_DATABASE;
  const portText = process.env.BLOOMSTEP_TEST_PORT ?? '0';
  if (!/^[a-f0-9]{64}$/i.test(keyText ?? '') ||
      !databasePath ||
      !/^\d{1,5}$/.test(portText)) {
    process.stderr.write('TEST_API_START_FAILED\n');
    process.exit(2);
  }
  try {
    const instance = await createLocalTestServer({
      databasePath,
      key: Buffer.from(keyText, 'hex'),
      port: Number(portText),
      reuseDatabase: process.env.BLOOMSTEP_TEST_REUSE_DATABASE === 'true',
    });
    process.stdout.write(`TEST_API_READY ${new URL(instance.url).port}\n`);
    let stopping = false;
    const stop = async () => {
      if (stopping) return;
      stopping = true;
      await instance.close();
      process.exit(0);
    };
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', command => {
      if (command.split(/\r?\n/).includes('shutdown')) void stop();
    });
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
  } catch {
    process.stderr.write('TEST_API_START_FAILED\n');
    process.exit(2);
  }
}
