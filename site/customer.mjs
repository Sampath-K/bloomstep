import { parseInvitation, nativeInvitationUrl } from './invitation-landing.mjs';
import { validateReceipt } from './measurement.mjs';

const campaignFields = ['utm_source', 'utm_medium', 'utm_campaign'];
const campaignValue = /^[a-zA-Z0-9_-]{1,48}$/;
/** Categories only; no referrer hostname or URL leaves this function. */
export function classifySource(referrer, search, origin) {
  const query = new URLSearchParams(search);
  const fields = [...query.keys()].filter(key => key.startsWith('utm_'));
  if (fields.length) {
    return fields.every(key => campaignFields.includes(key) && query.getAll(key).length === 1 &&
      campaignValue.test(query.get(key))) ? 'campaign' : 'unknown';
  }
  if (!referrer) return 'direct';
  let url;
  try { url = new URL(referrer); } catch { return 'unknown'; }
  if (!['https:', 'http:'].includes(url.protocol) || url.origin === origin) return 'unknown';
  const searchHosts = ['google.com', 'google.co.uk', 'google.co.in', 'bing.com', 'duckduckgo.com',
    'search.yahoo.com', 'search.brave.com', 'ecosia.org'];
  return searchHosts.some(host => url.hostname === host || url.hostname.endsWith('.' + host)) ? 'search' : 'referral';
}
export function architectureHint(architecture, bitness) {
  if (Number(bitness) !== 64) return 'unknown';
  return architecture === 'arm' ? 'arm64' : architecture === 'x86' ? 'x64' : 'unknown';
}
export function createWebObserver({ send, dnt, gpc, source = 'unknown', uuid = () => crypto.randomUUID() }) {
  const seen = new Set();
  return {
    async record(event, architecture = 'unknown') {
      if (dnt === '1' || gpc || seen.has(`${event}:${architecture}`)) return false;
      seen.add(`${event}:${architecture}`);
      try {
        await send({ channel: 'web', event, source, architecture, eventId: uuid(), synthetic: false });
        return true;
      } catch {
        return false;
      }
    },
  };
}

