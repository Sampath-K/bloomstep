export function validatePublicConfig(config, origin) {
  if (!config || !/^[\da-f-]{36}$/i.test(config.clientId ?? '')) throw Error('Operator identity is not configured.');
  const broker = new URL(config.issuer);
  const site = new URL(origin);
  if (broker.protocol !== 'https:' || !broker.hostname.endsWith('.ciamlogin.com') ||
      !/^\/[\da-f-]{36}\/v2\.0\/?$/i.test(broker.pathname) || broker.search || broker.hash || broker.username || broker.password ||
      !/^api:\/\/[\da-f-]{36}\/Garden\.ReadWrite$/i.test(config.scope ?? '') ||
      site.protocol !== 'https:' || site.origin !== origin) throw Error('Operator identity configuration is invalid.');
  return { ...config, authority: config.issuer.replace(/\/v2\.0\/?$/, ''), redirectUri: origin + '/operator-callback.html', knownAuthorities:[broker.hostname] };
}

export function createOperatorAuth(client, rawConfig, origin, initialized = false) {
  const config=validatePublicConfig(rawConfig,origin);
  let account=null;
  let generation=0;
  const ready=initialized ? Promise.resolve() : client.initialize();
  return {
    async signIn() {
      const current=++generation;
      account=null;
      await ready;
      let result;
      try { result=await client.loginPopup({scopes:[config.scope],redirectUri:config.redirectUri,prompt:'select_account'}); }
      catch { throw Error('Operator sign-in failed or was cancelled. No private data loaded.'); }
      if(current!==generation) throw Error('Operator session was cleared.');
      if(!result.account) throw Error('Operator sign-in did not return an account.');
      account=result.account;
    },
    async token() {
      if(!account) throw Error('Sign in to the operator console first.');
      const current=generation;
      try {
        const result=await client.acquireTokenSilent({account,scopes:[config.scope],redirectUri:config.redirectUri});
        if(current!==generation || !account) throw Error('cleared');
        if(!result.accessToken) throw Error('missing');
        return result.accessToken;
      } catch { throw Error('Operator session needs sign-in again. No token fallback is available.'); }
    },
    async clear() {
      ++generation; account=null;
      await ready.catch(()=>{});
      await client.clearCache().catch(()=>{});
    },
  };
}

export async function operatorRequest(auth, origin, path, options = {}, fetcher = fetch) {
  if(new URL(origin).protocol!=='https:' || !/^\/api\/team\/(?:metrics|feedback|website|operational-status|operational-resume)(?:[/?]|$)/.test(path) || path.includes('\\') || path.includes('..')) throw Error('Invalid same-origin operator route.');
  const token=await auth.token();
  const response=await fetcher(origin+path,{
    ...options,credentials:'same-origin',redirect:'error',cache:'no-store',
    headers:{'X-Bloomstep-Authorization':`Bearer ${token}`,'Content-Type':'application/json'},
  });
  if(!response.ok) {
    if(response.status===401) throw Error('API rejected authentication (HTTP 401). Sign in again.');
    if(response.status===403) throw Error('API denied access (HTTP 403). Explicit customer Bloomstep.Admin assignment is required.');
    throw Error(`API request failed (HTTP ${response.status}). Private response details omitted.`);
  }
  return response.json();
}

export async function loadOperatorAuth(origin) {
  const response=await fetch('/operator-config.json',{cache:'no-store',credentials:'same-origin'});
  if(!response.ok) throw Error('Operator identity is not configured.');
  const config=validatePublicConfig(await response.json(),origin);
  const {PublicClientApplication,BrowserCacheLocation}=await import('@azure/msal-browser');
  const client=new PublicClientApplication({
    auth:{clientId:config.clientId,authority:config.authority,knownAuthorities:config.knownAuthorities,redirectUri:config.redirectUri},
    cache:{cacheLocation:BrowserCacheLocation.MemoryStorage,temporaryCacheLocation:BrowserCacheLocation.SessionStorage,storeAuthStateInCookie:false},
    system:{loggerOptions:{loggerCallback:()=>{},piiLoggingEnabled:false}},
  });
  await client.initialize();
  const auth=createOperatorAuth(client,config,origin,true);
  const clear=auth.clear;
  auth.clear=async()=>{
    const clearing=clear();
    for(const key of Object.keys(sessionStorage)) {
      if(key.startsWith('msal.')) sessionStorage.removeItem(key);
    }
    await clearing;
  };
  return auth;
}
