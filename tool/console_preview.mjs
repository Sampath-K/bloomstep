// Local-only fixture transport and bundle. Neither is imported by production site builds or Functions.
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { createAarrrFixture } from '../api/test/support/aarrr-fixture.mjs';
import { createExperimentHandlers, PARTITIONS } from '../api/src/experiments.mjs';
import { freezeInstance, CATALOG } from '../api/src/experiment-policy.mjs';

const require = createRequire(new URL('../site/package.json', import.meta.url));
const esbuild = await import(pathToFileURL(require.resolve('esbuild')));
const site = fileURLToPath(new URL('../site/', import.meta.url));
const fixtureDate = '2026-09-15T00:00:00Z';

async function buildSite() {
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['build.mjs'], { cwd: site, stdio: ['ignore', 'ignore', 'pipe'] });
    let error = '';
    child.stderr.on('data', chunk => { error += chunk; });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(Error(`Site build failed (${code}): ${error}`)));
  });
}

// Replaces only this disposable console bundle's auth import. The normal build continues using MSAL.
const previewAuth = `
export async function loadOperatorAuth(origin) {
  if (origin !== location.origin || location.hostname !== '127.0.0.1' || location.protocol !== 'http:')
    throw Error('Local preview requires loopback HTTP.');
  return { signIn: async () => {}, clear: async () => {} };
}
export async function operatorRequest(auth, origin, path, options = {}) {
  if (origin !== location.origin || location.hostname !== '127.0.0.1' ||
      !/^\\/api\\/team\\/(metrics|website|experiments)(\\?|$)/.test(path) ||
      (options.method ?? 'GET') !== 'GET') throw Error('Read-only local preview route required.');
  const session = await fetch('/__preview/session', { cache: 'no-store', signal: options.signal });
  if (!session.ok) throw Error('Local preview session unavailable.');
  const { token } = await session.json();
  const response = await fetch(path, { ...options, headers: { 'X-Bloomstep-Authorization': 'Bearer ' + token } });
  if (!response.ok) throw Error('Local preview HTTP ' + response.status);
  return response.json();
}
export function validatePublicConfig() { throw Error('Preview auth is not deployment configuration.'); }
`;

async function seedExperiments(container, authenticate, sign) {
  let now = new Date(fixtureDate);
  const handler = createExperimentHandlers({ container, environment: 'isolated', authenticate,
    authenticateWorker: async () => ({ roles: ['Bloomstep.AggregateWriter'] }),
    clock: () => now, stageSummary: async () => null });
  // Deliberately labeled aggregate fixtures, not observed exposures or efficacy evidence.
  const arm = (converted) => ({ exposed: 1000, converted: { primary_cta_click: converted, download_click: converted }, errors: 0 });
  const first = await freezeInstance(CATALOG[0], { startAt: '2026-08-01T00:00:00.000Z', environment: 'isolated' });
  const state = { id: 'state', userId: PARTITIONS.isolated, type: 'experiment_state', schemaVersion: 1,
    environment: 'isolated', killed: false, killReason: null, active: first,
    concluded: [], promotions: [], acceptance: null,
    audit: [{ at: first.startAt, action: 'launch', experimentId: first.experimentId }] };
  await container().items.create(state);
  await container().items.create({ id: `counts:${first.experimentId}`, userId: PARTITIONS.isolated,
    type: 'experiment_counts', arms: { control: arm(200), candidate: arm(350) }, looksDone: [] });
  const promoted = await handler.tick({});
  if (promoted.jsonBody.actions[0].decision.status !== 'promote') throw Error('Preview promotion seed failed.');
  const second = await freezeInstance(CATALOG[1], { startAt: '2026-09-01T00:00:00.000Z', environment: 'isolated' });
  const saved = (await container().item('state', PARTITIONS.isolated).read()).resource;
  saved.active = second;
  saved.audit.push({ at: second.startAt, action: 'launch', experimentId: second.experimentId });
  await container().item('state', PARTITIONS.isolated).replace(saved, { accessCondition: { condition: saved._etag } });
  await container().items.create({ id: `counts:${second.experimentId}`, userId: PARTITIONS.isolated,
    type: 'experiment_counts', arms: { control: arm(350), candidate: arm(100) }, looksDone: [] });
  now = new Date(Date.parse(second.harmLookAt[0]) + 1000);
  const rolledBack = await handler.tick({});
  if (rolledBack.jsonBody.actions[0].decision.status !== 'rollback_harm') throw Error('Preview rollback seed failed.');
  const third = await freezeInstance(CATALOG[2], { startAt: now.toISOString(), environment: 'isolated' });
  const finalState = (await container().item('state', PARTITIONS.isolated).read()).resource;
  finalState.active = third;
  finalState.audit.push({ at: third.startAt, action: 'launch', experimentId: third.experimentId });
  await container().item('state', PARTITIONS.isolated).replace(finalState, { accessCondition: { condition: finalState._etag } });
  await handler.kill({ headers: new Headers({ 'Content-Type': 'application/json',
    'X-Bloomstep-Authorization': `Bearer ${await sign('synthetic-admin')}` }),
    text: async () => JSON.stringify({ killed: true, reason: 'Local synthetic preview kill-switch drill' }) });
  return handler;
}

