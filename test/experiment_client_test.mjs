import test from 'node:test';
import assert from 'node:assert/strict';
import { createExperimentClient } from '../site/experiment-client.mjs';
import { CATALOG, assignArm, freezeInstance } from '../api/src/experiment-policy.mjs';

const active = await freezeInstance(CATALOG[0], { startAt: '2026-10-01T00:00:00.000Z', environment: 'isolated' });
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const until = async predicate => {
  for (let i = 0; i < 200; i++) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  assert.fail('Expected lifecycle boundary was not reached.');
};
let nextId = 0;
const uuid = () => `00000000-0000-4000-8000-${String(++nextId).padStart(12, '0')}`;
const candidateId = async () => {
  for (;;) {
    const id = uuid();
    if (await assignArm(active, id) === 'candidate') return id;
  }
};
function fixture({ config, exposure, deletion, allowed } = {}) {
  const calls = [];
  const node = { textContent: CATALOG[0].control.value };
  const client = createExperimentClient({
    document: { querySelector: () => node }, uuid, allowed,
    fetchJson: async (path, body) => {
      calls.push({ path, body });
      if (path === '/api/web/experiments') return config ? config() : { enabled: true, active };
      if (path.endsWith('/exposure')) return exposure?.(body) ?? {};
      if (path.endsWith('/forget')) return deletion?.(body) ?? {};
      return {};
    },
  });
  return { client, calls, node };
}

test('withdrawal before configuration completes cancels enrollment and coalesces duplicate starts', async () => {
  const response = deferred();
  const { client, calls, node } = fixture({ config: () => response.promise });
  const first = client.start(), second = client.start();
  assert.equal(await client.stop(), false);
  response.resolve({ enabled: true, active });
  assert.deepEqual(await first, { active: false, arm: null });
  assert.deepEqual(await second, { active: false, arm: null });
  assert.deepEqual(calls.map(call => call.path), ['/api/web/experiments']);
  assert.equal(node.textContent, CATALOG[0].control.value);
  assert.equal(client.state.active, false);
});

test('privacy eligibility is rechecked after configuration, before assignment or exposure', async () => {
  let allowed = true;
  const response = deferred();
  const { client, calls } = fixture({ config: () => response.promise, allowed: () => allowed });
  const start = client.start();
  allowed = false;
  response.resolve({ enabled: true, active });
  assert.equal((await start).active, false);
  assert.equal(calls.length, 1);
  assert.equal((await client.start()).active, false);
  assert.equal(await client.outcome('download_click'), false);
});

test('withdrawal while assignment is pending prevents variant application and exposure', async () => {
  const calls = [], node = { textContent: CATALOG[0].control.value };
  let client;
  client = createExperimentClient({
    document: { querySelector: () => node },
    uuid: () => { void client.stop(); return uuid(); },
    fetchJson: async path => { calls.push(path); return { enabled: true, active }; },
  });
  assert.equal((await client.start()).active, false);
  assert.equal(node.textContent, CATALOG[0].control.value);
  assert.deepEqual(calls, ['/api/web/experiments']);
});

test('withdrawal after a completed exposure removes that subject and blocks later outcomes', async () => {
  const { client, calls } = fixture();
  await client.start();
  assert.equal(await client.outcome('download_click'), true);
  assert.equal(await client.stop(), true);
  assert.equal(await client.outcome('download_click'), false);
  assert.equal(calls.at(-1).path, '/api/web/experiments/forget');
  assert.equal(calls.at(-1).body.subjectId, calls.find(call => call.path.endsWith('/exposure')).body.subjectId);
  assert.equal(await client.stop(), false);
});

