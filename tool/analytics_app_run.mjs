import { mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { localConfig } from './analytics_config.mjs';

const values = await localConfig();
const output = new URL('../build/analytics-defines.json', import.meta.url);
await mkdir(new URL('../build/', import.meta.url), { recursive: true });
await writeFile(output, JSON.stringify({
  BLOOMSTEP_ANALYTICS_SANDBOX: 'true',
  APTABASE_APP_KEY: values.APTABASE_APP_KEY || '',
  SENTRY_DSN: values.SENTRY_DSN || '',
}));
// flutter is a batch launcher on Windows; no key values enter the command line.
const args = ['run', '-d', 'windows', '--debug', `--dart-define-from-file=${fileURLToPath(output)}`];
const child = process.platform === 'win32'
  ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `flutter ${args.map(arg => `"${arg}"`).join(' ')}`], { stdio: 'inherit' })
  : spawn('flutter', args, { stdio: 'inherit' });
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', code => { process.exitCode = code ?? 1; });
