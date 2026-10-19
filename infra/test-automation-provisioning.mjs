import test from 'node:test';
import assert from 'node:assert/strict';
import { automationUser, provisioningPreflight, temporaryPermissions, provisionAutomation } from './provision-automation.mjs';

test('provisioning is restricted to the approved tenant, free temporary Graph scopes and no customer-policy changes', () => {
  const organization = { id: '80e48373-4f7c-4871-9223-1c83a780bba9', verifiedDomains: [{ name: 'budlarkcustomers261004.onmicrosoft.com', isDefault: true }] };
  const safe = { organization, defaults: { isEnabled: false }, policies: { value: [] },
    providers: { value: [{ id: 'EmailPassword-OAUTH', identityProviderType: 'EmailPassword' }] } };
  assert.equal(provisioningPreflight(safe), 'budlarkcustomers261004.onmicrosoft.com');
  assert.equal(provisioningPreflight({ ...safe, defaults: { isEnabled: true } }), 'budlarkcustomers261004.onmicrosoft.com');
  assert.deepEqual(temporaryPermissions, ['EventListener.ReadWrite.All', 'IdentityProvider.Read.All', 'Policy.Read.All']);
  for (const bad of [{ ...safe, organization: { ...organization, id: 'other' } },
    { ...safe, defaults: { isEnabled: 'unknown' } }, { ...safe, defaults: {} },
    { ...safe, policies: { value: [{ state: 'enabled' }] } },
    { ...safe, policies: { value: [], '@odata.nextLink': 'more' } },
    { ...safe, providers: { value: [] } }]) {
    assert.throws(() => provisioningPreflight(bad), /Provisioning preflight/);
  }
});

test('existing dedicated users migrate in place and read back before credentials are published', async () => {
  const domain = 'existing-customers.onmicrosoft.com';
  const prefix = ['bloom', 'step'].join('');
  for (const label of ['a', 'b', 'admin']) {
    const calls = [];
    let stored = { id: `user-${label}`, displayName: `${prefix}-test-${label}`,
      identities: [{ signInType: 'emailAddress', issuer: domain, issuerAssignedId: `${prefix}-test-${label}@${domain}` }] };
    const graph = async (method, path, body) => {
      calls.push({ method, path });
      if (method === 'GET' && path.startsWith('/users?')) return {
        value: path.includes(`'${stored.identities[0].issuerAssignedId}'`) ? [stored] : [],
      };
      if (method === 'PATCH' && path === `/users/user-${label}`) { stored = { ...stored, ...body }; return; }
      if (method === 'GET' && path.startsWith(`/users/user-${label}?`)) return stored;
      assert.fail(`Unexpected operation: ${method} ${path}`);
    };
    const profile = { password: 'synthetic-password-not-for-login', forceChangePasswordNextSignIn: false };
    const result = await automationUser(graph, { label, domain, passwordProfile: profile });
    assert.equal(result.user.id, `user-${label}`);
    assert.equal(result.email, `budlark-test-${label}@${domain}`);
    assert.equal(stored.passwordProfile, profile);
    assert.equal(calls.some(call => call.method === 'POST' || call.method === 'DELETE'), false);
  }
});

test('ambiguous, incomplete or unowned test users fail before mutation', async () => {
  const domain = 'existing-customers.onmicrosoft.com';
  for (const scenario of ['duplicate', 'unowned', 'paginated']) {
    const graph = async (method, path) => {
      assert.equal(method, 'GET');
      const address = path.match(/issuerAssignedId eq '([^']+)'/)[1];
      const name = address.split('@')[0];
      return { value: scenario === 'paginated' ? [] : [{
        id: name, displayName: scenario === 'unowned' ? 'customer' : name,
        identities: [{ signInType: 'emailAddress', issuer: domain, issuerAssignedId: address }],
      }], ...(scenario === 'paginated' ? { '@odata.nextLink': 'more' } : {}) };
    };
    await assert.rejects(automationUser(graph, { label: 'a', domain, passwordProfile: {} }),
      /Ambiguous|ownership unverified|Incomplete/);
  }
});

test('temporary credentials and assignments are removed even when policy preflight blocks provisioning', async () => {
  const calls = [];
  const clock = () => new Date('2026-10-12T01:00:00Z');
  const graph = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === 'DELETE') return;
    if (path.startsWith('/organization')) return { value: [{ id: '80e48373-4f7c-4871-9223-1c83a780bba9', verifiedDomains: [{ name: 'budlarkcustomers261004.onmicrosoft.com', isDefault: true }] }] };
    if (path.startsWith('/servicePrincipals/7f7')) return { appId: 'api', appRoles: [{ id: 'admin', value: 'Budlark.Admin', isEnabled: true, allowedMemberTypes: ['User'] }],
      oauth2PermissionScopes: [{ id: 'garden', value: 'Garden.ReadWrite', isEnabled: true }] };
    if (path.startsWith('/servicePrincipals?')) return { value: [{ id: 'graph', appRoles: temporaryPermissions.map((value, id) => ({ id: String(id), value, isEnabled: true, allowedMemberTypes: ['Application'] })) }] };
    if (method === 'POST' && path === '/applications') return { id: 'temp-app', appId: 'temp-client' };
    if (method === 'POST' && path === '/servicePrincipals') return { id: 'temp-sp' };
    if (path.endsWith('/appRoleAssignments')) return { id: `role-${calls.length}` };
    if (path.endsWith('/addPassword')) {
      assert.equal(Date.parse(body.passwordCredential.endDateTime) - clock().getTime(), 45 * 60000);
      return { secretText: 'synthetic-temporary-credential', keyId: 'synthetic-key-id' };
    }
    if (path.endsWith('/removePassword')) return;
    if (path.includes('SecurityDefaults')) return { isEnabled: true };
    if (path.includes('conditionalAccess')) return { value: [{ state: 'enabled' }] };
    if (path.includes('identityProviders')) return { value: [{ id: 'EmailPassword-OAUTH', identityProviderType: 'EmailPassword' }] };
    if (path.startsWith('/applications?')) return { value: [] };
    throw Error('Unexpected provisioning operation.');
  };
  const evidence = await provisionAutomation({ graph, clock, authenticateTemporary: async () => {},
    secret: async () => assert.fail('No secret should be created'), variable: async () => assert.fail('No client variable should be created') });
  assert.equal(evidence.passed, false);
  assert.equal(evidence.users, 0);
  assert.equal(evidence.temporaryCreated, true);
  assert.equal(evidence.temporaryDeleted, true);
  assert.equal(calls.filter(c => c.method === 'DELETE' && c.path.includes('appRoleAssignments')).length, 3);
  assert.ok(calls.some(c => c.method === 'DELETE' && c.path === '/servicePrincipals/temp-sp'));
  assert.ok(calls.some(c => c.method === 'DELETE' && c.path === '/applications/temp-app'));
  assert.ok(calls.some(c => c.method === 'POST' && c.path === '/applications/temp-app/removePassword' && c.body.keyId === 'synthetic-key-id'));
  assert.equal(calls.some(c => ['PATCH', 'PUT'].includes(c.method)), false);
});
