import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const setup = () => read('packaging/bloomstep.iss');
const visual = () => read('packaging/install-progress.iss');
const section = (source, name) => source.split(`[${name}]`)[1]?.split(/\n\[/)[0] ?? '';

test('Defender-blocked private candidate is withdrawn, not treated as a reputation warning', () => {
  const docs = read('docs/installer-onboarding.md');
  assert.match(docs, /WITHDRAWN: Defender-blocked private candidate/);
  assert.match(docs, /Behavior:Win32\/DefenseEvasion\.A!ml/);
  assert.match(docs, /b58ba7fc3f39d66c7d3afc9022cbbeec2036fb58c0677940e20f1b036e4e2be5/);
  assert.match(docs, /Do not download, restore, distribute, or run/);
  assert.match(docs, /partial-install state is unknown/);
  assert.match(docs, /not established as a false positive/);
});

test('one source compiles exactly two flows: one-click default and zero-click experiment', () => {
  const source = setup();
  assert.match(source, /#ifndef InstallFlow\s+#define InstallFlow "oneclick"\s+#endif/);
  assert.match(source, /#if InstallFlow != "oneclick" && InstallFlow != "zeroclick"\s+#error/);
  // Inno always shows one pre-install page when not silent; zero-click owns it as the visual and never shows a generic welcome.
  assert.match(source, /DisableWelcomePage=no\s+#if InstallFlow == "zeroclick"\s+DisableDirPage=yes\s+#else\s+DisableDirPage=no\s+#endif/);
  assert.doesNotMatch(source, /DisableWelcomePage=yes/);
  assert.match(source, /DisableReadyPage=yes/);
  assert.match(source, /DisableFinishedPage=yes/);
  assert.match(source, /DisableProgramGroupPage=yes/);
  assert.match(source, /#if InstallFlow == "zeroclick"\s+OutputBaseFilename=Bloomstep-\{#AppVersion\}-windows-\{#AppArch\}-zeroclick-setup\s+#else\s+OutputBaseFilename=Bloomstep-\{#AppVersion\}-windows-\{#AppArch\}-setup\s+#endif/);
  assert.match(source, /DefaultDirName=\{localappdata\}\\Programs\\Bloomstep/);
  assert.match(source, /PrivilegesRequired=lowest/);
  assert.doesNotMatch(source, /PrivilegesRequiredOverridesAllowed|PrivilegesRequired=admin|ShellExec\(|DownloadTemporaryFile/);
});

test('no Finish page, launch checkbox or optional settings; successful interactive install opens the app non-elevated', () => {
  const source = setup();
  assert.doesNotMatch(section(source, 'Run'), /\S/, '[Run] must not offer a post-install checkbox');
  assert.doesNotMatch(source, /postinstall|RunList|FinishedLabel|FinishedHeadingLabel|wpFinished|CreateCustomPage\(|Launch Bloomstep and plant/);
  const gate = /function CanLaunchBloomstep\(\): Boolean;([\s\S]*?)\nend;/.exec(source)?.[1];
  assert.ok(gate);
  for (const guard of ['InstallationSucceeded', 'not WizardSilent', 'not IsAdmin', 'not LaunchAttempted', 'InteractiveDesktop']) {
    assert.ok(gate.includes(guard), guard);
  }
  const done = /procedure CurStepChanged\(CurStep: TSetupStep\);([\s\S]*?)\nend;/.exec(source)?.[1];
  assert.ok(done);
  assert.match(done, /CurStep = ssDone[\s\S]*CanLaunchBloomstep[\s\S]*ExecAsOriginalUser\(ExpandConstant\('\{app\}\\bloomstep\.exe'\), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode\)/);
  assert.match(done, /LaunchAttempted := True/);
  assert.match(done, /Bloomstep automatic launch/);
  assert.match(source, /IsAdmin[\s\S]*not WizardSilent[\s\S]*SuppressibleMsgBox\('Bloomstep is installed\. Open Bloomstep from the Start menu as your normal Windows account\.', mbInformation, MB_OK, IDOK\)/);
  assert.doesNotMatch(source, /[^e]MsgBox\('Bloomstep is installed/, '/SUPPRESSMSGBOXES must suppress the elevated-host notice');
});

test('neither flow can navigate back to an already auto-advanced splash', () => {
  const source = setup();
  const page = /procedure CurPageChanged\(CurPageID: Integer\);([\s\S]*?)\nend;/.exec(source)?.[1];
  assert.ok(page);
  assert.match(page, /WizardForm\.BackButton\.Visible := False;/);
  assert.match(page, /WizardForm\.BackButton\.Enabled := False;/);
  assert.match(source, /function BackButtonClick\(CurPageID: Integer\): Boolean;\s+begin\s+Result := False;\s+end;/);
  assert.match(read('tool/verify_install_progress.ps1'), /Installer must not offer Back/);
  for (const path of ['tool/verify_onboarding_wizard.ps1', 'tool/verify_install_progress.ps1']) {
    assert.match(read(path), /Destination must not offer Back/);
    assert.match(read(path), /destinationBackAbsent/);
  }
});

test('one visual says only Anchor, Action and Celebrate, with accessible native words and original art', () => {
  const progress = visual();
  const captions = [...progress.matchAll(/\.Caption := '([^']*)'/g)].map(match => match[1]);
  assert.deepEqual([...new Set(captions)].sort(), ['Action', 'Anchor', 'Celebrate']);
  assert.doesNotMatch(progress + setup(), /A little is enough|familiar routine|Not today leaves|WelcomeLabel[12]=/);
  assert.match(progress, /StepWords\[0\] := 'Anchor'[\s\S]*StepWords\[1\] := 'Action'[\s\S]*StepWords\[2\] := 'Celebrate'/);
  assert.match(progress, /welcome-steps\.bmp/);
  assert.match(progress, /welcome-garden\.bmp/);
  const files = section(setup(), 'Files');
  assert.match(files, /Source: "assets\\welcome-steps\.bmp"; Flags: dontcopy/);
  assert.match(files, /Source: "assets\\welcome-garden\.bmp"; Flags: dontcopy/);
  assert.doesNotMatch(files, /education-/);
  const manifest = JSON.parse(read('packaging/assets/education-art-provenance.json'));
  assert.deepEqual(manifest.assets.map(asset => asset.file), ['welcome-steps.bmp', 'welcome-garden.bmp']);
  for (const asset of manifest.assets) {
    const bmp = readFileSync(new URL(`../packaging/assets/${asset.file}`, import.meta.url));
    assert.equal(bmp.subarray(0, 2).toString(), 'BM');
    assert.equal(bmp.readInt32LE(18), asset.width);
    assert.equal(bmp.readInt32LE(22), asset.height);
    assert.equal(createHash('sha256').update(bmp).digest('hex'), asset.sha256);
  }
  const exporter = read('tool/installer_art_export_test.dart');
  assert.match(exporter, /'welcome-steps'/);
  assert.match(exporter, /'welcome-garden'/);
  assert.doesNotMatch(exporter, /\bText\(/, 'no words baked into pixels');
});

test('welcome auto-advances after 4s even with reduced motion; zero-click holds one visual about 5s while installing', () => {
  const progress = visual();
  assert.match(progress, /#if InstallFlow == "zeroclick"\s+WelcomeAdvanceMilliseconds = 0;\s+#else\s+WelcomeAdvanceMilliseconds = 4000;\s+#endif/);
  assert.match(progress, /ZeroClickVisualMilliseconds = 5000;/);
  const init = /procedure InitializeInstallMotion\(\);([\s\S]*?)\nend;/.exec(progress)?.[1];
  assert.ok(init);
  assert.doesNotMatch(init, /#if/, 'both flows build the welcome visual; the timer must never touch unbuilt art');
  assert.match(init, /WelcomeLabel1\.Visible := False[\s\S]*BuildVisual\(0, WizardForm\.WelcomePage/);
  assert.match(progress, /WizardForm\.NextButton\.OnClick\(WizardForm\.NextButton\)/);
  assert.match(progress, /CurPageID = wpWelcome[\s\S]*NextButton\.Visible := False[\s\S]*BackButton\.Visible := False/);
  assert.doesNotMatch(progress, /CancelButton\.Visible := False|CancelButton\.Enabled := False/);
  const start = /procedure StartVisualTimer\(\);([\s\S]*?)\nend;/.exec(progress)?.[1];
  assert.ok(start);
  assert.match(start, /SetTimer\(/);
  assert.doesNotMatch(start, /if not MotionAllowed then[\s\S]*Exit;[\s\S]*SetTimer/, 'static preference still auto-advances');
  assert.match(progress, /if MotionAllowed then[\s\S]*ScaleX\(Drift\)/);
  assert.match(progress, /\$1042/);
  assert.doesNotMatch(progress, /SPI_SET|SystemParametersInfo\(\$1043/);
  assert.match(progress, /#if InstallFlow == "zeroclick"[\s\S]*procedure HoldZeroClickVisual\(\);[\s\S]*PeekMessage[\s\S]*DispatchMessage[\s\S]*#endif/);
  assert.match(setup(), /#if InstallFlow == "zeroclick"\s+HoldZeroClickVisual\(\);\s+#endif/);
  assert.match(progress, /Bloomstep visual identity=anchor-action-celebrate-garden; phase=/);
  assert.match(progress, /Bloomstep welcome auto-advanced after /);
  assert.match(progress, /Bloomstep zero-click visual held until /);
  assert.match(progress, /if WizardSilent then Exit/);
});

test('actual compiled proof covers both flows without Finish and never calls static art motion', () => {
  const proof = read('tool/verify_install_progress.ps1');
  assert.match(proof, /\[ValidateSet\('oneclick','zeroclick'\)\]\[string\]\$Flow/);
  for (const field of ['welcomeObserved', 'welcomeToDestinationMilliseconds', 'installClicks',
    'finishPageAbsent', 'automaticLaunch', 'visualFrames', 'visualHoldMilliseconds', 'staticPreference']) {
    assert.ok(proof.includes(field), field);
  }
  assert.match(proof, /Anchor[\s\S]*Action[\s\S]*Celebrate/);
  assert.match(proof, /GetDpiForWindow/);
  assert.match(proof, /GITHUB_ACTIONS/);
  const workflow = read('.github/workflows/ci.yml');
  assert.match(workflow, /\/DInstallFlow=zeroclick/);
  assert.match(workflow, /bloomstep-universal-zeroclick-installer-PRIVATE-EXPERIMENT/);
  assert.match(workflow, /verify_install_progress\.ps1[^\n]*-Flow oneclick/);
  assert.match(workflow, /verify_install_progress\.ps1[^\n]*-Flow zeroclick/);
  const release = workflow.split('  release:')[1];
  assert.doesNotMatch(release, /zeroclick/i, 'zero-click experiment is never released');
  const docs = read('docs/installer-onboarding.md');
  for (const phrase of ['SmartScreen', 'Mark-of-the-Web', 'no UAC', 'Plant a habit', 'zero-click']) {
    assert.ok(docs.includes(phrase), phrase);
  }
});
