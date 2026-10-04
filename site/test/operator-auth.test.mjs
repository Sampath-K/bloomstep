import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createOperatorAuth, validatePublicConfig, operatorRequest } from '../operator-auth.mjs';
const config = { clientId:'11111111-1111-4111-8111-111111111111', issuer:'https://example.ciamlogin.com/22222222-2222-4222-8222-222222222222/v2.0', scope:'api://33333333-3333-4333-8333-333333333333/Garden.ReadWrite' };
const fixture = (failure = false) => {
  const calls = [];
  const account = { homeAccountId:'customer' };
  const client = {
    initialize: async () => {},
    loginPopup: async options => { calls.push(options); if(failure) throw Error('private-provider-error'); return {account}; },
    acquireTokenSilent: async options => { calls.push(options); return {account,accessToken:'signed.token.value'}; },
    clearCache: async () => { calls.push('clear'); },
  };
  return { calls, auth:createOperatorAuth(client,config,'https://test.azurestaticapps.net') };
};
test('public config pins HTTPS customer broker, narrow scope and callback', () => {
  assert.equal(validatePublicConfig(config,'https://test.azurestaticapps.net').redirectUri,'https://test.azurestaticapps.net/operator-callback.html');
  for(const changes of [{issuer:'https://login.microsoftonline.com/common/v2.0'},{scope:'User.Read'},{clientId:'secret'}]) assert.throws(()=>validatePublicConfig({...config,...changes},'https://test.azurestaticapps.net'));
});
test('real popup initiation and memory state supply only custom bearer, clear invalidates requests',async()=>{
  const {auth,calls}=fixture();
  await assert.rejects(auth.token(),/Sign in/);
  await auth.signIn();
  assert.equal(await auth.token(),'signed.token.value');
  assert.equal(calls[0].redirectUri,'https://test.azurestaticapps.net/operator-callback.html');
  await auth.clear();
  await assert.rejects(auth.token(),/Sign in/);
  assert.ok(calls.includes('clear'));
});
test('failed signin is explicit and does not expose provider text or leave authenticated state',async()=>{
  const {auth}=fixture(true);
  await assert.rejects(auth.signIn(),/Operator sign-in failed/);
  await assert.rejects(auth.token(),/Sign in/);
});
test('late popup completion after pagehide cannot restore a session',async()=>{
  let resolve;
  const client={initialize:async()=>{},clearCache:async()=>{},loginPopup:()=>new Promise(r=>resolve=r)};
  const auth=createOperatorAuth(client,config,'https://test.azurestaticapps.net');
  const pending=auth.signIn();
  await new Promise(r=>setImmediate(r));
  await auth.clear();
  resolve({account:{}});
  await assert.rejects(pending,/cleared/);
});
test('same-origin custom-header transport leaves server role authoritative and surfaces401/403',async()=>{
  const auth={token:async()=>'actual.broker.token'};
  let captured;
  const fetcher=async(url,options)=>{captured={url,options};return {ok:true,json:async()=>({feedback:[]})};};
  await operatorRequest(auth,'https://test.azurestaticapps.net','/api/team/feedback',{},fetcher);
  assert.equal(captured.options.headers['X-Bloomstep-Authorization'],'Bearer actual.broker.token');
  assert.equal(captured.options.headers.Authorization,undefined);
  assert.equal(captured.options.redirect,'error');
  for(const status of [401,403]) await assert.rejects(operatorRequest(auth,'https://test.azurestaticapps.net','/api/team/metrics',{},async()=>({ok:false,status,json:async()=>({error:'private'})})),new RegExp(`HTTP ${status}`));
  await assert.rejects(operatorRequest(auth,'https://test.azurestaticapps.net','https://untrusted.invalid/api/team/feedback',{},fetcher));
});
test('browser credentials use memory cache only, no manual bearer field/CDN fallback',()=>{
  const authSource=readFileSync(new URL('../operator-auth.mjs',import.meta.url),'utf8');
  assert.match(authSource,/cacheLocation:BrowserCacheLocation.MemoryStorage/);
  assert.match(authSource,/temporaryCacheLocation:BrowserCacheLocation.SessionStorage/);
  assert.doesNotMatch(authSource,/localStorage|clientSecret|clipboard/);
  const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
  assert.doesNotMatch(html,/id="token"|src="https:/);
  assert.match(html,/assets\/console.js/);
});
test('platform HTML authentication failures remain explicit, never parsed as private JSON',async()=>{
  await assert.rejects(operatorRequest({token:async()=> 'fixture-token'},'https://example.azurestaticapps.net','/api/team/metrics',{},async()=>({
    ok:false,status:401,json(){throw Error('Unexpected platform HTML');},
  })),/HTTP 401/);
});
