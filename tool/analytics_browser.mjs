export function initializeSandbox(config, win = window, doc = document) {
  const consent = doc.getElementById('sandbox-consent');
  const status = doc.getElementById('sandbox-status');
  const blocked = () => win.navigator.doNotTrack === '1' || win.navigator.globalPrivacyControl === true;
  let started = false;
  const seen = new Set();
  const incoming = new URLSearchParams(win.location.search);
  const campaign = {};
  const campaignChoices = {
    utm_source: ['sandbox', 'newsletter', 'linkedin', 'community', 'search', 'referral'],
    utm_medium: ['test', 'organic', 'email', 'social', 'referral'],
    utm_campaign: ['prelaunch', 'tiny-habits'],
  };
  for (const [key, choices] of Object.entries(campaignChoices)) {
    const value = incoming.get(key);
    campaign[key] = incoming.getAll(key).length === 1 && choices.includes(value) ? value : choices[0];
  }
  const pagePath = win.location.pathname === '/releases/' ? '/releases/' : '/';
  const pageProperties = { page_location: win.location.origin + pagePath,
    page_referrer: '', page_title: 'Bloomstep sandbox', ...campaign };
  const productProperties = { $current_url: win.location.origin + pagePath,
    $referrer: '', ...campaign };
  function record(name, architecture) {
    if (!started || !consent.checked || blocked()) return;
    const id = `${name}:${architecture || ''}`;
    if (seen.has(id)) return;
    seen.add(id);
    const properties = architecture ? { architecture } : {};
    if (config.GA4_ID) win.gtag?.('event', name, { ...pageProperties, ...properties });
    if (config.POSTHOG_KEY) win.posthog?.capture(name, { ...productProperties, ...properties });
  }
  function script(src, attributes = {}) {
    const node = doc.createElement('script');
    node.src = src; node.async = true; node.referrerPolicy = 'no-referrer';
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    node.onerror = () => { status.textContent = 'A sandbox vendor failed to load. Downloads still work.'; };
    doc.head.append(node);
  }
  const host = config.POSTHOG_REGION === 'US' ? 'https://us.i.posthog.com' : 'https://eu.i.posthog.com';
  const tagLinks = () => {
    for (const link of doc.querySelectorAll('[data-download], #primary-cta, #download-footer-cta .button')) {
      const url = new URL(link.href, win.location.href);
      // Discard unknown query data before replay SDKs can inspect link targets.
      url.search = '';
      for (const [key, value] of Object.entries(campaign)) url.searchParams.set(key, value);
      link.href = url.href;
    }
  };
  tagLinks();
  consent.addEventListener('change', () => {
    if (!consent.checked && started) {
      started = false;
      if (config.GA4_ID) {
        // Disable transport before consent updates or pagehide can flush engagement.
        win[`ga-disable-${config.GA4_ID}`] = true;
        win.gtag?.('consent', 'update', { analytics_storage: 'denied', ad_storage: 'denied',
          ad_user_data: 'denied', ad_personalization: 'denied' });
      }
      // Destroy the browsing context to stop SDK timers, workers and queued events.
      win.location.reload();
      return;
    }
    if (!consent.checked || started) return;
    if (blocked()) {
      consent.checked = false; status.textContent = 'Privacy signal honoured; sandbox analytics disabled.'; return;
    }
    started = true;
    const enabled = ['GA4_ID', 'CLARITY_ID', 'CLOUDFLARE_TOKEN', 'POSTHOG_KEY'].filter(key => config[key]);
    status.textContent = enabled.length ? 'Sandbox analytics active for this visit. Uncheck to reload and stop.' : 'No vendor keys configured; nothing loaded.';
    if (enabled.length) win.history.replaceState(null, '', win.location.pathname);
    // Never pass query strings, invitation tokens, referrers or page text to event APIs.
    if (config.GA4_ID) {
      win.dataLayer = [];
      win.gtag = function () { win.dataLayer.push(arguments); };
      win.gtag('consent', 'default', { analytics_storage: 'granted', ad_storage: 'denied',
        ad_user_data: 'denied', ad_personalization: 'denied' });
      win.gtag('js', new Date());
      win.gtag('config', config.GA4_ID, { send_page_view: false, allow_google_signals: false,
        allow_ad_personalization_signals: false, ...pageProperties });
      win.gtag('event', 'page_view', pageProperties);
      script(`https://www.googletagmanager.com/gtag/js?id=${config.GA4_ID}`);
    }
    if (config.CLARITY_ID) {
      win.clarity = function () { (win.clarity.q ||= []).push(arguments); };
      win.clarity('consentv2', { ad_Storage: 'denied', analytics_Storage: 'granted' });
      script(`https://www.clarity.ms/tag/${config.CLARITY_ID}`);
    }
    if (config.CLOUDFLARE_TOKEN) script('https://static.cloudflareinsights.com/beacon.min.js',
      { 'data-cf-beacon': JSON.stringify({ token: config.CLOUDFLARE_TOKEN, spa: false }) });
    if (config.POSTHOG_KEY) {
      const queue = [];
      win.posthog = queue;
      queue.__SV = 1;
      for (const method of ['capture', 'init']) queue[method] = (...args) => queue.push([method, ...args]);
      queue._i = [[config.POSTHOG_KEY, {
        api_host: host, autocapture: false, capture_pageview: false, capture_pageleave: false,
        disable_session_recording: true, persistence: 'memory', person_profiles: 'never',
        advanced_disable_feature_flags: true,
      }, 'posthog']];
      queue.capture('sandbox_page_view', productProperties);
      script(`${host}/static/array.js`);
    }
  });
  for (const link of doc.querySelectorAll('#primary-cta, #download-footer-cta .button')) {
    link.addEventListener('click', () => record('sandbox_primary_cta_click'));
  }
  for (const link of doc.querySelectorAll('[data-download]')) link.addEventListener('click', () => {
    const architecture = ['x64', 'arm64'].includes(link.dataset.download) ? link.dataset.download : 'unknown';
    record('sandbox_download_click', architecture);
  });
}
