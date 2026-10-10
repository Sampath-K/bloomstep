import { readFile } from 'node:fs/promises';

export const keys = ['GA4_ID', 'CLARITY_ID', 'CLOUDFLARE_TOKEN', 'POSTHOG_KEY', 'POSTHOG_REGION',
  'APTABASE_APP_KEY', 'SENTRY_DSN'];
export async function localConfig() {
  let text = '';
  try { text = await readFile(new URL('../.env.analytics.local', import.meta.url), 'utf8'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line);
    if (!match || !keys.includes(match[1])) throw Error('Invalid analytics configuration line.');
    values[match[1]] = match[2].trim().replace(/^["']|["']$/g, '');
  }
  for (const key of keys) if (process.env[key] !== undefined) values[key] = process.env[key];
  return values;
}
export function websiteConfig(values) {
  const patterns = { GA4_ID: /^G-[A-Z0-9]+$/, CLARITY_ID: /^[a-z0-9]+$/,
    CLOUDFLARE_TOKEN: /^[a-f0-9-]{36}$/, POSTHOG_KEY: /^phc_[a-zA-Z0-9]+$/ };
  for (const [key, pattern] of Object.entries(patterns)) {
    if (values[key] && !pattern.test(values[key])) throw Error(`Invalid ${key}.`);
  }
  if (values.POSTHOG_REGION && !['EU', 'US'].includes(values.POSTHOG_REGION)) throw Error('POSTHOG_REGION must be EU or US.');
  return Object.fromEntries([...Object.keys(patterns), 'POSTHOG_REGION'].map(key => [key, values[key] || (key === 'POSTHOG_REGION' ? 'EU' : '')]));
}