export async function startConsolePreview({ port = 8787 } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw Error('Port must be an integer from 0 to 65535.');
  await buildSite();
  const bundle = await esbuild.build({ entryPoints: [fileURLToPath(new URL('../site/console.mjs', import.meta.url))],
    bundle: true, format: 'esm', target: 'es2022', write: false, logLevel: 'silent',
    plugins: [{ name: 'disposable-loopback-auth', setup(build) {
      build.onResolve({ filter: /^\.\/operator-auth\.mjs$/ }, () => ({ path: 'preview-auth', namespace: 'preview-only' }));
      build.onLoad({ filter: /.*/, namespace: 'preview-only' }, () => ({ contents: previewAuth, loader: 'js' }));
    } }] });
  let fixture;
  try {
    fixture = await createAarrrFixture({ port, configure: async ({ container, authenticate, sign }) => {
      const experiments = await seedExperiments(container, authenticate, sign);
      const html = (await readFile(new URL('../site/console.html', import.meta.url), 'utf8'))
        .replace('<body>', '<body><aside role="status" style="padding:16px;background:#ffe9a8;color:#222;font-weight:bold">Local synthetic preview — not customers. Fixed fixture window: September 2026. No real traffic or efficacy evidence.</aside>')
        .replace('value="7"', 'value="14"')
        .replace('This deployed HTTPS API origin', 'Read-only loopback preview API origin')
        .replace('Sign in to Bloomstep operator console', 'Local preview connected (no sign-in needed)')
        .replace('Sign out and clear private data', 'Clear loaded preview panels');
      return new Map([
        ['GET /', async () => ({ contentType: 'text/html', body: html })],
        ['GET /console.html', async () => ({ contentType: 'text/html', body: html })],
        ['GET /assets/console.js', async () => ({ contentType: 'text/javascript', body: bundle.outputFiles[0].text })],
        ['GET /__preview/session', async () => ({ jsonBody: { token: await sign('synthetic-admin') } })],
        ['GET /api/team/experiments', request => experiments.report(request)],
      ]);
    } });
    await fixture.seed({ receipt: true });
    const touch = { source: 'search', referrerDomain: 'google.com', campaignSource: 'newsletter',
      campaignMedium: 'email', campaignName: 'tiny_habits' };
    await fixture.seedWebsite({ firstTouch: touch, lastTouch: touch });
    await fixture.restartStore();
    fixture.restrictToReports();
    return { url: fixture.url + '/console.html', address: fixture.address,
      databasePath: fixture.databasePath, close: () => fixture.close() };
  } catch (error) {
    if (fixture) await fixture.close();
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--port' || !/^\d+$/.test(args[1]))) {
    throw Error('Usage: node tool/console_preview.mjs [--port 8787]');
  }
  const preview = await startConsolePreview({ port: args.length ? Number(args[1]) : 8787 });
  console.log(`Local synthetic preview — not customers\n${preview.url}\nPress Ctrl+C to stop and delete the disposable store.`);
  let closing = false;
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
    if (closing) return;
    closing = true;
    await preview.close();
  });
}
