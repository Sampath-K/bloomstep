import { createServer } from 'node:http';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SignJWT, jwtVerify } from 'jose';
import { createHandlers, ServiceError } from '../../src/backend.mjs';
import { accountKey } from '../../src/contracts.mjs';
import { FileBackedCosmosContainer } from './file_backed_cosmos.mjs';
import { createWebsiteHandlers } from '../../src/website-funnel.mjs';

const issuer = 'https://aarrr-fixture.invalid';
const audience = 'isolated-aarrr-fixture';
const observedAt = '2026-09-15T00:00:00Z';

// This disposable loopback harness is never registered in production Functions.
export async function createAarrrFixture({ port = 0, configure = () => new Map() } = {}) {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  const databasePath = join(root, 'aarrr.json'), key = randomBytes(32);
  let container = await FileBackedCosmosContainer.openFresh(databasePath);
  const sign = sub => new SignJWT({ scp: 'Garden.ReadWrite' }).setProtectedHeader({ alg: 'HS256' })
    .setIssuer(issuer).setAudience(audience).setSubject(sub).setIssuedAt().setExpirationTime('15m').sign(key);
  const authenticate = async request => {
    const match = /^Bearer (.+)$/.exec(request.headers.get('X-Bloomstep-Authorization') ?? '');
    if (!match) throw new ServiceError(401, 'Isolated fixture sign-in required.');
    let payload;
    try { ({ payload } = await jwtVerify(match[1], key, { issuer, audience, algorithms: ['HS256'] })); }
    catch { throw new ServiceError(401, 'Invalid isolated fixture signature.'); }
    if (typeof payload.sub !== 'string' || !/^synthetic-(?:admin|account-\d{3})$/.test(payload.sub) ||
        payload.scp !== 'Garden.ReadWrite') throw new ServiceError(401, 'Synthetic fixture subjects only.');
    return { userId: accountKey(issuer, payload.sub), roles: payload.sub === 'synthetic-admin' ? ['Bloomstep.Admin'] : [],
      scopes: ['Garden.ReadWrite'] };
  };
  const handlers = createHandlers({ container: () => container, authenticate,
    clock: () => new Date(observedAt), environment: () => ({ BLOOMSTEP_INVITATIONS_DISABLED: 'true' }) });
  let webNow = new Date(observedAt);
  const website = createWebsiteHandlers({ container: () => container, authenticate, clock: () => webNow });
  let extensions;
  try { extensions = await configure({ container: () => container, authenticate, sign }); }
  catch (error) {
    await container.close();
    await rm(root, { recursive: true, force: true });
    throw error;
  }
  const staticFiles = new Map([
    ['/console.html', ['../../../site/console.html', 'text/html']],
    ['/console.css', ['../../../site/console.css', 'text/css']],
    ['/assets/theme.css', ['../../../site/assets/theme.css', 'text/css']],
    ['/assets/console.js', ['../../../site/assets/console.js', 'text/javascript']],
    ['/aarrr-panels.mjs', ['../../../site/aarrr-panels.mjs', 'text/javascript']],
    ['/website-panels.mjs', ['../../../site/website-panels.mjs', 'text/javascript']],
    ['/acquisition-panels.mjs', ['../../../site/acquisition-panels.mjs', 'text/javascript']],
    ['/api/src/website-attribution.mjs', ['../../src/website-attribution.mjs', 'text/javascript']],
    ['/operator-config.json', ['../../../site/operator-config.json', 'application/json']],
    ['/assets/bloomstep-icon.png', ['../../../site/assets/bloomstep-icon.png', 'image/png']],
  ]);
  let unavailable = false, readOnly = false;
  const server = createServer(async (incoming, response) => {
    const path = new URL(incoming.url, 'http://127.0.0.1').pathname;
    const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
    try {
      if (incoming.headers.host !== `127.0.0.1:${server.address().port}` ||
          (incoming.headers.origin && incoming.headers.origin !== url)) {
        throw new ServiceError(403, 'Loopback fixture origin required.');
      }
      if (readOnly && path.startsWith('/api/') &&
          (incoming.method !== 'GET' || !['/api/team/metrics', '/api/team/website', '/api/team/experiments'].includes(path))) {
        throw new ServiceError(403, 'Local preview permits report reads only.');
      }
      const extension = extensions.get(`${incoming.method} ${path}`);
      if (extension) {
        const result = await extension({ headers: new Headers(incoming.headers),
          method: incoming.method, url: `${url}${incoming.url}`,
          query: new URLSearchParams(new URL(incoming.url, url).search) });
        response.writeHead(result.status ?? 200, { ...headers, 'Content-Type': result.contentType ?? 'application/json' });
        response.end(result.body ?? JSON.stringify(result.jsonBody));
        return;
      }
      const asset = staticFiles.get(path);
      if (asset && incoming.method === 'GET') {
        response.writeHead(200, { ...headers, 'Content-Type': asset[1] });
        response.end(await readFile(new URL(asset[0], import.meta.url))); return;
      }
      if (path === '/healthz') { response.writeHead(200, headers); response.end('ready'); return; }
      if (unavailable && path === '/api/team/metrics') throw new ServiceError(503, 'Isolated pipeline unavailable.');
      const handler = path === '/api/sync' && ['GET', 'POST'].includes(incoming.method) ? handlers.sync :
        path === '/api/team/metrics' && incoming.method === 'GET' ? handlers.metrics :
        path === '/api/web/events' && incoming.method === 'POST' ? website.ingest :
        path === '/api/team/website' && incoming.method === 'GET' ? website.metrics :
        path === '/api/account' && incoming.method === 'DELETE' ? handlers.deleteAccount : null;
      if (!handler) { response.writeHead(404, headers); response.end(); return; }
      let body = '';
      for await (const chunk of incoming) {
        body += chunk;
        if (Buffer.byteLength(body) > 512 * 1024) throw new ServiceError(413, 'Fixture body cap exceeded.');
      }
      const result = await handler({ method: incoming.method, headers: new Headers(incoming.headers),
        url: `${url}${incoming.url}`,
        query: new URLSearchParams(new URL(incoming.url, 'http://127.0.0.1').search),
        params: {}, text: async () => body });
      response.writeHead(result.status ?? 200, { ...headers, 'Content-Type': 'application/json' });
      response.end(result.jsonBody === undefined ? '' : JSON.stringify(result.jsonBody));
    } catch (error) {
      response.writeHead(error instanceof ServiceError ? error.status : 500, { ...headers, 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: error instanceof ServiceError ? error.message : 'Isolated fixture failed.' }));
    }
  });
  try {
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  } catch (error) {
    await container.close();
    await rm(root, { recursive: true, force: true });
    throw error;
  }
  const url = `http://127.0.0.1:${server.address().port}`;
  const adminToken = await sign('synthetic-admin');
  const subjects = [];
  const request = async (path, token = adminToken, method = 'GET', body) => fetch(url + path, {
    method, headers: { 'X-Bloomstep-Authorization': `Bearer ${token}`, 'Content-Type': 'application/json',
      ...(method === 'DELETE' ? { 'X-Confirm-Delete': 'delete-my-garden' } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return {
    url, databasePath, request, adminToken, subjects, address: server.address(),
    failPipeline(value) { unavailable = value; },
    restrictToReports() { readOnly = true; },
    async seedWebsite(attribution) {
      let index = 0;
      for (const [stageIndex, stage] of ['landing_view', 'primary_cta_click', 'download_click'].entries()) {
        for (let count = 0; count < 50; count++) {
          webNow = new Date(Date.parse(`2026-09-${String(12 + stageIndex).padStart(2, '0')}T10:00:00Z`) + count * 60000);
          const result = await request('/api/web/events', adminToken, 'POST', {
            channel: 'web', event: stage, source: 'search', architecture: 'unknown',
            eventId: randomUUID(), synthetic: false, ...(attribution ? { attribution, observedAt: webNow.toISOString() } : {}),
          });
          if (result.status !== 202) throw Error(`Isolated web fixture failed (${result.status}): ${await result.text()}`);
          index++;
        }
      }
      webNow = new Date(observedAt);
      return index;
    },
    async seed() {
      for (let i = 0; i < 150; i++) {
        const subject = `synthetic-account-${String(i).padStart(3, '0')}`;
        const token = await sign(subject), habitId = randomUUID();
        const event = (name, ts, properties = {}) => ({ id: randomUUID(), name, ts, properties });
        const payload = { habits: [], checkins: [], reflections: [], voice: [], events: [
          event('signin_succeeded', '2026-09-01T10:00:00Z'),
        ] };
        if (i < 100) {
          payload.habits.push({ id: habitId, aspiration: 'ISOLATED FIXTURE', anchor: 'FIXTURE',
            behavior: 'FIXTURE', celebration: 'FIXTURE', species: 'Fern', stage: 0, status: 'active', updated: '2026-09-01T11:00:00Z' });
          payload.events.push(event('recipe_created', '2026-09-01T11:00:00Z', { habitId, localDay: '2026-09-01' }));
        }
        if (i < 50) {
          for (const day of ['2026-09-01', '2026-09-02', '2026-09-08']) {
            payload.checkins.push({ id: randomUUID(), habitId, day, result: 'did', reason: null, ts: `${day}T12:00:00Z` });
            payload.events.push(event(day === '2026-09-01' ? 'first_checkin' : 'checkin', `${day}T12:00:00Z`,
              { habitId, localDay: day, result: 'did' }));
          }
        }
        const result = await request('/api/sync', token, 'POST', payload);
        if (result.status !== 200) throw Error(`Fixture sync failed (${result.status}): ${await result.text()}`);
        subjects.push({ subject, token, payload });
      }
    },
    async restartStore() {
      await container.close();
      container = await FileBackedCosmosContainer.openExisting(databasePath);
    },
    async close() {
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      await container.close(); await rm(root, { recursive: true, force: true });
    },
  };
}
