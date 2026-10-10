import { cp, mkdir, readFile, writeFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from '../site/node_modules/esbuild/lib/main.js';
import { localConfig, websiteConfig } from './analytics_config.mjs';

export const output = new URL('../build/analytics-site/', import.meta.url);
export async function buildSandbox(values) {
  const config = websiteConfig(values ?? await localConfig());
  await mkdir(new URL('assets/', output), { recursive: true });
  await cp(new URL('../site/assets/', import.meta.url), new URL('assets/', output), { recursive: true });
  await build({ entryPoints: [fileURLToPath(new URL('../site/customer.mjs', import.meta.url))],
    bundle: true, format: 'esm', outfile: fileURLToPath(new URL('assets/customer.js', output)) });
  await build({ stdin: { contents: `import {initializeSandbox} from './analytics_browser.mjs'; initializeSandbox(${JSON.stringify(config)});`,
    resolveDir: fileURLToPath(new URL('.', import.meta.url)), sourcefile: 'sandbox-entry.mjs' },
    bundle: true, format: 'esm', outfile: fileURLToPath(new URL('assets/sandbox.js', output)) });
  const panel = `<section class="notice" data-clarity-mask="true"><h2>Staging analytics sandbox - not production</h2>
    <p>Optional third-party measurement sends data to configured vendors. Session replay is masked; PostHog replay is disabled.
    Consent lasts for this visit only. Unchecking reloads the page to stop sending; earlier data remains with vendors.</p>
    <label><input type="checkbox" id="sandbox-consent"> Allow staging third-party analytics for this visit</label>
    <p id="sandbox-status" role="status">Off by default. No third-party requests.</p>
    <p>Test referral code: <code>BS-SANDBOX</code>. Enter this code in the staging app; it is a shared campaign, not a person identifier.</p></section>`;
  for (const page of ['index.html', 'releases/index.html']) {
    await mkdir(new URL(page === 'index.html' ? '.' : 'releases/', output), { recursive: true });
    let html = await readFile(new URL(`../site/${page}`, import.meta.url), 'utf8');
    html = html.replace('</head>', '<meta name="robots" content="noindex,nofollow,noarchive"></head>')
      .replace('<body>', '<body data-clarity-mask="true">')
      .replace('</main>', `${panel}</main>`)
      .replace('</body>', '<script type="module" src="/assets/sandbox.js"></script></body>');
    html = html.replace('There are no third-party product analytics scripts.', 'Production has no third-party analytics. This isolated staging page can load vendors only with the separate sandbox choice.');
    if (!html.includes('id="sandbox-consent"')) html = html.replace('</body>', `${panel}</body>`);
    await writeFile(new URL(page, output), html);
  }
  await writeFile(new URL('robots.txt', output), 'User-agent: *\nDisallow: /\n');
  await writeFile(new URL('staticwebapp.config.json', output), JSON.stringify({
    globalHeaders: { 'X-Robots-Tag': 'noindex, nofollow, noarchive', 'Referrer-Policy': 'no-referrer' },
  }));
  return output;
}
export async function assertProductionClean() {
  const forbidden = /googletagmanager|google-analytics|clarity\.ms|cloudflareinsights|posthog|aptabase|sentry|sandbox-consent/i;
  async function scan(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (['node_modules', 'test', 'package-lock.json', 'package.json'].includes(entry.name)) continue;
      const path = new URL(entry.name + (entry.isDirectory() ? '/' : ''), directory);
      if (entry.isDirectory()) await scan(path);
      else if (/\.(html|js|mjs|json|css)$/.test(entry.name) && forbidden.test(await readFile(path, 'utf8'))) {
        throw Error(`Production contains third-party analytics: ${path}`);
      }
    }
  }
  await scan(new URL('../site/', import.meta.url));
}
if (process.argv[1] === fileURLToPath(import.meta.url)) await buildSandbox();