function initializeCustomer() {
  const status = document.getElementById('website-status');
  const consent = document.getElementById('website-consent');
  const blocked = () => navigator.doNotTrack === '1' || window.doNotTrack === '1' || navigator.globalPrivacyControl === true;
  const observer = createWebObserver({
    source: classifySource(document.referrer, location.search, location.origin),
    send: async payload => {
      if (blocked()) { status.textContent = 'Privacy signal honoured: no website observations are sent.'; return; }
      const response = await fetch('/api/web/events', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload), credentials: 'omit', referrerPolicy: 'no-referrer',
        signal: AbortSignal.timeout(4000), keepalive: true,
      });
      if (!response.ok) throw Error('Website measurement unavailable.');
    },
    dnt: navigator.doNotTrack ?? window.doNotTrack, gpc: navigator.globalPrivacyControl,
  });
  const record = (event, arch) => {
    if (blocked()) { status.textContent = 'Privacy signal honoured: no website observations are sent.'; return; }
    if (!consent.checked) return;
    void observer.record(event, arch).then(accepted => {
      if (!accepted) status.textContent = 'Website measurement is unavailable or this observation was already counted. Downloads still work.';
    });
  };
  if (blocked()) { consent.disabled = true; status.textContent = 'Privacy signal honoured: no website observations are sent.'; }
  consent.addEventListener('change', () => {
    if (blocked()) { consent.checked = false; status.textContent = 'Privacy signal honoured: no website observations are sent.'; return; }
    status.textContent = consent.checked ? 'Optional daily website counts active for this visit only.' : 'Website measurement is off. Earlier anonymous counts cannot be individually identified.';
    if (consent.checked) record('landing_view');
  });
  document.getElementById('primary-cta').addEventListener('click', () => record('primary_cta_click'));
  for (const link of document.querySelectorAll('[data-download]')) {
    link.addEventListener('click', () => record('download_click', link.dataset.download));
  }
  // Coarse CPU guidance is used for display only, never sent as a visitor attribute.
  if (!document.querySelector('[data-universal-download]') && navigator.userAgentData?.getHighEntropyValues) {
    navigator.userAgentData.getHighEntropyValues(['architecture', 'bitness']).then(value => {
      const arch = architectureHint(value.architecture, value.bitness);
      if (arch === 'unknown') return;
      document.getElementById('architecture-guidance').textContent =
        `Your browser suggests ${arch === 'arm64' ? 'ARM64' : 'x64'} for this device. If that does not match your Windows System type, choose the other download below.`;
      const choices = document.querySelector('.choices');
      choices.prepend(document.querySelector(`[data-download="${arch}"]`));
      document.querySelector(`[data-download="${arch}"]`).textContent += ' (suggested)';
    }).catch(() => {
      document.getElementById('architecture-guidance').textContent += ' Automatic guidance is unavailable; both choices still work.';
    });
  }
  initializeReceipt(blocked);
  const notice = document.getElementById('invitation');
  try {
    const invitation = parseInvitation(location.search);
    if (!invitation) return;
    notice.hidden = false;
    const explanation = document.createElement('p');
    explanation.textContent = invitation.generic ? 'You were invited to grow a tiny habit. No personal garden data is shared.' :
      'Your invitation is ready. Install Bloomstep, then return to this link. Open it when you are ready; Bloomstep validates it after sign-in.';
    notice.append(explanation);
    if (!invitation.generic) {
      const open = document.createElement('a'); open.href = nativeInvitationUrl(invitation);
      open.textContent = 'Open invitation in Bloomstep'; notice.append(open);
    }
  } catch (error) {
    notice.hidden = false; notice.textContent = `${error.message} No invitation was accepted. Use the original link.`;
  }
}

function initializeReceipt(blocked) {
  const consent = document.getElementById('receipt-consent'), button = document.getElementById('receipt-export');
  const status = document.getElementById('receipt-status');
  let receipt = null;
  const clear = () => {
    receipt = null; consent.checked = false; button.disabled = true; status.textContent = 'Receipt collection is off; page memory cleared.';
  };
  consent.addEventListener('change', () => {
    if (!consent.checked) { clear(); return; }
    if (blocked()) { clear(); status.textContent = 'Your privacy signal disables receipt collection too.'; return; }
    const at = new Date().toISOString();
    receipt = { schemaVersion: 1, source: 'website', consentedAt: at,
      events: [{ id: crypto.randomUUID(), name: 'landing_view', ts: at }] };
    button.disabled = false; status.textContent = 'Receipt stays only in page memory. Nothing is linked to your account.';
  });
  for (const link of document.querySelectorAll('[data-download]')) {
    link.addEventListener('click', () => {
      if (blocked()) { clear(); return; }
      if (!receipt) return;
      if (receipt.events.length >= 32) { status.textContent = 'Receipt limit reached; export or clear it. Download is unaffected.'; return; }
      receipt.events.push({ id: crypto.randomUUID(), name: 'download_click', ts: new Date().toISOString() });
    });
  }
  button.addEventListener('click', () => {
    if (blocked()) { clear(); return; }
    try {
      const raw = JSON.stringify(receipt);
      validateReceipt(raw);
      const url = URL.createObjectURL(new Blob([raw], { type: 'application/json' }));
      const link = document.createElement('a'); link.href = url; link.download = 'bloomstep-website-measurement.json'; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = 'Receipt export requested. Linking it in app Settings is a separate choice.';
    } catch (error) { status.textContent = error.message; }
  });
  document.getElementById('receipt-clear').addEventListener('click', clear);
  window.addEventListener('pagehide', clear);
}

if (typeof document !== 'undefined' && document.getElementById('primary-cta')) initializeCustomer();
