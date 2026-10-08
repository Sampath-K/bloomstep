import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { packageVersion, packageManifest, appInstaller } from '../tool/msix_update.mjs';

const options = {
  version: '0.1.0-preview.13',
  publisher: 'CN=Bloomstep fixture',
  architecture: 'arm64',
};

test('monotonic Windows version mapping and separate stable/preview identity', () => {
  assert.equal(packageVersion(options.version), '0.1.0.13');
  assert.equal(packageVersion('0.1.0'), '0.1.0.65535');
  assert.equal(packageVersion('0.1.0-preview'), '0.1.0.0');
  for (const version of ['0.1.0-preview.0', '1.2.3-beta.4',
    '1.2.3+build', '1.2.3-preview.65535', '65536.1.0', '01.2.3']) {
    assert.throws(() => packageVersion(version));
  }
  assert.match(packageManifest(options), /Name="Bloomstep.Desktop.Preview"/);
  assert.match(packageManifest({ ...options, version: '0.1.0' }),
    /Name="Bloomstep.Desktop.Stable"/);
});

test('real executable full-trust nonvirtualized identity, protocol and architectures', () => {
  const manifest = packageManifest(options);
  assert.match(manifest, /ProcessorArchitecture="arm64"/);
  assert.match(manifest, /Executable="bloomstep.exe"/);
  assert.match(manifest, /RuntimeBehavior="win32App"/);
  assert.match(manifest, /TrustLevel="mediumIL"/);
  assert.match(manifest, /MinVersion="10.0.19041.0"/);
  assert.match(manifest, /Protocol Name="bloomstep"/);
  assert.doesNotMatch(manifest, /packagedClassicApp|FileSystemWriteVirtualization|appContainer/);
  assert.throws(() => packageManifest({ ...options, architecture: 'x86' }));
  assert.throws(() => packageManifest({ ...options, publisher: '' }));
  assert.match(packageManifest({ ...options, publisher: 'CN=A&B' }), /CN=A&amp;B/);
});

test('App Installer enrollment checks silently on launch and in background, never downgrades', () => {
  const feed = appInstaller(options);
  assert.match(feed, /appinstaller\/2021/);
  assert.match(feed, /HoursBetweenUpdateChecks="0"/);
  assert.match(feed, /ShowPrompt="false"/);
  assert.match(feed, /UpdateBlocksActivation="false"/);
  assert.match(feed, /AutomaticBackgroundTask/);
  assert.doesNotMatch(feed, /ForceUpdateFromAnyVersion|ForceApplicationShutdown/);
  assert.match(feed, /MainBundle Name="Bloomstep.Desktop.Preview"/);
  assert.match(feed, /releases\/download\/update-preview\/Bloomstep.appinstaller/);
  assert.match(feed, /releases\/download\/v0.1.0-preview.13\/Bloomstep-0.1.0-preview.13.msixbundle/);
  assert.match(feed, /Publisher="CN=Bloomstep fixture"/);
});

test('candidate workflow is exact-source gated, signed and not a publishing/migration shortcut', () => {
  const workflow = readFileSync(new URL('../.github/workflows/msix-candidate.yml', import.meta.url), 'utf8');
  const builder = readFileSync(new URL('../tool/build_msix.ps1', import.meta.url), 'utf8');
  const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.match(workflow, /environment: msix-signing/);
  assert.match(workflow, /head_sha -ne \$env:GITHUB_SHA/);
  assert.match(workflow, /conclusion -ne 'success'/);
  assert.match(workflow, /run.path -ne '\.github\/workflows\/ci.yml'/);
  assert.match(builder, /release_payload\.mjs', 'verify'/);
  assert.match(builder, /\$machine -ne \$expected/);
  assert.match(builder, /\$cert.Subject -cne \$Publisher/);
  assert.match(builder, /'verify', '\/pa', '\/v'/);
  assert.match(builder, /installedUpgrade = 'UNVERIFIED'/);
  assert.match(builder, /if \(-not \$UnsignedValidationOnly\)/);
  assert.match(builder, /UNSIGNED-SDK-VALIDATION-ONLY/);
  assert.match(ci, /msix-sdk-validation:[\s\S]*needs: \[test-and-build-windows\]/);
  assert.match(ci, /build_msix\.ps1[\s\S]*-UnsignedValidationOnly/);
  const validation = ci.split('  msix-sdk-validation:')[1].split('  release:')[0];
  assert.match(validation, /\$source = git rev-parse HEAD/);
  assert.match(validation, /-SourceSha \$source/);
  assert.doesNotMatch(validation, /-SourceSha \$env:GITHUB_SHA/);
  const fixture = readFileSync(new URL('../tool/verify_msix_packaging.ps1', import.meta.url), 'utf8');
  assert.match(fixture, /unprovisionedPublisherRejected = 'PASS'[\s\S]*\$global:LASTEXITCODE = 0/);
  assert.match(ci, /verify_msix_packaging\.ps1/);
  assert.doesNotMatch(workflow + builder,
    /gh release|Add-AppxPackage|Import-Certificate|TrustedPeople|Root\\|Start-Process|ForceApplicationShutdown/);
});
