import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const tenant = '80e48373-4f7c-4871-9223-1c83a780bba9';
const apiSp = '7f7fc77f-e06c-465e-89ef-c6896009d287';
const graphAppId = '00000003-0000-0000-c000-000000000000';
const retiredPrefix = ['bloom', 'step'].join('');
export const temporaryPermissions = ['EventListener.ReadWrite.All', 'IdentityProvider.Read.All', 'Policy.Read.All'];

export function provisioningPreflight({ organization, defaults, policies, providers }) {
  const domains = organization?.verifiedDomains?.filter(d => d.isDefault && /^[a-z0-9-]+\.onmicrosoft\.com$/.test(d.name)) ?? [];
  if (organization?.id !== tenant || domains.length !== 1 ||
      typeof defaults?.isEnabled !== 'boolean' || !Array.isArray(policies?.value) || policies.value.length ||
      policies['@odata.nextLink'] || !providers?.value?.some(p => p.id === 'EmailPassword-OAUTH' && p.identityProviderType === 'EmailPassword')) {
    throw Error('Provisioning preflight failed; no customer protections may be changed.');
  }
  return domains[0].name;
}

export async function automationUser(graph, { label, domain, passwordProfile }) {
  if (!['a', 'b', 'admin'].includes(label) || !/^[a-z0-9-]+\.onmicrosoft\.com$/.test(domain)) {
    throw Error('Invalid automation identity.');
  }
  const email = `budlark-test-${label}@${domain}`;
  const retiredEmail = `${retiredPrefix}-test-${label}@${domain}`;
  const matches = [];
  for (const address of [email, retiredEmail]) {
    const result = await graph('GET', `/users?$filter=identities/any(c:c/issuerAssignedId eq '${address}' and c/issuer eq '${domain}')&$select=id,displayName,identities`);
    if (!Array.isArray(result.value) || result['@odata.nextLink']) throw Error('Incomplete test user inventory.');
    for (const user of result.value) {
      const prefix = address === email ? 'budlark' : retiredPrefix;
      if (user.displayName !== `${prefix}-test-${label}` ||
          user.identities?.length !== 1 ||
          !user.identities.some(identity => identity.signInType === 'emailAddress' &&
            identity.issuer === domain && identity.issuerAssignedId === address)) {
        throw Error('Test user ownership unverified.');
      }
      matches.push(user);
    }
  }
  if (matches.length > 1) throw Error('Ambiguous test users; no identities were changed.');
  const identity = { signInType: 'emailAddress', issuer: domain, issuerAssignedId: email };
  const body = { displayName: `budlark-test-${label}`, identities: [identity], passwordProfile };
  const existing = matches[0];
  const user = existing ?? await graph('POST', '/users', {
    ...body, accountEnabled: true, passwordPolicies: 'DisablePasswordExpiration',
  });
  if (existing) await graph('PATCH', `/users/${user.id}`, body);
  const actual = await graph('GET', `/users/${user.id}?$select=id,displayName,identities`);
  if (actual.id !== user.id || actual.displayName !== body.displayName ||
      actual.identities?.length !== 1 ||
      !actual.identities.some(value => value.signInType === identity.signInType &&
        value.issuer === domain && value.issuerAssignedId === email)) {
    throw Error('Test user migration readback failed.');
  }
  return { user: actual, email };
}

