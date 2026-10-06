import { build } from 'esbuild';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { validatePublicConfig } from './operator-auth.mjs';
import { fileURLToPath } from 'node:url';

const values=['CONSOLE_CLIENT_ID','OIDC_ISSUER','OIDC_API_SCOPE','API_ORIGIN'].map(key=>process.env[key]);
if(values.some(Boolean) && !values.every(Boolean)) throw Error('All public console deployment identifiers are required together.');
await mkdir(new URL('./assets/',import.meta.url),{recursive:true});
const index=await readFile(new URL('./index.html',import.meta.url),'utf8');
for (const asset of ['habit-anchor.svg','habit-tiny.svg','habit-celebrate.svg',
  'download-flow.svg','edge-downloads.png','chrome-downloads.png','download-capture-provenance.json']) {
  const bytes = await readFile(new URL(`./assets/${asset}`, import.meta.url));
  if (!bytes.length) throw Error(`Required onboarding asset is empty: ${asset}`);
}
const theme=/<style>([\s\S]*?)<\/style>/.exec(index)?.[1];
if(!theme) throw Error('Existing site theme is required for callback.');
await writeFile(new URL('./assets/theme.css',import.meta.url),theme);
await build({entryPoints:[fileURLToPath(new URL('./console.mjs',import.meta.url))],bundle:true,format:'esm',target:'es2022',outfile:fileURLToPath(new URL('./assets/console.js',import.meta.url)),minify:true,sourcemap:false});
await build({entryPoints:[fileURLToPath(new URL('./customer.mjs',import.meta.url))],bundle:true,format:'esm',target:'es2022',outfile:fileURLToPath(new URL('./assets/customer.js',import.meta.url)),minify:true,sourcemap:false});
const customer = JSON.parse(await readFile(new URL('./customer-config.json',import.meta.url),'utf8'));
const origin = new URL(customer.origin);
if(origin.protocol !== 'https:' || origin.origin !== customer.origin) throw Error('Canonical origin must be an HTTPS origin.');
if(!/^v[0-9A-Za-z.-]+$/.test(customer.release.tag)) throw Error('Explicit release tag required.');
for (const arch of ['arm64','x64']) {
  const release = customer.release[arch];
  const expected = `https://github.com/Sampath-K/bloomstep/releases/download/${customer.release.tag}/Bloomstep-${customer.release.tag.slice(1)}-windows-${arch}-setup.exe`;
  if(release.url !== expected ||
      !/^[a-f0-9]{64}$/.test(release.sha256)) throw Error('Verified release assets and checksums required.');
}
for (const page of ['index.html','releases/index.html']) {
  const url = new URL(`./${page}`,import.meta.url);
  let html = await readFile(url,'utf8');
  html = html.replaceAll('https://brave-plant-02c10e800.5.azurestaticapps.net',customer.origin);
  for (const arch of ['arm64','x64']) {
    html = html.replace(new RegExp(`https://github\\.com/Sampath-K/bloomstep/releases/download/[^"\\s]+-windows-${arch}-setup\\.exe`,'g'),customer.release[arch].url);
    html = html.replace(new RegExp(`Bloomstep-[0-9A-Za-z.-]+-windows-${arch}-setup\\.exe(?=</code>)`, 'g'),
      `Bloomstep-${customer.release.tag.slice(1)}-windows-${arch}-setup.exe`);
  }
  html = html.replace(/(<span id="download-version">)[^<]+(<\/span>)/,
    `$1${customer.release.tag.slice(1)}$2`);
  if(page === 'releases/index.html') {
    html = html.replace(/ARM64 SHA-256: [a-f0-9]{64}/,`ARM64 SHA-256: ${customer.release.arm64.sha256}`)
      .replace(/x64 SHA-256: [a-f0-9]{64}/,`x64 SHA-256: ${customer.release.x64.sha256}`);
    html = html.replace(/https:\/\/github\.com\/Sampath-K\/bloomstep\/releases\/tag\/v[0-9A-Za-z.-]+/,
      `https://github.com/Sampath-K/bloomstep/releases/tag/${customer.release.tag}`);
  }
  html = html.replace(/\s*<meta name="(?:google-site-verification|msvalidate\.01)" content="[^"]*">/g,'');
  for (const [name, token] of [
    ['google-site-verification',process.env.GOOGLE_SITE_VERIFICATION || customer.googleVerification],
    ['msvalidate.01',process.env.BING_SITE_VERIFICATION || customer.bingVerification],
  ]) {
    if (!token) continue;
    if(!/^[a-zA-Z0-9_-]{1,256}$/.test(token)) throw Error('Invalid public search verification token.');
    html = html.replace('</head>',`  <meta name="${name}" content="${token}">\n</head>`);
  }
  await writeFile(url,html);
}
for (const page of ['robots.txt','sitemap.xml']) {
  const url = new URL(`./${page}`,import.meta.url);
  await writeFile(url,(await readFile(url,'utf8')).replaceAll('https://brave-plant-02c10e800.5.azurestaticapps.net',customer.origin));
}
const config=values.every(Boolean) ? validatePublicConfig({clientId:values[0],issuer:values[1],scope:values[2]},values[3]) : null;
await writeFile(new URL('./operator-config.json',import.meta.url),JSON.stringify(config ? {clientId:config.clientId,issuer:config.issuer,scope:config.scope} : {configured:false}));
console.log(config ? 'Built bundled operator login with public identifiers.' : 'Built unconfigured fail-closed operator preview.');