test('withdrawal restores control immediately and deletes even an ambiguously failed in-flight exposure', async () => {
  const response = deferred(), entered = deferred();
  const id = await candidateId();
  const node = { textContent: CATALOG[0].control.value }, calls = [];
  const client = createExperimentClient({
    document: { querySelector: () => node }, uuid: () => id,
    fetchJson: async (path, body) => {
      calls.push({ path, body });
      if (path === '/api/web/experiments') return { enabled: true, active };
      if (path.endsWith('/exposure')) { entered.resolve(); return response.promise; }
      return {};
    },
  });
  const start = client.start();
  await entered.promise;
  assert.equal(node.textContent, CATALOG[0].candidate.value);
  assert.equal(await client.outcome('download_click'), false);
  const stop = client.stop();
  assert.equal(node.textContent, CATALOG[0].control.value);
  assert.equal(client.state.active, false);
  response.reject(Error('Response lost after possible commit'));
  assert.equal((await start).active, false);
  assert.equal(await stop, true);
  assert.equal(calls.filter(call => call.path.endsWith('/forget')).length, 1);
  assert.equal(calls.at(-1).body.subjectId, id);
});

test('failed candidate exposure restores control, forgets possible commit and permits a fresh enrollment', async () => {
  const id = await candidateId();
  const node = { textContent: CATALOG[0].control.value }, calls = [];
  let fail = true;
  const client = createExperimentClient({
    document: { querySelector: () => node }, uuid: () => fail ? id : uuid(),
    fetchJson: async (path, body) => {
      calls.push({ path, body });
      if (path === '/api/web/experiments') return { enabled: true, active };
      if (path.endsWith('/exposure') && fail) {
        assert.equal(node.textContent, CATALOG[0].candidate.value);
        throw Error('503 fixture');
      }
      return {};
    },
  });
  await assert.rejects(client.start(), /503 fixture/);
  assert.equal(node.textContent, CATALOG[0].control.value);
  assert.equal(client.state.active, false);
  assert.equal(await client.outcome('download_click'), false);
  assert.equal(calls.at(-1).path, '/api/web/experiments/forget');
  fail = false;
  assert.equal((await client.start()).active, true);
  assert.equal(await client.outcome('download_click'), true);
  assert.equal(calls.filter(call => call.path.endsWith('/exposure')).length, 2);
  await client.stop();
});

test('failed withdrawal remains retryable; reconsent cannot bypass unconfirmed cleanup', async () => {
  let fail = true;
  const { client, calls, node } = fixture({ deletion: () => {
    if (fail) throw Error('Deletion unavailable');
    return {};
  } });
  await client.start();
  await assert.rejects(client.stop(), /Deletion unavailable/);
  assert.equal(client.state.active, false);
  assert.equal(node.textContent, CATALOG[0].control.value);
  await assert.rejects(client.start(), /Deletion unavailable/);
  assert.equal(calls.filter(call => call.path === '/api/web/experiments').length, 1);
  fail = false;
  assert.equal(await client.stop(), true);
  assert.equal((await client.start()).active, true);
  await client.stop();
});

test('stale configuration cannot enroll or overwrite a newly consented visit', async () => {
  const response = deferred();
  let configs = 0;
  const { client, calls } = fixture({ config: () => ++configs === 1 ? response.promise : { enabled: true, active } });
  const stale = client.start();
  await client.stop();
  const fresh = await client.start();
  response.resolve({ enabled: true, active });
  assert.equal((await stale).active, false);
  assert.deepEqual(client.state, fresh);
  assert.equal(calls.filter(call => call.path.endsWith('/exposure')).length, 1);
  await client.stop();
});

test('disabled production configuration remains noncollecting control', async () => {
  const { client, calls, node } = fixture({ config: () => ({ enabled: false, active: null }) });
  assert.equal((await client.start()).active, false);
  assert.equal(await client.outcome('download_click'), false);
  assert.equal(await client.stop(), false);
  assert.equal(node.textContent, CATALOG[0].control.value);
  assert.equal(calls.length, 1);
});

