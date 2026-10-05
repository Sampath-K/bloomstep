import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('customer branding provisioning preserves existing content and fails on wrong tenant/readback', () => {
  const script = fileURLToPath(new URL('../infra/test-configure-customer-branding.ps1', import.meta.url));
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `& '${script.replaceAll("'", "''")}'`], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});

test('native user-visible titles and publisher do not retain scaffold identifiers', () => {
  assert.match(read('windows/runner/main.cpp'), /window\.Create\(L"Bloomstep"/);
  const metadata = read('windows/runner/Runner.rc');
  assert.match(metadata, /VALUE "ProductName", "Bloomstep"/);
  assert.match(metadata, /VALUE "FileDescription", "Bloomstep"/);
  assert.match(metadata, /VALUE "CompanyName", "Bloomstep contributors"/);
  assert.doesNotMatch(metadata, /com\.bloomstep/);
});

test('native sign-in and both callback outcomes identify Bloomstep without hiding security errors', () => {
  assert.match(read('lib/app/bloomstep_app.dart'), /ciamlogin\.com is Microsoft's sign-in service for Bloomstep/);
  assert.match(read('lib/services/identity.dart'), /Bloomstep sign-in response is invalid/);
  assert.match(read('lib/services/identity.dart'), /Return to Bloomstep/);
  assert.match(read('lib/features/garden/garden_screen.dart'), /A tiny step together with Bloomstep/);
});

test('stable Windows storage is installed before instance, invitations and credentials open', () => {
  const main = read('lib/main.dart');
  assert.ok(main.indexOf('installWindowsStorageIdentity();') > main.indexOf('WidgetsFlutterBinding.ensureInitialized();'));
  assert.ok(main.indexOf('installWindowsStorageIdentity();') < main.indexOf('getApplicationSupportDirectory()'));
  assert.match(read('lib/services/identity.dart'), /wOptions: WindowsOptions\(useBackwardCompatibility: false\)/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /Branding relocated the existing Windows storage namespace/);
  assert.match(workflow, /Branding altered the synthetic upgrade preservation marker/);
});

test('site, operator popup and download labels are product-branded', () => {
  const site = read('site/index.html');
  assert.match(site, /Download Bloomstep ARM64/);
  assert.match(site, /Download Bloomstep x64/);
  assert.match(site, /Sign in to Bloomstep operator console/);
  assert.match(site, /rel="icon"/);
  assert.match(read('site/operator-callback.html'), /Completing Bloomstep operator sign-in/);
});

test('public branding release links both verified native preview4 artifacts without claiming accepted MVP', () => {
  const site = read('site/index.html');
  for (const arch of ['arm64', 'x64']) {
    assert.ok(site.includes(`releases/download/v0.1.0-preview.4/Bloomstep-0.1.0-preview.4-windows-${arch}-setup.exe`));
  }
  assert.match(site, /0\.1\.0-preview\.4 - Bloomstep identity and Windows branding/);
  assert.match(site, /not the full MVP/);
});

test('branding assets have genuine binary formats and do not replace protocol identifiers', () => {
  const png = readFileSync(new URL('../site/assets/bloomstep-wordmark.png', import.meta.url));
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  assert.ok(png.readUInt32BE(16) <= 245);
  assert.ok(png.readUInt32BE(20) <= 36);
  const icon = readFileSync(new URL('../windows/runner/resources/app_icon.ico', import.meta.url));
  assert.equal(icon.readUInt16LE(2), 1);
  assert.match(read('lib/services/identity.dart'), /http:\/\/127\.0\.0\.1:43821\/callback/);
  assert.match(read('packaging/bloomstep.iss'), /Software\\Classes\\bloomstep/);
});
