import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('upgrade retains the uninstall identity but never inherits the prior product directory or group', () => {
  const setup = read('packaging/budlark.iss');
  assert.match(setup, /AppId=\{\{99BE7E95-0565-4C72-A4DD-46D1D5B6C679\}/);
  assert.doesNotMatch(setup, /UsePreviousAppDir=yes/);
  assert.match(setup, /^UsePreviousGroup=no$/m);
  assert.match(setup, /^DefaultDirName=\{localappdata\}\\Programs\\Budlark$/m);
  assert.match(setup, /^DefaultGroupName=Budlark$/m);
  assert.match(setup, /#include "upgrade-migration\.iss"/);
  assert.match(setup, /InitializeWizard\(\);[\s\S]*CapturePreviousInstallation\(\)/);
  assert.match(setup, /if CurStep = ssPostInstall then begin[\s\S]*CompleteUpgradeMigration\(\)/);
});

test('migration derives only the active Inno identity and bounds every prior file deletion', () => {
  const migration = read('packaging/upgrade-migration.iss');
  assert.match(migration, /SetupSetting\("AppId"\)/);
  for (const name of ['Inno Setup: App Path', 'InstallLocation', 'DisplayIcon', 'UninstallString', 'Inno Setup: Icon Group']) {
    assert.ok(migration.includes(`'${name}'`), name);
  }
  assert.match(migration, /RegQueryStringValue\(HKCU/);
  assert.match(migration, /CompareText\(AppPath, UpgradePlainPath\(Location\)\)/);
  assert.match(migration, /CompareText\(ExtractFileDir\(AppPath\), Programs\)/);
  assert.match(migration, /CompareText\(Icon, AppPath \+ '\\' \+ ExtractFileName\(AppPath\) \+ '\.exe'\)/);
  assert.match(migration, /CompareText\(Icon, AppPath \+ '\\budlark\.exe'\)/);
  assert.match(migration, /PreviousOriginalExecutable := AppPath \+ '\\' \+ ExtractFileName\(AppPath\) \+ '\.exe'/);
  assert.match(migration, /UpgradeUninstallerName\(Uninstaller\)/);
  assert.match(migration, /Attributes and \$400/);
  assert.match(migration, /CompareText\(Result, ExpandFileName\(Result\)\)/);
  assert.match(migration, /RegisterExtraCloseApplicationsResource\(False, PreviousExecutable\)/);
  assert.doesNotMatch(migration, /\b(?:DelTree|Exec|ShellExec|RegDeleteKeyIncludingSubkeys)\s*\(/);
  assert.deepEqual([...migration.matchAll(/DeleteFile\(([^)]+)\)/g)].map(match => match[1]), [
    'Filename', 'Filename',
  ]);
  assert.match(read('packaging/budlark.iss'),
    /if CurStep = ssPostInstall then begin\s+CompleteUpgradeMigration\(\)/);
});

test('shortcut retirement verifies exact targets and cannot delete newly installed or unrelated links', () => {
  const migration = read('packaging/upgrade-migration.iss');
  assert.match(migration, /Shell\.CreateShortcut\(Filename\)/);
  assert.match(migration, /Target := Shortcut\.TargetPath/);
  assert.match(migration, /CompareText\(Target, PreviousExecutable\) = 0/);
  assert.match(migration, /CompareText\(Target, PreviousOriginalExecutable\) = 0/);
  assert.match(migration, /CompareText\(Target, PreviousUninstaller\) = 0/);
  assert.match(migration, /CompareText\(Target, ExpandConstant\('\{app\}\\budlark\.exe'\)\) <> 0/);
  assert.match(migration, /CompareText\(Target, ExpandConstant\('\{uninstallexe\}'\)\) <> 0/);
  assert.match(migration, /CompareText\(Filename, ExpandConstant\('\{app\}\\budlark\.exe'\)\) <> 0/);
  assert.match(migration, /RetirePreviousExecutable\(PreviousExecutable\)/);
  assert.match(migration, /RetirePreviousExecutable\(PreviousOriginalExecutable\)/);
  assert.match(migration, /UpgradeMigrationFailed := True;[\s\S]*RetirePreviousExecutable/);
  assert.match(migration, /GetCustomSetupExitCode[\s\S]*if UpgradeMigrationFailed then\s+Result := 10/);
  assert.match(migration, /RemoveDir\(PreviousGroup\)/);
  assert.doesNotMatch(migration, /DeleteFile\([^)]*(?:\*|owner|receipt|session|credential|garden)/i);
  const setup = read('packaging/budlark.iss');
  assert.match(setup, /AppUserModelID: "Budlark\.Garden"/);
  assert.match(setup, /AppUserModelToastActivatorCLSID: "dc9b4d34-b0de-4df7-aead-690d8a5304a2"/);
});

test('native upgrade simulation compiles actual migration under isolated identity and withholds real owner acceptance', () => {
  const fixture = read('packaging/upgrade-fixture.iss');
  assert.match(fixture, /AppId=\{\{A6690692-4D92-475A-9EAC-1AD867AB0635\}/);
  assert.doesNotMatch(fixture, /99BE7E95/);
  assert.match(fixture, /UpgradeRenamedExecutableFixture/);
  const proof = read('tool/verify_installer_upgrade.ps1');
  for (const contract of ['BUDLARK_DISPOSABLE_VM', 'GITHUB_ACTIONS', 'Start-ProtectedInstallerProof',
    'Assert-InstallerProtectionUnchanged', '/DOnboardingJourneyFixture', 'packaging\\budlark.iss',
    'Assert-SyntheticDataPreserved', 'Assert-NewShortcuts', 'forced-before-install-failure',
    'same-product-reinstall', 'upgrade-preserving-unrelated-links', 'new-uninstall',
    'renamed-executable-in-prior-location', 'renamedExecutableInPriorLocationAlsoRetired',
    'cleanupVerified', 'real prior release and app data compatibility unverified']) {
    assert.ok(proof.includes(contract), contract);
  }
  assert.match(proof, /refuses pre-existing product or fixture state/);
  assert.match(proof, /migrationSha256/);
  assert.doesNotMatch(proof, /Set-MpPreference|Add-MpPreference|ExecutionPolicy Bypass|runas\b/i);
});

test('native upgrade proof PowerShell parses without executing installers', () => {
  const path = fileURLToPath(new URL('../tool/verify_installer_upgrade.ps1', import.meta.url));
  const script = `$errors = $null; $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
      '${path.replaceAll("'", "''")}', [ref]$tokens, [ref]$errors)
    if ($errors.Count) { $errors | Out-String | Write-Error; exit 1 }`;
  const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout || result.error?.message);
});
