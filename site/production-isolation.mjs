import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { isolationIdentity, isolationSummary } from './isolation-check.mjs';

const origin = 'https://brave-plant-02c10e800.5.azurestaticapps.net';
const tenant = '80e48373-4f7c-4871-9223-1c83a780bba9';
const authority = `https://${tenant}.ciamlogin.com/${tenant}`;
const scope = 'api://97a870fe-374f-47ab-9b03-f0a6c5ed76a4/Garden.ReadWrite';
const redirectUri = 'http://localhost:8400/automation-callback';
const empty = () => ({ habits: [], checkins: [], reflections: [], voice: [], events: [] });
const requireCheck = condition => { if (!condition) throw Error('Acceptance check failed.'); };

export function redactSignInText(text, account) {
  return String(text).replaceAll(account.password, '[credential]').replaceAll(account.email, '[test account]')
    .replace(/[^\s@]+@[^\s@]+/g, '[account]')
    .replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]')
    .replace(/[a-f0-9]{8}-[a-f0-9-]{27,}/gi, '[identifier]').slice(0, 300);
}

export function automationAccounts(environment) {
  let issuerDomain;
  return ['A', 'B', 'ADMIN'].map(label => {
    const email = environment[`BUDLARK_TEST_${label}_EMAIL`];
    const password = environment[`BUDLARK_TEST_${label}_PASSWORD`];
    const domain = typeof email === 'string' ? email.split('@')[1] : undefined;
    if (!domain || !/^[a-z0-9-]+\.onmicrosoft\.com$/.test(domain) ||
        email !== `budlark-test-${label.toLowerCase()}@${domain}` ||
        issuerDomain && issuerDomain !== domain ||
        typeof password !== 'string' || password.length < 24) throw Error('Dedicated automation credentials are missing or invalid.');
    issuerDomain = domain;
    return { label, email, password };
  });
}

export async function runIsolationAcceptance(call) {
  const evidence = { schemaVersion: 1, passed: false, accounts: [], adminMetrics: null, cleanup: 'pending', phase: 'identity' };
  const habitId = randomUUID(), voiceId = randomUUID();
  const identities = new Map();
  const now = () => new Date().toISOString();
  try {
    for (const label of ['A', 'B']) {
      const result = await call(label, '/api/account/isolation');
      requireCheck(result.status === 200);
      identities.set(label, isolationIdentity(result.data));
    }
    requireCheck(identities.get('A') !== identities.get('B'));
    evidence.phase = 'own-write';
    for (const label of ['A', 'B']) {
      const result = await call(label, '/api/sync', 'POST', {
        ...empty(),
        habits: [{ id: habitId, aspiration: 'automation', anchor: `automation-${label}`,
          behavior: 'pause once', celebration: 'done', species: 'Fern', stage: 0, status: 'active', updated: now() }],
        voice: [{ id: voiceId, kind: 'Idea', body: `Automation isolation fixture ${label}`, rating: null, ts: now() }],
      });
      requireCheck(result.status === 200);
    }
    evidence.phase = 'cross-account-checks';
    for (const label of ['A', 'B']) {
      const peerUserId = identities.get(label === 'A' ? 'B' : 'A');
      const deniedRead = await call(label, `/api/sync?userId=${peerUserId}`);
      const deniedWrite = await call(label, '/api/sync', 'POST', { ...empty(), userId: peerUserId });
      requireCheck(deniedRead.status === 400 && deniedWrite.status === 400);
      const own = await call(label, '/api/sync');
      requireCheck(own.status === 200 &&
        own.data.habits?.find(row => row.id === habitId)?.anchor === `automation-${label}` &&
        own.data.voice?.find(row => row.id === voiceId)?.body === `Automation isolation fixture ${label}`);
      for (const route of ['/api/team/feedback?limit=1', '/api/team/metrics?days=1', '/api/team/website?days=1',
        '/api/team/operational-status']) {
        requireCheck((await call(label, route)).status === 403);
      }
      const proof = await call(label, '/api/account/isolation', 'POST', { peerUserId });
      requireCheck(proof.status === 200);
      isolationSummary(proof.data, identities.get(label));
      requireCheck(proof.data.checks.teamFeedback === 403);
      evidence.accounts.push({ label, sameIdRecordsIsolated: true, foreignRead: 400, foreignWrite: 400,
        teamRoutes: 403, auditId: proof.data.auditId });
    }
    evidence.phase = 'admin-metrics';
    const admin = await call('ADMIN', '/api/team/metrics?days=1');
    requireCheck(admin.status === 200 && admin.data && Array.isArray(admin.data.daily));
    evidence.adminMetrics = 200;
    evidence.passed = true;
  } catch {
    evidence.passed = false;
  } finally {
    let cleaned = true;
    for (const label of ['A', 'B']) {
      try {
        const result = await call(label, '/api/sync', 'POST', {
          ...empty(), deletions: ['habits', 'voice'].map(type => ({
            id: randomUUID(), type, recordId: type === 'habits' ? habitId : voiceId, ts: now(),
          })),
        });
        requireCheck(result.status === 200 && Array.isArray(result.data.habits) && Array.isArray(result.data.voice) &&
          !result.data.habits.some(row => row.id === habitId) && !result.data.voice.some(row => row.id === voiceId));
      } catch { cleaned = false; }
    }
    evidence.cleanup = cleaned ? 'passed' : 'failed';
    evidence.passed &&= cleaned;
    if (evidence.passed) evidence.phase = 'complete';
  }
  return evidence;
}