export async function provisionAutomation({ graph, authenticateTemporary, verifySignIn, secret, variable, clock = () => new Date() }) {
  const evidence = { passed: false, stage: 'tenant-preflight', temporaryCreated: false, temporaryDeleted: false, users: 0 };
  let temporaryApp, temporarySp, temporaryCredentialKey;
  const assignments = [];
  let failure;
  try {
    const organization = (await graph('GET', '/organization?$select=id,verifiedDomains')).value?.[0];
    if (organization?.id !== tenant) throw Error('Wrong customer tenant.');
    const api = await graph('GET', `/servicePrincipals/${apiSp}?$select=appId,appRoles,oauth2PermissionScopes`);
    const adminRole = api.appRoles?.find(r => r.value === 'Budlark.Admin' && r.isEnabled && r.allowedMemberTypes.includes('User'));
    const gardenScope = api.oauth2PermissionScopes?.find(s => s.value === 'Garden.ReadWrite' && s.isEnabled);
    if (!adminRole || !gardenScope) throw Error('Approved API role/scope unavailable.');
    const graphSp = (await graph('GET', `/servicePrincipals?$filter=appId eq '${graphAppId}'&$select=id,appRoles`)).value?.[0];
    const permissions = temporaryPermissions.map(value => graphSp?.appRoles?.find(r => r.value === value && r.isEnabled && r.allowedMemberTypes.includes('Application')));
    if (permissions.some(p => !p)) throw Error('Temporary Graph permissions unavailable.');
    evidence.stage = 'temporary-principal';
    temporaryApp = await graph('POST', '/applications', { displayName: 'budlark-provisioning-temp', signInAudience: 'AzureADMyOrg' });
    evidence.temporaryCreated = true;
    temporarySp = await graph('POST', '/servicePrincipals', { appId: temporaryApp.appId });
    for (const permission of permissions) {
      assignments.push(await graph('POST', `/servicePrincipals/${temporarySp.id}/appRoleAssignments`,
        { principalId: temporarySp.id, resourceId: graphSp.id, appRoleId: permission.id }));
    }
    const credential = await graph('POST', `/applications/${temporaryApp.id}/addPassword`, {
      passwordCredential: { displayName: 'one-run-only', endDateTime: new Date(clock().getTime() + 45 * 60000).toISOString() },
    });
    temporaryCredentialKey = credential.keyId;
    await authenticateTemporary(temporaryApp.appId, credential.secretText);
    credential.secretText = '';
    evidence.stage = 'mfa-and-provider-preflight';
    const defaults = await graph('GET', '/policies/identitySecurityDefaultsEnforcementPolicy', undefined, true);
    const policies = await graph('GET', '/identity/conditionalAccess/policies', undefined, true);
    const providers = await graph('GET', '/identity/identityProviders', undefined, true);
    evidence.securityDefaultsEnabled = defaults.isEnabled;
    evidence.conditionalAccessPolicyCount = policies.value?.length;
    evidence.passwordProviderAvailable = providers.value?.some(p => p.id === 'EmailPassword-OAUTH' && p.identityProviderType === 'EmailPassword') === true;
    const domain = provisioningPreflight({ organization, defaults, policies, providers });
    // Never update a production flow, conditional-access policy or security defaults.
    evidence.stage = 'test-client';
    const retiredDisplay = `${retiredPrefix[0].toUpperCase()}${retiredPrefix.slice(1)}`;
    const existing = await graph('GET', `/applications?$filter=displayName eq 'Budlark automation test client' or displayName eq '${retiredDisplay} automation test client'`);
    if (existing['@odata.nextLink'] || existing.value?.length > 1 ||
        existing.value?.[0] && !existing.value[0].tags?.some(tag =>
          ['budlark-automation-test', `${retiredPrefix}-automation-test`].includes(tag))) {
      throw Error('Existing test client ownership is unverified.');
    }
    const client = existing.value?.[0] ?? await graph('POST', '/applications', { displayName: 'Budlark automation test client',
      tags: ['budlark-automation-test'],
      signInAudience: 'AzureADMyOrg', isFallbackPublicClient: true,
      publicClient: { redirectUris: ['http://localhost:8400/automation-callback'] },
      requiredResourceAccess: [{ resourceAppId: api.appId, resourceAccess: [{ id: gardenScope.id, type: 'Scope' }] }],
    });
    if (client.publicClient?.redirectUris?.length !== 1 || client.publicClient.redirectUris[0] !== 'http://localhost:8400/automation-callback' ||
        client.signInAudience !== 'AzureADMyOrg') throw Error('Test client readback failed.');
    if (existing.value?.length) await graph('PATCH', `/applications/${client.id}`, {
      displayName: 'Budlark automation test client',
      tags: client.tags.map(tag => tag === `${retiredPrefix}-automation-test` ? 'budlark-automation-test' : tag),
    });
    const knownSp = await graph('GET', `/servicePrincipals?$filter=appId eq '${client.appId}'`);
    if (knownSp.value?.length > 1) throw Error('Ambiguous test service principal.');
    const clientSp = knownSp.value?.[0] ?? await graph('POST', '/servicePrincipals', { appId: client.appId, appRoleAssignmentRequired: true });
    if (!clientSp.appRoleAssignmentRequired) throw Error('Test client assignment restriction unavailable.');
    const grants = await graph('GET', `/oauth2PermissionGrants?$filter=clientId eq '${clientSp.id}'`);
    if (grants.value?.some(g => g.resourceId !== apiSp || g.scope !== 'Garden.ReadWrite' || g.consentType !== 'AllPrincipals')) throw Error('Unexpected test consent.');
    if (!grants.value?.length) await graph('POST', '/oauth2PermissionGrants', { clientId: clientSp.id, consentType: 'AllPrincipals', resourceId: apiSp, scope: 'Garden.ReadWrite' });
    evidence.clientId = client.appId;
    evidence.stage = 'isolated-password-flow';
    const flows = await graph('GET', '/identity/authenticationEventsFlows', undefined, true);
    const knownFlows = flows.value?.filter(f => ['budlark-test-email-password', `${retiredPrefix}-test-email-password`].includes(f.displayName)) ?? [];
    if (flows['@odata.nextLink'] || knownFlows.length > 1 || knownFlows[0] && knownFlows[0].description !== 'Dedicated automation accounts only; production providers unchanged.') throw Error('Test flow ownership unverified.');
    const flow = knownFlows[0] ?? await graph('POST', '/identity/authenticationEventsFlows', {
      '@odata.type': '#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow',
      displayName: 'budlark-test-email-password', description: 'Dedicated automation accounts only; production providers unchanged.',
      onInteractiveAuthFlowStart: { '@odata.type': '#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp', isSignUpAllowed: false },
      onAuthenticationMethodLoadStart: { '@odata.type': '#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp',
        identityProviders: [{ '@odata.type': '#microsoft.graph.builtInIdentityProvider', id: 'EmailPassword-OAUTH' }] },
    }, true);
    const apps = flow.conditions?.applications?.includeApplications ?? [];
    if (apps.some(a => a.appId !== client.appId)) throw Error('Test flow includes a non-test application.');
    if (knownFlows.length && flow.displayName !== 'budlark-test-email-password') {
      await graph('PATCH', `/identity/authenticationEventsFlows/${flow.id}`, {
        '@odata.type': '#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow',
        displayName: 'budlark-test-email-password',
      }, true);
    }
    if (!apps.length) await graph('POST', `/identity/authenticationEventsFlows/${flow.id}/conditions/applications/includeApplications`,
      { '@odata.type': '#microsoft.graph.authenticationConditionApplication', appId: client.appId }, true);
    const actual = await graph('GET', `/identity/authenticationEventsFlows/${flow.id}`, undefined, true);
    const included = actual.conditions?.applications?.includeApplications;
    const flowProviders = actual.onAuthenticationMethodLoadStart?.identityProviders;
    if (included?.length !== 1 || included[0].appId !== client.appId || flowProviders?.length !== 1 || flowProviders[0].id !== 'EmailPassword-OAUTH') {
      throw Error('Isolated flow readback failed.');
    }
    evidence.flowId = flow.id;
    evidence.stage = 'test-users';
    const knownGroups = await graph('GET', `/groups?$filter=displayName eq 'budlark-automation-test-users' or displayName eq '${retiredPrefix}-automation-test-users'`);
    if (knownGroups['@odata.nextLink'] || knownGroups.value?.length > 1 || knownGroups.value?.[0] &&
        !['Dedicated Budlark automation identities only; no customer policy modifications.',
          `Dedicated ${retiredDisplay} automation identities only; no customer policy modifications.`].includes(knownGroups.value[0].description)) throw Error('Test group ownership unverified.');
    const group = knownGroups.value?.[0] ?? await graph('POST', '/groups', { displayName: 'budlark-automation-test-users',
      description: 'Dedicated Budlark automation identities only; no customer policy modifications.',
      mailEnabled: false, mailNickname: 'budlark-automation-test-users', securityEnabled: true });
    if (knownGroups.value?.length) await graph('PATCH', `/groups/${group.id}`, {
      displayName: 'budlark-automation-test-users', mailNickname: 'budlark-automation-test-users',
      description: 'Dedicated Budlark automation identities only; no customer policy modifications.',
    });
    for (const label of ['a', 'b', 'admin']) {
      let password = `Aa7!${randomBytes(32).toString('base64url')}`;
      const profile = { password, forceChangePasswordNextSignIn: false };
      const { user, email } = await automationUser(graph, { label, domain, passwordProfile: profile });
      const members = await graph('GET', `/groups/${group.id}/members?$select=id`);
      if (!members.value?.some(m => m.id === user.id)) await graph('POST', `/groups/${group.id}/members/$ref`, { '@odata.id': `https://graph.microsoft.com/v1.0/directoryObjects/${user.id}` });
      const userRoles = await graph('GET', `/users/${user.id}/appRoleAssignments`);
      if (label !== 'admin' && userRoles.value?.some(r => r.resourceId === apiSp)) throw Error('Ordinary test user has unexpected API roles.');
      if (!userRoles.value?.some(r => r.resourceId === clientSp.id)) await graph('POST', `/users/${user.id}/appRoleAssignments`, { principalId: user.id, resourceId: clientSp.id,
        appRoleId: '00000000-0000-0000-0000-000000000000' });
      if (label === 'admin' && !userRoles.value?.some(r => r.resourceId === apiSp && r.appRoleId === adminRole.id)) await graph('POST', `/users/${user.id}/appRoleAssignments`,
        { principalId: user.id, resourceId: apiSp, appRoleId: adminRole.id });
      evidence.stage = `hosted-sign-in-${label}`;
      await verifySignIn({ label: label.toUpperCase(), email, password }, client.appId);
      await secret(`BUDLARK_TEST_${label.toUpperCase()}_EMAIL`, email);
      await secret(`BUDLARK_TEST_${label.toUpperCase()}_PASSWORD`, password);
      password = '';
      profile.password = '';
      evidence.users++;
      evidence.stage = 'test-users';
    }
    await variable('BUDLARK_AUTOMATION_CLIENT_ID', client.appId);
    evidence.passed = true;
    evidence.stage = 'complete';
  } catch (error) {
    failure = error;
    evidence.passed = false;
  } finally {
    const clean = async (path) => { try { await graph('DELETE', path); } catch { evidence.temporaryCleanupFailed = true; } };
    if (temporaryApp && temporaryCredentialKey) {
      try { await graph('POST', `/applications/${temporaryApp.id}/removePassword`, { keyId: temporaryCredentialKey }); }
      catch { evidence.temporaryCleanupFailed = true; }
    }
    if (temporarySp) {
      for (const assignment of assignments) await clean(`/servicePrincipals/${temporarySp.id}/appRoleAssignments/${assignment.id}`);
      await clean(`/servicePrincipals/${temporarySp.id}`);
    }
    if (temporaryApp) {
      await clean(`/applications/${temporaryApp.id}`);
      try {
        const remains = await graph('GET', `/applications?$filter=appId eq '${temporaryApp.appId}'&$select=id`);
        evidence.temporaryDeleted = remains.value?.length === 0 && !evidence.temporaryCleanupFailed;
      } catch { evidence.temporaryDeleted = false; }
    }
    if (temporaryApp && !evidence.temporaryDeleted) evidence.passed = false;
  }
  if (failure) evidence.error = /^(Graph request|Hosted sign-in (?:blocked|failed):)/.test(failure.message) ? failure.message : 'Provisioning failed closed; inspect the reported stage.';
  return evidence;
}

