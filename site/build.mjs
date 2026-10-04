import { build } from 'esbuild';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { validatePublicConfig } from './operator-auth.mjs';
import { fileURLToPath } from 'node:url';

const values=['CONSOLE_CLIENT_ID','OIDC_ISSUER','OIDC_API_SCOPE','API_ORIGIN'].map(key=>process.env[key]);
if(values.some(Boolean) && !values.every(Boolean)) throw Error('All public console deployment identifiers are required together.');
await mkdir(new URL('./assets/',import.meta.url),{recursive:true});
const index=await readFile(new URL('./index.html',import.meta.url),'utf8');
const theme=/<style>([\s\S]*?)<\/style>/.exec(index)?.[1];
if(!theme) throw Error('Existing site theme is required for callback.');
await writeFile(new URL('./assets/theme.css',import.meta.url),theme);
await build({entryPoints:[fileURLToPath(new URL('./console.mjs',import.meta.url))],bundle:true,format:'esm',target:'es2022',outfile:fileURLToPath(new URL('./assets/console.js',import.meta.url)),minify:true,sourcemap:false});
const config=values.every(Boolean) ? validatePublicConfig({clientId:values[0],issuer:values[1],scope:values[2]},values[3]) : null;
await writeFile(new URL('./operator-config.json',import.meta.url),JSON.stringify(config ? {clientId:config.clientId,issuer:config.issuer,scope:config.scope} : {configured:false}));
console.log(config ? 'Built bundled operator login with public identifiers.' : 'Built unconfigured fail-closed operator preview.');