export async function signIn(browser, account, clientId, tokenFetcher = fetch) {
  if (!/^[a-f0-9-]{36}$/i.test(clientId ?? '')) throw Error('Automation client is not configured.');
  const verifier = randomBytes(32).toString('base64url'), state = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  let receive, reject, timer;
  const callback = new Promise((resolve, fail) => { receive = resolve; reject = fail; });
  // Attach rejection handling before browser navigation; callback values never enter logs.
  callback.catch(() => {});
  const server = createServer((request, response) => {
    const url = new URL(request.url ?? '/', redirectUri);
    const valid = request.method === 'GET' && url.pathname === '/automation-callback' &&
      url.searchParams.get('state') === state && url.searchParams.has('code') && !url.searchParams.has('error');
    response.writeHead(valid ? 200 : 400, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    response.end(valid ? 'Automation sign-in completed.' : 'Automation sign-in rejected.');
    if (valid) receive(url.searchParams.get('code'));
    else reject(Error('Automation callback rejected.'));
  });
  const context = await browser.newContext();
  let page;
  try {
    await new Promise((resolve, fail) => { server.once('error', fail); server.listen(8400, '127.0.0.1', resolve); });
    timer = setTimeout(() => reject(Error('Automation sign-in timed out.')), 120000);
    const url = new URL(`${authority}/oauth2/v2.0/authorize`);
    url.search = new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: redirectUri,
      response_mode: 'query', scope: `openid profile ${scope}`, state, code_challenge: challenge,
      code_challenge_method: 'S256', prompt: 'login' }).toString();
    page = await context.newPage();
    page.setDefaultTimeout(30000);
    await page.goto(url.href);
    const brokerOnly = () => requireCheck(new URL(page.url()).origin === new URL(authority).origin);
    brokerOnly();
    await page.locator('input[type="email"], input[name="username"], input[name="signInName"], input[name="loginfmt"]').first().fill(account.email);
    if (!await page.locator('input[type="password"]').isVisible()) {
      await page.getByRole('button', { name: /^(Next|Sign in|Continue)$/i }).click();
    }
    await page.locator('input[type="password"]').waitFor();
    brokerOnly();
    await page.locator('input[type="password"]').fill(account.password);
    await page.getByRole('button', { name: /^(Next|Sign in|Continue)$/i }).click();
    const code = await Promise.race([callback, (async () => {
      while (server.listening) {
        const text = await page.locator('body').innerText().catch(() => '');
        const prompt = text.match(/Approve sign[- ]in request|More information required|Verify your identity|Enter (?:the )?verification code|Set up (?:your )?account|Help us protect your account/i)?.[0];
        if (prompt) throw Error(`Hosted sign-in blocked: ${prompt}`);
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      return callback;
    })()]);
    const response = await tokenFetcher(`${authority}/oauth2/v2.0/token`, {
      method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: clientId, grant_type: 'authorization_code', code,
        redirect_uri: redirectUri, code_verifier: verifier, scope }),
    });
    if (!response.ok) throw Error('Automation code exchange failed.');
    const result = await response.json();
    if (typeof result.access_token !== 'string' || !result.access_token) throw Error('Automation token unavailable.');
    return result.access_token;
  } catch (error) {
    if (error.message.startsWith('Hosted sign-in blocked:')) throw error;
    const text = page ? await page.locator('body').innerText().catch(() => '') : '';
    const controls = page ? await page.locator('input').evaluateAll(inputs => inputs.map(input => ({
      type: input.type, id: input.id, name: input.name,
    }))).catch(() => []) : [];
    const host = page ? new URL(page.url()).origin : 'unknown';
    throw Error(`Hosted sign-in failed: ${redactSignInText(error.message.split('\n')[0], account)}; ${host}; controls=${JSON.stringify(controls)}; ${redactSignInText(text, account)}`);
  } finally {
    clearTimeout(timer);
    await context.close();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}

