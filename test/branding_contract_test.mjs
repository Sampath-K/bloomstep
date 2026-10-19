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
  assert.match(read('windows/runner/main.cpp'), /window\.Create\(L"Budlark"/);
  const metadata = read('windows/runner/Runner.rc');
  assert.match(metadata, /VALUE "ProductName", "Budlark"/);
  assert.match(metadata, /VALUE "FileDescription", "Budlark"/);
  assert.match(metadata, /VALUE "CompanyName", "Budlark contributors"/);
  assert.doesNotMatch(metadata, /com\.budlark/);
});

test('native sign-in and both callback outcomes identify Budlark without hiding security errors', () => {
  assert.match(read('lib/app/budlark_app.dart'), /profile_section\.dart/);
  const profile = read('lib/features/garden/profile_section.dart');
  assert.match(profile, /Microsoft or Google.*your password stays in your browser/);
  assert.match(read('lib/features/garden/sign_in_welcome.dart'), /Microsoft, Google or email code in your browser/);
  assert.doesNotMatch(profile, /ciamlogin\.com|login\.live\.com/);
  assert.match(read('lib/services/identity.dart'), /Budlark sign-in response is invalid/);
  assert.match(read('lib/services/identity.dart'), /Return to Budlark/);
  assert.match(read('lib/features/garden/invitation_dialog.dart'), /A tiny step together with Budlark/);
});

test('stable Windows storage is installed before instance, invitations and credentials open', () => {
  const main = read('lib/main.dart');
  assert.ok(main.indexOf('installWindowsStorageIdentity();') > main.indexOf('WidgetsFlutterBinding.ensureInitialized();'));
  assert.ok(main.indexOf('installWindowsStorageIdentity();') < main.indexOf('getApplicationSupportDirectory()'));
  assert.match(read('lib/services/identity.dart'), /wOptions: WindowsOptions\(useBackwardCompatibility: false\)/);
  assert.match(read('.github/workflows/ci.yml'), /run: flutter test --reporter expanded/);
  assert.match(read('test/windows_storage_identity_test.dart'), /branding cannot relocate garden, credential or instance storage/);
});

test('site, operator popup and download labels are product-branded', () => {
  const site = read('site/index.html');
  assert.match(site, /Owner-test download \(designated testers only\)/);
  assert.match(site, /Budlark ARM64/);
  assert.match(site, /Budlark x64/);
  assert.doesNotMatch(site, /Sign in to Budlark operator console/);
  assert.match(read('site/console.html'), /Sign in to Budlark (?:operator )?console/);
  assert.match(site, /rel="icon"/);
  assert.match(read('site/operator-callback.html'), /Completing Budlark operator sign-in/);
});

test('customer release page makes the owner-test restriction clear and excludes operator evidence', () => {
  const site = read('site/releases/index.html');
  for (const arch of ['arm64', 'x64', 'universal']) {
    assert.ok(site.includes(`releases/download/v0.1.0-preview.14/Budlark-0.1.0-preview.14-windows-${arch}-setup.exe`));
  }
  assert.ok(site.includes('7ad56cc3c71a40d78dd7cb043b43aa42ea884cb0484da982cffa386c9384b094'));
  assert.match(site, /Early preview — not yet verified for general use/);
  assert.match(site, /The files are publicly reachable, but download them only if you are the designated tester/);
  assert.match(site, /Launch after installation and the complete app journey have not been verified/);
  assert.match(site, /Recent preview changes/);
  assert.doesNotMatch(site, /owner-trial-checklist|docs\/status\.md|\bCI\b|elevated worker|launch gates|support receipts|stale-device|API audit/i);
});

test('branding assets have genuine binary formats and do not replace protocol identifiers', () => {
  const png = readFileSync(new URL('../site/assets/budlark-wordmark.png', import.meta.url));
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  assert.ok(png.readUInt32BE(16) <= 245);
  assert.ok(png.readUInt32BE(20) <= 36);
  const icon = readFileSync(new URL('../windows/runner/resources/app_icon.ico', import.meta.url));
  assert.equal(icon.readUInt16LE(2), 1);
  assert.match(read('lib/services/identity.dart'), /http:\/\/127\.0\.0\.1:43821\/callback/);
  assert.match(read('packaging/budlark.iss'), /Software\\Classes\\budlark/);
});