async function main() {
  let delegated = process.env.BUDLARK_PROVISIONING_TOKEN, temporary, browser;
  delete process.env.BUDLARK_PROVISIONING_TOKEN;
  const evidencePath = process.argv[2];
  if (!delegated || !evidencePath) throw Error('Cached tenant token and evidence path required.');
  const graph = async (method, path, body, useTemporary = false) => {
    const response = await fetch(`https://graph.microsoft.com/v1.0${path}`, { method, redirect: 'error',
      headers: { Authorization: `Bearer ${useTemporary ? temporary : delegated}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    if (!response.ok) throw Error(`Graph request failed (HTTP ${response.status}).`);
    return response.status === 204 ? undefined : response.json();
  };
  const cli = (args, input) => {
    const result = spawnSync('gh', args, { input, stdio: ['pipe', 'ignore', 'pipe'], encoding: 'utf8', windowsHide: true });
    if (result.status !== 0) throw Error('GitHub setting failed; credentials omitted.');
  };
  let evidence;
  try {
    const { signIn, createAutomationBrowser } = await import('../site/production-isolation.mjs');
    evidence = await provisionAutomation({ graph,
      authenticateTemporary: async (clientId, clientSecret) => {
        for (let attempt = 0; attempt < 4; attempt++) {
          const response = await fetch(`https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`, {
            method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, grant_type: 'client_credentials', scope: 'https://graph.microsoft.com/.default' }),
          });
          const data = await response.json();
          if (response.ok && data.access_token) { temporary = data.access_token; return; }
          const codes = Array.isArray(data.error_codes) ? data.error_codes.filter(Number.isInteger) : [];
          if (attempt === 3 || !codes.some(code => [700016, 7000215].includes(code))) {
            throw Error(`Graph request token failed (HTTP ${response.status}; codes ${codes.join(',')}).`);
          }
          await new Promise(resolve => setTimeout(resolve, 10000));
        }
      },
      verifySignIn: async (account, clientId) => {
        browser ??= await createAutomationBrowser();
        let token = await signIn(browser, account, clientId);
        const response = await fetch('https://brave-plant-02c10e800.5.azurestaticapps.net/api/sync', {
          redirect: 'error', headers: { 'X-Budlark-Authorization': `Bearer ${token}` },
        });
        token = null;
        if (response.status !== 200) throw Error('Hosted token was not accepted by the production own-data endpoint.');
      },
      secret: async (name, value) => cli(['secret', 'set', name, '-R', 'Sampath-K/budlark'], value),
      variable: async (name, value) => cli(['variable', 'set', name, '-R', 'Sampath-K/budlark'], value),
    });
  } finally { delegated = null; temporary = null; await browser?.close(); }
  evidence.timestamp = new Date().toISOString();
  if (evidence.passed) cli(['variable', 'set', 'BUDLARK_AUTOMATION_PROVISIONING_RECEIPT', '-R', 'Sampath-K/budlark'], JSON.stringify(evidence));
  await writeFile(evidencePath, JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence));
  process.exitCode = evidence.passed ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await main(); } catch { console.error('Provisioning could not start; no credentials displayed.'); process.exitCode = 1; }
}
