const storageKey = 'bloomstep.pending-invitation.v1';
const channels = new Set(['link', 'email', 'qr', 'native']);

function validCode(code) {
  if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(code)) return false;
  const decoded = atob(code.replaceAll('-', '+').replaceAll('_', '/') + '=');
  return decoded.length === 32 &&
    btoa(decoded).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '') === code;
}

export function parseInvitation(search) {
  const query = new URLSearchParams(search);
  if (!query.has('invite')) return null;
  if ([...query.keys()].some(key => !['invite', 'channel'].includes(key)) ||
      query.getAll('invite').length !== 1 || query.getAll('channel').length > 1) {
    throw new Error('This invitation contains unsupported parameters.');
  }
  const channel = query.get('channel') ?? 'link';
  if (!channels.has(channel)) throw new Error('This invitation channel is invalid.');
  if (query.get('invite') === 'garden') return { generic: true };
  const code = query.get('invite');
  if (!validCode(code)) throw new Error('This invitation code is invalid.');
  return { code, channel };
}

export function nativeInvitationUrl(intent) {
  if (!intent || !validCode(intent.code) || !channels.has(intent.channel)) {
    throw new Error('No valid invitation is ready to open.');
  }
  return 'bloomstep://invite?' + new URLSearchParams({ code: intent.code, channel: intent.channel });
}

export function rememberInvitation(storage, intent, now = Date.now()) {
  nativeInvitationUrl(intent);
  storage.setItem(storageKey, JSON.stringify({ version: 1, code: intent.code, channel: intent.channel, savedAt: now }));
}

export function savedInvitation(storage, now = Date.now()) {
  const raw = storage.getItem(storageKey);
  if (raw === null) return null;
  try {
    const value = JSON.parse(raw);
    if (!value || Object.keys(value).length !== 4 || value.version !== 1 ||
        !Number.isFinite(value.savedAt) || now - value.savedAt >= 7 * 86400000 ||
        now - value.savedAt < -300000) throw new Error('The remembered invitation expired or is damaged.');
    nativeInvitationUrl(value);
    return { code: value.code, channel: value.channel };
  } catch (error) {
    storage.removeItem(storageKey);
    throw error;
  }
}

export function initializeInvitationLanding() {
  const notice = document.getElementById('invitation');
  try {
    const intent = parseInvitation(location.search) ?? savedInvitation(localStorage);
    if (!intent) return;
    notice.hidden = false;
    notice.replaceChildren();
    const explanation = document.createElement('p');
    explanation.textContent = intent.generic
      ? 'You were invited to grow a tiny habit. This generic link shares no personal garden data and does not claim referral credit.'
      : 'Your invitation is ready. It contains no private garden data. Bloomstep validates it after you sign in; accepting credits the inviter. Both gardens may earn a cosmetic flower after the invited friend practices.';
    notice.append(explanation);
    const download = document.createElement('a'); download.href = '#download';
    download.textContent = 'Install the unsigned Windows preview'; notice.append(download);
    if (intent.generic) return;
    const open = document.createElement('a'); open.href = nativeInvitationUrl(intent);
    open.className = 'button'; open.textContent = 'Open invitation in Bloomstep';
    const steps = document.createElement('p');
    steps.textContent = 'If Bloomstep is not installed, install first and return to this page to open your invitation. The code stays with this link across installation and sign-in. No app is opened without your click.';
    const label = document.createElement('label');
    const remember = document.createElement('input'); remember.type = 'checkbox';
    remember.style.width = 'auto'; remember.style.display = 'inline';
    label.append(remember, ' Remember this invitation for up to seven days on this browser (optional functional storage)');
    const status = document.createElement('p'); status.setAttribute('role', 'status');
    remember.addEventListener('change', () => {
      try {
        if (remember.checked) rememberInvitation(localStorage, intent);
        else localStorage.removeItem(storageKey);
        status.textContent = remember.checked ? 'Invitation remembered on this browser only.' : 'Remembered invitation removed.';
      } catch {
        remember.checked = false;
        status.textContent = 'This browser could not save the invitation. Keep the original link; it still works.';
      }
    });
    notice.append(steps, open, label, status);
  } catch (error) {
    notice.hidden = false;
    notice.textContent = `${error.message} No referral was accepted or private data fetched. Use the original link again.`;
  }
}
