import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { SignJWT } from 'jose';
import { createLocalTestServer } from './support/local_api_server.mjs';

const issuer = 'https://bloomstep.test';
const audience = 'bloomstep-test-api';
const secret = () => randomBytes(32);
const repositoryRoot = fileURLToPath(new URL('../../', import.meta.url));
const apiServerEntry = fileURLToPath(
  new URL('./support/local_api_server.mjs', import.meta.url),
);
const sign = async (key, sub, claims = {}) => new SignJWT({
  scp: 'Garden.ReadWrite',
  ...claims,
})
  .setProtectedHeader({ alg: 'HS256' })
  .setIssuer(issuer)
  .setSubject(sub)
  .setAudience(audience)
  .setIssuedAt()
  .setExpirationTime('2m')
  .sign(key);

async function request(url, token, method = 'GET', payload = undefined) {
  return fetch(`${url}/api/sync`, {
    method,
    headers: {
      'x-bloomstep-authorization': `Bearer ${token}`,
      ...(payload === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
  });
}

async function startServerProcess(databasePath, key, reuseDatabase = false) {
  const environment = {
    BLOOMSTEP_TEST_AUTH_SECRET: key.toString('hex'),
    BLOOMSTEP_TEST_DATABASE: databasePath,
    BLOOMSTEP_TEST_PORT: '0',
    BLOOMSTEP_TEST_REUSE_DATABASE: String(reuseDatabase),
    ...(process.env.PATH ? { PATH: process.env.PATH } : {}),
    ...(process.platform === 'win32' && process.env.SystemRoot
      ? { SystemRoot: process.env.SystemRoot }
      : {}),
  };
  const child = spawn(process.execPath, [apiServerEntry], {
    cwd: repositoryRoot,
    env: environment,
    stdio: ['pipe', 'pipe', 'ignore'],
  });
  let output = '';
  let resolved = false;
  let resolveReady;
  let rejectReady;
  const ready = new Promise((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    output += chunk;
    const match = /^TEST_API_READY ([0-9]{1,5})$/m.exec(output);
    if (match && !resolved) {
      resolved = true;
      resolveReady(Number(match[1]));
    }
  });
  child.once('error', () => {
    if (!resolved) rejectReady(new Error('The isolated test API process failed to start.'));
  });
  child.once('exit', () => {
    if (!resolved) rejectReady(new Error('The isolated test API process exited before readiness.'));
  });
  let port;
  let readyTimeout;
  try {
    port = await Promise.race([
      ready,
      new Promise((_, reject) => {
        readyTimeout = setTimeout(
          () => reject(new Error('The isolated test API process did not become ready.')),
          30000,
        );
      }),
    ]);
  } catch (error) {
    const exited = child.exitCode === null ? once(child, 'exit') : null;
    child.kill();
    await exited;
    throw error;
  } finally {
    clearTimeout(readyTimeout);
  }
  return {
    url: `http://127.0.0.1:${port}`,
    async close() {
      if (child.exitCode !== null) return;
      const exited = once(child, 'exit');
      child.stdin.end('shutdown\n');
      const timeout = setTimeout(() => child.kill(), 10000);
      const [code] = await exited;
      clearTimeout(timeout);
      assert.equal(code, 0);
    },
  };
}

test('test-key auth runs production sync and deletion handlers on restartable disposable owner partitions', async () => {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  const databasePath = join(root, 'server.json');
  const key = secret();
  let server = await createLocalTestServer({ databasePath, key, port: 0 });
  try {
    assert.match(server.url, /^http:\/\/127\.0\.0\.1:\d+$/);
    assert.equal((await fetch(`${server.url}/healthz`)).status, 200);
    assert.equal(
      (await fetch(`${server.url}/api/account`, { method: 'DELETE' })).status,
      404,
    );
    assert.equal((await fetch(`${server.url}/admin/feedback`)).status, 404);
    const alice = await sign(key, 'synthetic-alice');
    const bob = await sign(key, 'synthetic-bob');
    const realAccountShape = await sign(key, 'someone@example.com');
    const wrong = await sign(secret(), 'synthetic-alice');
    const unauthorized = await request(server.url, wrong);
    assert.equal(unauthorized.status, 401);
    assert.deepEqual(await unauthorized.json(), {
      error: 'Identity token could not be validated.',
    });
    assert.equal((await request(server.url, realAccountShape)).status, 401);
    const wrongScope = await sign(key, 'synthetic-alice', {
      scp: 'User.Read',
    });
    assert.equal((await request(server.url, wrongScope)).status, 401);
    const expired = await new SignJWT({ scp: 'Garden.ReadWrite' })
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer(issuer)
      .setSubject('synthetic-alice')
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime('0s')
      .sign(key);
    assert.equal((await request(server.url, expired)).status, 401);
    const adminClaim = await sign(key, 'synthetic-alice', {
      roles: ['Bloomstep.Admin'],
    });
    assert.equal((await request(server.url, adminClaim)).status, 401);
    assert.equal(
      (await fetch(`${server.url}/api/sync`)).status,
      401,
    );

    const habitId = randomUUID();
    const payload = {
      habits: [{
        id: habitId,
        aspiration: 'calm',
        anchor: 'open test app',
        behavior: 'breathe once',
        celebration: 'smile',
        species: 'Fern',
        stage: 0,
        status: 'active',
        updated: new Date().toISOString(),
      }],
      checkins: [],
      reflections: [],
      voice: [],
      events: [],
      settings: [],
      deletions: [],
    };
    const saved = await request(server.url, alice, 'POST', payload);
    assert.equal(saved.status, 200);
    assert.equal((await saved.json()).habits[0].id, habitId);
    const isolated = await request(server.url, bob);
    assert.deepEqual((await isolated.json()).habits, []);
    const readback = await request(server.url, alice);
    assert.equal((await readback.json()).habits[0].id, habitId);

    const deleted = await request(server.url, alice, 'POST', {
      habits: [],
      checkins: [],
      reflections: [],
      voice: [],
      events: [],
      settings: [],
      deletions: [{
        id: randomUUID(),
        type: 'habits',
        recordId: habitId,
        ts: new Date().toISOString(),
      }],
    });
    assert.equal(deleted.status, 200);
    assert.deepEqual((await deleted.json()).habits, []);

    const persisted = await readFile(databasePath, 'utf8');
    assert.equal(persisted.includes(key.toString('base64')), false);
    assert.equal(persisted.includes('Bearer'), false);
    await server.close();
    server = await createLocalTestServer({
      databasePath,
      key,
      port: 0,
      reuseDatabase: true,
    });
    const afterRestart = await request(server.url, alice);
    const restarted = await afterRestart.json();
    assert.deepEqual(restarted.habits, []);
    assert.equal(
      restarted.deletions.some(row => row.recordId === habitId),
      true,
    );
    assert.deepEqual((await (await request(server.url, bob)).json()).habits, []);
  } finally {
    await server.close();
    await rm(root, { recursive: true, force: true });
  }
});

test('test API refuses missing keys and database paths outside a new temporary run', async () => {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  try {
    await assert.rejects(
      createLocalTestServer({
        databasePath: join(root, 'server.json'),
        key: undefined,
        port: 0,
      }),
      /test authentication unavailable/,
    );
    await assert.rejects(
      createLocalTestServer({
        databasePath: join(tmpdir(), 'not-a-bloomstep-test.json'),
        key: secret(),
        port: 0,
      }),
      /disposable test directory/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('test API process restart preserves owner data and deletion tombstones without forwarding credentials', async () => {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  const databasePath = join(root, 'server-process.json');
  const key = secret();
  let server;
  try {
    server = await startServerProcess(databasePath, key);
    const alice = await sign(key, 'synthetic-restart');
    const habitId = randomUUID();
    const payload = {
      habits: [{
        id: habitId,
        aspiration: 'focus',
        anchor: 'open test app',
        behavior: 'write one word',
        celebration: 'smile',
        species: 'Fern',
        stage: 0,
        status: 'active',
        updated: new Date().toISOString(),
      }],
      checkins: [],
      reflections: [],
      voice: [],
      events: [],
      settings: [],
      deletions: [],
    };
    assert.equal((await request(server.url, alice, 'POST', payload)).status, 200);
    await server.close();

    server = await startServerProcess(databasePath, key, true);
    const afterRestart = await (await request(server.url, alice)).json();
    assert.equal(afterRestart.habits[0].id, habitId);
    const bob = await sign(key, 'synthetic-other');
    assert.deepEqual((await (await request(server.url, bob)).json()).habits, []);

    const deletion = [{
      id: randomUUID(),
      type: 'habits',
      recordId: habitId,
      ts: new Date().toISOString(),
    }];
    const deleted = await request(server.url, alice, 'POST', {
      habits: [],
      checkins: [],
      reflections: [],
      voice: [],
      events: [],
      settings: [],
      deletions: deletion,
    });
    assert.equal(deleted.status, 200);
    await server.close();

    server = await startServerProcess(databasePath, key, true);
    const finalRead = await (await request(server.url, alice)).json();
    assert.deepEqual(finalRead.habits, []);
    assert.equal(finalRead.deletions.some(row => row.recordId === habitId), true);
    assert.deepEqual((await (await request(server.url, bob)).json()).habits, []);
    const persisted = await readFile(databasePath, 'utf8');
    assert.equal(persisted.includes(key.toString('hex')), false);
    assert.equal(persisted.includes(alice), false);
  } finally {
    try {
      await server?.close();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  }
});
