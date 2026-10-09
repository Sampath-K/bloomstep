export function initializeSandbox(config, win = window, doc = document) {
  const consent = doc.getElementById('sandbox-consent');
  const status = doc.getElementById('sandbox-status');
  const blocked = () => win.navigator.doNotTrack === '1' || win.navigator.globalPrivacyControl === true;
  let started = false;
  function script(src, attributes = {}) {
    const node = doc.createElement('script');
    node.src = src; node.async = true; node.referrerPolicy = 'no-referrer';
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    node.onerror = () => { status.textContent = 'A sandbox vendor failed to load. Downloads still work.'; };
    doc.head.append(node);
  }
  const host = config.POSTHOG_REGION === 'US' ? 'https://us.i.posthog.com' : 'https://eu.i.posthog.com';
  const tagLinks = () => {
    const incoming = new URLSearchParams(win.location.search);
    for (const link of doc.querySelectorAll('[data-download], #primary-cta, #download-footer-cta .button')) {
      const url = new URL(link.href, win.location.href);
      for (const key of ['utm_source', 'utm_medium', 'utm_campaign']) {
        const value = incoming.get(key);
        url.searchParams.set(key, /^[a-zA-Z0-9_-]{1,48}$/.test(value ?? '') ? value :
          ({ utm_source: 'sandbox', utm_medium: 'test', utm_campaign: 'prelaunch' })[key]);
      }
      link.href = url.href;
    }
  };
  tagLinks();
  consent.addEventListener('change', () => {
    if (!consent.checked && started) {
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
        allow_ad_personalization_signals: false });
      win.gtag('event', 'page_view', { page_location: win.location.origin + '/', page_referrer: '', page_title: 'Bloomstep sandbox' });
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
      queue.capture('sandbox_page_view', { $current_url: win.location.origin + '/', $referrer: '' });
      script(`${host}/static/array.js`);
    }
  });
  for (const link of doc.querySelectorAll('[data-download]')) link.addEventListener('click', () => {
    if (!consent.checked || blocked()) return;
    win.gtag?.('event', 'sandbox_download_click', { page_location: win.location.origin + '/', page_referrer: '' });
    win.posthog?.capture('sandbox_download_click', { $current_url: win.location.origin + '/', $referrer: '' });
  });
}