test('Budlark display metadata, packages and binaries share the product identity', () => {
  assert.match(read('lib/app/budlark_app.dart'), /title: 'Budlark'/);
  assert.match(read('android/app/src/main/AndroidManifest.xml'), /android:label="Budlark"/);
  assert.match(read('android/app/build.gradle.kts'), /applicationId = "com\.budlark\.budlark"/);
  assert.match(read('ios/Runner/Info.plist'), /<key>CFBundleDisplayName<\/key>\s*<string>Budlark<\/string>/);
  assert.match(read('macos/Runner/Info.plist'), /<key>CFBundleDisplayName<\/key>\s*<string>Budlark<\/string>/);
  for (const platform of ['ios', 'macos']) {
    assert.match(read(`${platform}/Runner/Info.plist`), /<key>CFBundleName<\/key>\s*<string>Budlark<\/string>/);
  }
  assert.match(read('macos/Runner/Configs/AppInfo.xcconfig'), /PRODUCT_NAME = budlark/);
  assert.match(read('windows/CMakeLists.txt'), /set\(BINARY_NAME "budlark"\)/);
  assert.match(read('pubspec.yaml'), /^name: budlark\n/);
  assert.match(read('pubspec.yaml'), /description: "Budlark -/);
});

test('installer preserves its AppId while using the clean-break product identity', () => {
  const setup = read('packaging/budlark.iss');
  assert.match(setup, /^AppName=Budlark$/m);
  assert.match(setup, /^AppName=Budlark isolated journey proof$/m);
  assert.match(read('.github/workflows/ci.yml'), /Compile isolated standard-wizard contract fixture/);
  assert.match(setup, /^AppPublisher=Budlark contributors$/m);
  assert.match(setup, /Description: "Launch Budlark"/);
  assert.match(read('packaging/install-progress.iss'), /Welcome to Budlark/);
  assert.match(setup, /AppId=\{\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679\}/);
  assert.match(setup, /^DefaultDirName=\{localappdata\}\\Programs\\Budlark$/m);
  assert.match(setup, /^DefaultGroupName=Budlark$/m);
  assert.match(setup, /^OutputBaseFilename=Budlark-/m);
  assert.match(setup, /Name: "\{group\}\\Budlark"; Filename: "\{app\}\\budlark\.exe"/);
  assert.doesNotMatch(setup, /CurrentVersion\\Run|\{userstartup\}/);
  assert.match(setup, /ValueData: "URL:Budlark invitation"/);
  assert.match(read('lib/services/desktop_reminders.dart'), /appName: 'Budlark',\s*appUserModelId: 'Budlark\.Garden'/);
  assert.match(read('lib/services/desktop_reminders.dart'), /launchAtStartup\.setup\(\s*appName: 'Budlark'/);
  assert.match(read('lib/services/windows_storage_identity.dart'), /p\.join\(root, 'Budlark'\)/);
  assert.match(read('lib/services/identity.dart'), /key: 'budlark-session'/);
  assert.match(read('site/invitation-landing.mjs'), /budlark\.pending-invitation\.v1/);
});

test('public metadata and download labels use Budlark', () => {
  for (const path of ['site/index.html', 'site/releases/index.html']) {
    const html = read(path);
    assert.match(html, /<title>Budlark/);
    assert.match(html, /property="og:title" content="Budlark/);
    assert.match(html, /name="twitter:title" content="Budlark/);
    assert.match(html, /Budlark-0\.1\.0-preview\.14-windows-universal-setup\.exe/);
  }
  assert.match(read('site/index.html'), /"name":"Budlark"/);
  assert.match(read('site/release-downloads.mjs'), />Budlark x64</);
  assert.match(read('site/release-downloads.mjs'), />Budlark ARM64</);
  assert.match(read('tool/generate_brand_assets.py'), /"Budlark"/);
  assert.match(read('tool/create_social_image.ps1'), /DrawString\('Budlark'/);
  assert.match(read('infra/configure-customer-branding.ps1'), /SignIn_Title = 'Sign in to Budlark'/);
  assert.match(read('site/console.html'), /server-assigned Budlark\.Admin/);
});

test('retired product identity is absent from every tracked file and path with no exceptions', () => {
  const retired = ['bloom', 'step'].join('');
  const cwd = fileURLToPath(new URL('../', import.meta.url));
  const content = spawnSync('git', ['grep', '-i', '-l', '--', retired], { cwd, encoding: 'utf8' });
  assert.equal(content.status, 1, content.stdout || content.stderr || content.error?.message);
  const paths = spawnSync('git', ['ls-files', '-z'], { cwd, encoding: 'utf8' });
  assert.equal(paths.status, 0, paths.stderr || paths.error?.message);
  assert.deepEqual(paths.stdout.split('\0').filter(path => path.toLowerCase().includes(retired)), []);
});