test('missing variant surface never sends exposure and leaves the client in control', async () => {
  const calls = [];
  const client = createExperimentClient({
    document: { querySelector: () => null }, uuid,
    fetchJson: async path => { calls.push(path); return { enabled: true, active }; },
  });
  await assert.rejects(client.start(), /surface missing/);
  assert.equal(client.state.active, false);
  assert.equal(calls.some(path => path.endsWith('/exposure')), false);
  assert.equal(await client.outcome('download_click'), false);
});

async function customerFixture(t, configResponse = { enabled: true, active }) {
  const element = () => ({
    checked: false, disabled: false, textContent: '', handlers: {},
    addEventListener(name, handler) { this.handlers[name] = handler; },
  });
  const elements = Object.fromEntries(['primary-cta', 'website-consent', 'website-status', 'receipt-consent',
    'receipt-export', 'receipt-status', 'receipt-clear', 'invitation'].map(id => [id, element()]));
  const heading = { textContent: CATALOG[0].control.value };
  const document = { documentElement: { dataset: {} }, referrer: '',
    getElementById: id => elements[id], querySelectorAll: () => [], querySelector: () => heading };
  const window = { handlers: {}, addEventListener(name, handler) {
    const previous = this.handlers[name];
    this.handlers[name] = () => { previous?.(); handler(); };
  } };
  const navigator = {}, calls = [];
  const values = { document, window, navigator, location: { origin: 'https://example.test', search: '' },
    fetch: async (path, options) => {
      calls.push({ path, options });
      const body = path === '/api/web/experiments' ? await configResponse : {};
      return { ok: true, status: path === '/api/web/events' ? 202 : 200, json: async () => body };
    } };
  const originals = Object.fromEntries(Object.keys(values).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  for (const [key, value] of Object.entries(values)) Object.defineProperty(globalThis, key, { configurable: true, value });
  t.after(() => {
    for (const [key, descriptor] of Object.entries(originals)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  });
  await import(`../site/customer.mjs?lifecycle-test=${uuid()}`);
  return { elements, document, window, navigator, calls };
}

test('customer withdrawal during pending config neither exposes nor writes stale arm metadata', async t => {
  const response = deferred();
  const { elements, document, calls } = await customerFixture(t, response.promise);
  const consent = elements['website-consent'];
  consent.checked = true; consent.handlers.change();
  await until(() => calls.some(call => call.path === '/api/web/experiments'));
  consent.checked = false; consent.handlers.change();
  response.resolve({ enabled: true, active });
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal(calls.some(call => call.path.endsWith('/exposure')), false);
  assert.equal(document.documentElement.dataset.experimentArm, undefined);
});

test('customer privacy signal permits deletion but prevents further collection', async t => {
  const { elements, document, navigator, calls } = await customerFixture(t);
  const consent = elements['website-consent'];
  consent.checked = true; consent.handlers.change();
  await until(() => document.documentElement.dataset.experimentArm !== undefined);
  navigator.globalPrivacyControl = true;
  consent.handlers.change();
  await until(() => calls.some(call => call.path.endsWith('/forget')));
  assert.equal(consent.checked, false);
  assert.equal(document.documentElement.dataset.experimentArm, undefined);
  assert.equal(calls.at(-1).path, '/api/web/experiments/forget');
});

test('customer pagehide ends collection without deleting completed consented observations', async t => {
  const { elements, document, window, calls } = await customerFixture(t);
  const consent = elements['website-consent'];
  consent.checked = true; consent.handlers.change();
  await until(() => document.documentElement.dataset.experimentArm !== undefined);
  window.handlers.pagehide();
  assert.equal(consent.checked, false);
  assert.equal(document.documentElement.dataset.experimentArm, undefined);
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(calls.some(call => call.path.endsWith('/forget')), false);
});

test('page exit cancels pending configuration without creating an exposure', async () => {
  const response = deferred();
  const { client, calls } = fixture({ config: () => response.promise });
  const pending = client.start();
  await client.end();
  response.resolve({ enabled: true, active });
  assert.equal((await pending).active, false);
  assert.equal(client.state.active, false);
  assert.equal(calls.length, 1);
});
