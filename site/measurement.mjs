import { parseInvitation } from './invitation-landing.mjs';

export const measurementKey = 'bloomstep.measurement-receipt.v1';
const lifetime = 7 * 86400000;
const names = {
  website: new Set(['landing_view', 'invite_link_open', 'download_click']),
  installer: new Set(['installer_started', 'install_completed', 'first_launch', 'signin_view']),
};
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
class ExpiredReceipt extends Error {}
const invalid = () => Error('Invalid or unsupported measurement receipt. No data was imported.');
const keys = (value, allowed) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).length === allowed.length && Object.keys(value).every(k => allowed.includes(k));
function timestamp(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) throw invalid();
  const at = Date.parse(value);
  if (!Number.isFinite(at) || new Date(at).toISOString().slice(0, 19) !== value.slice(0, 19)) throw invalid();
  return at;
}

export function validateReceipt(text, now = Date.now()) {
  if (typeof text !== 'string' || new TextEncoder().encode(text).length > 16384) throw invalid();
  let value;
  try { value = JSON.parse(text); } catch { throw invalid(); }
  if (!keys(value, ['schemaVersion', 'source', 'consentedAt', 'events'])
      || value.schemaVersion !== 1 || !Object.hasOwn(names, value.source)) throw invalid();
  const consented = timestamp(value.consentedAt);
  if (consented > now) throw Error('Receipt clock is in the future. No observations were collected.');
  if (consented + lifetime <= now) throw new ExpiredReceipt('Measurement receipt expired.');
  if (!Array.isArray(value.events) || !value.events.length || value.events.length > 32) throw invalid();
  let previous = consented;
  const ids = new Set(), seen = new Set();
  for (const row of value.events) {
    if (!keys(row, ['id', 'name', 'ts']) || !uuidPattern.test(row.id) || ids.has(row.id)
        || !names[value.source].has(row.name)) throw invalid();
    const at = timestamp(row.ts);
    if (at < previous || at > now) throw Error('Receipt clock or event ordering is invalid.');
    if (value.source === 'installer' && (seen.has(row.name)
        || (!seen.size && row.name !== 'installer_started')
        || (row.name === 'first_launch' && !seen.has('install_completed'))
        || (row.name === 'signin_view' && !seen.has('first_launch')))) throw invalid();
    if (value.source === 'website' && !seen.size && row.name !== 'landing_view') throw invalid();
    ids.add(row.id); seen.add(row.name); previous = at;
  }
  return value;
}

export class LocalMeasurement {
  constructor(storage, { clock = Date.now, uuid = () => crypto.randomUUID() } = {}) {
    this.storage = storage; this.clock = clock; this.uuid = uuid;
  }
  current() {
    let raw;
    try { raw = this.storage.getItem(measurementKey); }
    catch { throw Error('Optional measurement receipt could not be read. No new observations collected.'); }
    if (raw === null) return null;
    try { return validateReceipt(raw, this.clock()); }
    catch (error) {
      if (!(error instanceof ExpiredReceipt)) throw error;
      this.clear();
      return null;
    }
  }
  save(value) {
    const text = JSON.stringify(value);
    validateReceipt(text, this.clock());
    try { this.storage.setItem(measurementKey, text); }
    catch { throw Error('Optional measurement receipt could not be saved. No new observations collected.'); }
  }
  consent() {
    const at = new Date(this.clock()).toISOString();
    this.save({ schemaVersion: 1, source: 'website', consentedAt: at,
      events: [{ id: this.uuid(), name: 'landing_view', ts: at }] });
  }
  record(name) {
    if (!names.website.has(name)) throw Error('Unsupported website observation.');
    const value = this.current();
    if (!value) return false;
    if (value.events.length >= 32) throw Error('Receipt observation limit reached. Export or clear it; no new observations collected.');
    value.events.push({ id: this.uuid(), name, ts: new Date(this.clock()).toISOString() });
    this.save(value);
    return true;
  }
  export() {
    const value = this.current();
    if (!value) throw Error('No current consented receipt is available to export.');
    return JSON.stringify(value, null, 2);
  }
  clear() {
    try { this.storage.removeItem(measurementKey); }
    catch { throw Error('Optional measurement receipt could not be removed. Clear this site storage in your browser.'); }
  }
}

export function initializeMeasurement() {
  const checkbox = document.getElementById('measurement-consent');
  const status = document.getElementById('local-measurement-status');
  const exportButton = document.getElementById('export-measurement');
  const clearButton = document.getElementById('clear-measurement');
  let collector;
  const report = error => { status.textContent = error.message; };
  const invitationViewed = () => {
    // A valid current invite view, not restoration or referral redemption.
    let intent;
    try {
      intent = parseInvitation(location.search);
    } catch {
      status.textContent = 'Invalid invitation was not measured. No invitation data is in the receipt.';
      return;
    }
    if (intent) collector.record('invite_link_open');
  };
  try {
    collector = new LocalMeasurement(localStorage);
    checkbox.checked = collector.current() !== null;
    if (checkbox.checked) status.textContent = 'Prior local observation consent is active. Only post-consent observations stay in this browser; nothing is sent.';
    if (checkbox.checked) { collector.record('landing_view'); invitationViewed(); }
    exportButton.disabled = !checkbox.checked;
  } catch (error) {
    if (!collector) report(Error('Browser storage is unavailable. Optional measurement is off.'));
    else report(error);
  }
  checkbox.addEventListener('change', () => {
    try {
      if (!collector) collector = new LocalMeasurement(localStorage);
      if (checkbox.checked) { collector.consent(); invitationViewed(); }
      else collector.clear();
      exportButton.disabled = !checkbox.checked;
      status.textContent = checkbox.checked
        ? 'Local observation consent saved. Nothing was sent. Export and explicitly link in app Settings only if you choose.'
        : 'Local receipt removed; no further website observations.';
    } catch (error) { checkbox.checked = false; exportButton.disabled = true; report(error); }
  });
  for (const link of document.querySelectorAll('[data-measure-download]')) {
    link.addEventListener('click', () => {
      try { if (checkbox.checked && collector?.record('download_click')) status.textContent = 'Download click observed locally, not download or install success. Nothing was sent.'; }
      catch (error) { report(error); }
    });
  }
  exportButton.addEventListener('click', () => {
    try {
      const url = URL.createObjectURL(new Blob([collector.export()], { type: 'application/json' }));
      const link = document.createElement('a');
      link.href = url; link.download = 'bloomstep-website-measurement.json'; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = 'Receipt export requested. Linking to your signed-in account is a separate app choice.';
    } catch (error) { report(error); }
  });
  clearButton.addEventListener('click', () => {
    try {
      if (!collector) collector = new LocalMeasurement(localStorage);
      collector.clear(); checkbox.checked = false; exportButton.disabled = true;
      status.textContent = 'Local receipt removed. An exported copy or already-linked account events must be removed separately.';
    } catch (error) { report(error); }
  });
}