export async function createAutomationBrowser() {
  const { chromium } = await import('playwright');
  return chromium.launch({ headless: true });
}

async function main() {
  let accounts = [], browser;
  const tokens = new Map();
  let evidence = { schemaVersion: 1, passed: false, phase: 'sign-in', cleanup: 'not-started' };
  let provisioning;
  try {
    provisioning = JSON.parse(process.env.BUDLARK_AUTOMATION_PROVISIONING_RECEIPT ?? '{}');
    requireCheck(provisioning.passed === true && provisioning.temporaryCreated === true &&
      provisioning.temporaryDeleted === true && provisioning.users === 3 &&
      provisioning.clientId === process.env.BUDLARK_AUTOMATION_CLIENT_ID);
    accounts = automationAccounts(process.env);
    for (const label of ['A', 'B', 'ADMIN']) {
      delete process.env[`BUDLARK_TEST_${label}_EMAIL`];
      delete process.env[`BUDLARK_TEST_${label}_PASSWORD`];
    }
    browser = await createAutomationBrowser();
    for (const account of accounts) {
      evidence.phase = `sign-in-${account.label}`;
      tokens.set(account.label, await signIn(browser, account, process.env.BUDLARK_AUTOMATION_CLIENT_ID));
    }
    evidence = await runIsolationAcceptance(async (label, route, method = 'GET', body) => {
      if (!tokens.has(label) || !/^\/api\/(?:sync(?:\?userId=[a-f0-9]{64})?|account\/isolation|team\/(?:feedback\?limit=1|metrics\?days=1|website\?days=1|operational-status))$/.test(route)) {
        throw Error('Automation API route rejected.');
      }
      const response = await fetch(origin + route, { method, redirect: 'error', signal: AbortSignal.timeout(30000),
        headers: { 'X-Budlark-Authorization': `Bearer ${tokens.get(label)}`, 'Content-Type': 'application/json' },
        ...(body ? { body: JSON.stringify(body) } : {}) });
      return { status: response.status, data: await response.json() };
    });
  } catch (error) {
    evidence.passed = false;
    if (error.message.startsWith('Hosted sign-in blocked:')) evidence.prompt = error.message;
  } finally {
    tokens.clear();
    for (const account of accounts) account.password = '';
    for (const label of ['A', 'B', 'ADMIN']) {
      delete process.env[`BUDLARK_TEST_${label}_EMAIL`];
      delete process.env[`BUDLARK_TEST_${label}_PASSWORD`];
    }
    await browser?.close();
    const receipt = provisioning?.passed === true ? {
      temporaryCreated: provisioning.temporaryCreated, temporaryDeleted: provisioning.temporaryDeleted,
      users: provisioning.users, securityDefaultsEnabled: provisioning.securityDefaultsEnabled,
      conditionalAccessPolicyCount: provisioning.conditionalAccessPolicyCount,
      timestamp: provisioning.timestamp,
    } : null;
    await writeFile('production-isolation-evidence.json', JSON.stringify({ ...evidence, provisioning: receipt,
      timestamp: new Date().toISOString() }, null, 2));
  }
  console.log(evidence.passed ? 'Production isolation acceptance passed.' : `Production isolation acceptance failed at ${evidence.phase}; sanitized evidence saved.`);
  process.exitCode = evidence.passed ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
