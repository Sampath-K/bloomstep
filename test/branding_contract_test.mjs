import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('customer branding provisioning preserves existing content and fails on wrong tenant/readback', () => {
  const script = fileURLToPath(new URL('../infra/test-configure-customer-branding.ps1', import.meta.url));
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `& '${script.replaceAll("'", "''")}'`], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});

test('native user-visible titles and publisher do not retain scaffold identifiers', () => {
  assert.match(read('windows/runner/main.cpp'), /window\.Create\(L"Budlock"/);
  const metadata = read('windows/runner/Runner.rc');
  assert.match(metadata, /VALUE "ProductName", "Budlock"/);
  assert.match(metadata, /VALUE "FileDescription", "Budlock"/);
  assert.match(metadata, /VALUE "CompanyName", "Budlock contributors"/);
  assert.doesNotMatch(metadata, /com\.bloomstep/);
});

test('native sign-in and both callback outcomes identify Budlock without hiding security errors', () => {
  assert.match(read('lib/app/bloomstep_app.dart'), /profile_section\.dart/);
  const profile = read('lib/features/garden/profile_section.dart');
  assert.match(profile, /Choose Microsoft personal account, Google or another enabled option in the system browser/);
  assert.match(profile, /Budlock never collects your password/);
  assert.doesNotMatch(profile, /ciamlogin\.com|login\.live\.com/);
  assert.match(read('lib/services/identity.dart'), /Budlock sign-in response is invalid/);
  assert.match(read('lib/services/identity.dart'), /Return to Budlock/);
  assert.match(read('lib/features/garden/garden_screen.dart'), /A tiny step together with Budlock/);
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
  assert.match(site, /Owner-test download \(designated testers only\)/);
  assert.match(site, /Budlock ARM64/);
  assert.match(site, /Budlock x64/);
  assert.doesNotMatch(site, /Sign in to Budlock operator console/);
  assert.match(read('site/console.html'), /Sign in to Budlock (?:operator )?console/);
  assert.match(site, /rel="icon"/);
  assert.match(read('site/operator-callback.html'), /Completing Budlock operator sign-in/);
});

test('customer release page makes the owner-test restriction clear and excludes operator evidence', () => {
  const site = read('site/releases/index.html');
  for (const arch of ['arm64', 'x64', 'universal']) {
    assert.ok(site.includes(`releases/download/v0.1.0-preview.14/Bloomstep-0.1.0-preview.14-windows-${arch}-setup.exe`));
  }
  assert.ok(site.includes('7ad56cc3c71a40d78dd7cb043b43aa42ea884cb0484da982cffa386c9384b094'));
  assert.match(site, /Early preview — not yet verified for general use/);
  assert.match(site, /The files are publicly reachable, but download them only if you are the designated tester/);
  assert.match(site, /Launch after installation and the complete sign-in and app journey have not been verified/);
  assert.match(site, /Recent preview changes/);
  assert.doesNotMatch(site, /owner-trial-checklist|docs\/status\.md|\bCI\b|elevated worker|launch gates|support receipts|stale-device|API audit/i);
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

test('Budlock display metadata is consistent without renaming package or binary identities', () => {
  assert.match(read('lib/app/bloomstep_app.dart'), /title: 'Budlock'/);
  assert.match(read('android/app/src/main/AndroidManifest.xml'), /android:label="Budlock"/);
  assert.match(read('android/app/build.gradle.kts'), /applicationId = "com\.bloomstep\.bloomstep"/);
  assert.match(read('ios/Runner/Info.plist'), /<key>CFBundleDisplayName<\/key>\s*<string>Budlock<\/string>/);
  assert.match(read('macos/Runner/Info.plist'), /<key>CFBundleDisplayName<\/key>\s*<string>Budlock<\/string>/);
  for (const platform of ['ios', 'macos']) {
    assert.match(read(`${platform}/Runner/Info.plist`), /<key>CFBundleName<\/key>\s*<string>Budlock<\/string>/);
  }
  assert.match(read('macos/Runner/Configs/AppInfo.xcconfig'), /PRODUCT_NAME = bloomstep/);
  assert.match(read('windows/CMakeLists.txt'), /set\(BINARY_NAME "bloomstep"\)/);
  assert.match(read('pubspec.yaml'), /^name: bloomstep\n/);
  assert.match(read('pubspec.yaml'), /description: "Budlock -/);
});

test('installer UI changes but upgrade identity, paths, startup and protocol remain stable', () => {
  const setup = read('packaging/bloomstep.iss');
  assert.match(setup, /^AppName=Budlock$/m);
  assert.match(setup, /^AppName=Bloomstep isolated journey proof$/m);
  assert.match(read('.github/workflows/ci.yml'), /AppName=Bloomstep isolated journey proof/);
  assert.match(setup, /^AppPublisher=Budlock contributors$/m);
  assert.match(setup, /Description: "Launch Budlock"/);
  assert.match(read('packaging/install-progress.iss'), /Welcome to Budlock/);
  assert.match(setup, /AppId=\{\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679\}/);
  assert.match(setup, /^DefaultDirName=\{localappdata\}\\Programs\\Bloomstep$/m);
  assert.match(setup, /^DefaultGroupName=Bloomstep$/m);
  assert.match(setup, /^OutputBaseFilename=Bloomstep-/m);
  assert.match(setup, /Name: "\{group\}\\Bloomstep"; Filename: "\{app\}\\bloomstep\.exe"/);
  assert.match(setup, /ValueName: "Bloomstep"; Flags: uninsdeletevalue/);
  assert.match(setup, /ValueData: "URL:Budlock invitation"/);
  assert.match(read('lib/services/desktop_reminders.dart'), /appName: 'Budlock',\s*appUserModelId: 'Bloomstep\.Garden'/);
  assert.match(read('lib/services/desktop_reminders.dart'), /launchAtStartup\.setup\(\s*appName: 'Bloomstep'/);
  assert.match(read('lib/services/windows_storage_identity.dart'), /p\.join\(root, 'com\.bloomstep', 'bloomstep'\)/);
  assert.match(read('lib/services/identity.dart'), /key: 'bloomstep-session'/);
  assert.match(read('site/invitation-landing.mjs'), /bloomstep\.pending-invitation\.v1/);
});

test('public metadata uses Budlock while authentic historical filenames stay exact', () => {
  for (const path of ['site/index.html', 'site/releases/index.html']) {
    const html = read(path);
    assert.match(html, /<title>Budlock/);
    assert.match(html, /property="og:title" content="Budlock/);
    assert.match(html, /name="twitter:title" content="Budlock/);
    assert.match(html, /Bloomstep-0\.1\.0-preview\.14-windows-universal-setup\.exe/);
  }
  assert.match(read('site/index.html'), /"name":"Budlock"/);
  assert.match(read('site/release-downloads.mjs'), />Budlock x64</);
  assert.match(read('site/release-downloads.mjs'), />Budlock ARM64</);
  assert.match(read('tool/generate_brand_assets.py'), /"Budlock"/);
  assert.match(read('tool/create_social_image.ps1'), /DrawString\('Budlock'/);
  assert.match(read('infra/configure-customer-branding.ps1'), /SignIn_Title = 'Sign in to Budlock'/);
  assert.match(read('site/console.html'), /server-assigned Bloomstep\.Admin/);
});

test('customer prose has no old product name beyond the explicit compatibility and evidence exceptions', () => {
  const paths = [
    ...readdirSync(new URL('../lib/', import.meta.url), { recursive: true })
      .filter(path => path.endsWith('.dart'))
      .map(path => `lib/${path.replaceAll('\\', '/')}`),
    'site/index.html', 'site/releases/index.html', 'site/console.html',
    'site/operator-callback.html', 'site/customer.mjs', 'site/console.mjs',
    'site/invitation-landing.mjs', 'site/release-downloads.mjs',
    'windows/runner/main.cpp', 'windows/runner/native_share.cpp',
    'infra/configure-customer-branding.ps1',
  ];
  for (const path of paths) {
    const prose = read(path)
      .replaceAll('X-Bloomstep-Authorization', 'Legacy-Authorization')
      .replaceAll('Bloomstep.Admin', 'Legacy.Admin')
      .replaceAll('Bloomstep.Garden', 'Legacy.Garden')
      .replaceAll("'Bloomstep', 'measurement'", "'Legacy', 'measurement'")
      .replaceAll("launchAtStartup.setup(\n        appName: 'Bloomstep'", "launchAtStartup.setup(\n        appName: 'Legacy'")
      .replaceAll('Earlier Bloomstep preview', 'Earlier preview')
      .replace(/\bBloomstep-(?=[0-9$])/g, 'LegacyArtifact-');
    assert.doesNotMatch(prose, /\bBloomstep\b/, path);
  }
});
