import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const readRepositoryFile = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const limited = 'Limited preview — Bloomstep is an early, unsigned Windows app for trying tiny, routine-linked habits, check-ins, and a personal growing garden. Sign-in is required; some features and sign-in options are still being refined. This is not the complete verified MVP, and it is not medical advice. There is no Microsoft Store version yet. If you use the app, private feedback is available in-app after sign-in.';

test('hero sells the small first step without front-loading installer warning language', () => {
  const page = read('index.html');
  const hero = /<section class="hero"[\s\S]*?<\/section>/.exec(page)?.[0];
  assert.ok(hero);
  assert.match(hero, /Make a tiny habit part of your day/);
  assert.match(hero, /Choose a routine, pair it with one small action, and celebrate your moment/);
  assert.match(hero, /Get Bloomstep for Windows/);
  assert.match(hero, /Free Windows download · Limited preview · Sign-in required/);
  assert.doesNotMatch(hero, /unsigned|not the full MVP|engineering preview|Windows protected your PC|SmartScreen/i);
  assert.match(page, /src="\/assets\/sample-garden\.png"[^>]+alt="[^"]+"/);
  assert.match(page, /Isolated synthetic sample garden; example app content, not customer data/);
  assert.equal(readFileSync(new URL('../assets/sample-garden.png', import.meta.url))
    .subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')), true);
  assert.match(page, /id="download-footer-cta"/);
});

test('unsigned installer wording is neutral, factual, safely bounded and linked beside downloads', () => {
  const page = read('index.html');
  assert.match(page, /href="#windows-install-help"[^>]*>Windows installation help before opening the installer/);
  assert.match(page, /<details id="windows-install-help"><summary>Why might Windows ask before opening Bloomstep\?/);
  assert.doesNotMatch(page, /<details id="windows-install-help"[^>]*\bopen/);
  assert.match(page, /This preview installer is not digitally signed, so Windows may show an unknown-publisher\/reputation prompt/);
  assert.match(page, /A warning alone doesn't establish malware, and we cannot guarantee safety/);
  assert.match(page, /Not all unknown programs are malicious/);
  assert.match(page, /known-malicious|known malicious/);
  assert.match(page, /known-malicious or dangerous[\s\S]*blocked by your organization or device policy/);
  assert.match(page, /More info.{0,50}Run anyway/);
  assert.match(page, /Only for an unknown-reputation prompt,[\s\S]*SHA-256 match,[\s\S]*policy permits[\s\S]*accept the risk/);
  assert.match(page, /Cancellation is always an option/);
  assert.doesNotMatch(page, /disable (?:Microsoft Defender )?SmartScreen|turn off (?:Edge|browser|Windows) protection|bypass (?:your |managed )?policy|run as administrator to get past/i);
  assert.match(page, /href="https:\/\/learn\.microsoft\.com\/en-us\/deployedge\/microsoft-edge-security-smartscreen"/);
  assert.match(page, /href="https:\/\/support\.microsoft\.com\/en-us\/edge\/how-can-smartscreen-help-protect-me-in-microsoft-edge"/);
  assert.match(page, /href="https:\/\/support\.mozilla\.org\/en-US\/kb\/where-find-and-manage-downloaded-files-firefox"/);
});

test('installer-warning imagery is never implied without exact public-asset provenance', () => {
  const page = read('index.html');
  const proof = new URL('../assets/edge-preview8-warning-provenance.json', import.meta.url);
  if (existsSync(proof)) {
    const provenance = JSON.parse(readFileSync(proof, 'utf8'));
    const config = JSON.parse(read('customer-config.json'));
    assert.equal(provenance.assetUrl, config.release.x64.url);
    assert.equal(provenance.assetFile, 'Bloomstep-0.1.0-preview.8-windows-x64-setup.exe');
    assert.equal(provenance.sha256, config.release.x64.sha256);
    assert.equal(provenance.product, 'Microsoft Edge');
    assert.match(provenance.edgeVersion, /^\d+\.\d+\.\d+\.\d+$/);
    assert.equal(provenance.warningCategory, 'unknown-reputation');
    assert.ok(provenance.screenshots.length > 0);
    assert.match(page, /edge-preview8-warning\.png/);
  } else {
    assert.doesNotMatch(page, /edge-preview8-warning\.png|actual Edge prompt for the verified preview/);
  }
});

test('Edge observation is exact-asset, policy-gated, non-executing and one-shot', () => {
  const script = readRepositoryFile('tool/capture_edge_warning.mjs');
  const workflow = readRepositoryFile('.github/workflows/ci.yml');
  const safetyGate = script.indexOf('if (!enabled || !policyPageReadable || !allInternetZone || !exemptionsAbsent)');
  const download = script.indexOf('await page.goto(assetUrl');
  assert.ok(safetyGate >= 0 && safetyGate < download);
  assert.equal((script.match(/await page\.goto\(assetUrl/g) ?? []).length, 1);
  assert.match(script, /v0\.1\.0-preview\.8/);
  assert.match(script, /ecd122fd8cc222fc197157595960210ed413e1aa4824c25b24bf3793649e2ae3/);
  assert.match(script, /installerExecuted: false/);
  assert.match(script, /protectionsChanged: false/);
  assert.match(script, /zone === 3/);
  assert.match(script, /policyPageReadStatus/);
  assert.match(script, /edge:\/\/settings\/privacy\/security/);
  assert.match(script, /Protect from harmful sites and downloads/);
  assert.match(script, /microsoftEdgePoliciesAbsent/);
  assert.match(script, /BLOOMSTEP_EDGE_PREFLIGHT_ONLY/);
  assert.match(script, /if \(evidence\.warningCategory === 'unknown-reputation'\)/);
  assert.match(script, /No Keep or other download action was selected/);
  assert.doesNotMatch(script, /--disable-features|--no-sandbox|SmartScreenEnabled\s*[:=]\s*false|Run anyway/i);
  assert.match(workflow, /github\.event_name == 'pull_request' && github\.event\.action == 'opened'/);
  assert.match(workflow, /github\.event_name == 'workflow_dispatch' && inputs\.verify_edge_warning/);
  assert.match(workflow, /!inputs\.verify_edge_warning/);
  assert.match(workflow, /name: edge-download-warning-observation/);
});

test('both customer entry paths disclose the exact limited scope, independence and official learning', () => {
  for (const path of ['index.html', 'releases/index.html']) {
    const page = read(path);
    assert.ok(page.includes(limited), path);
    assert.match(page, /independent app inspired by the Tiny Habits method/);
    assert.match(page, /not affiliated with or endorsed by BJ Fogg or Tiny Habits/);
    assert.match(page, /href="https:\/\/tinyhabits.com"/);
    assert.match(page, /href="https:\/\/tinyhabits.com\/book\/"/);
    assert.doesNotMatch(page, /join (?:our|the) (?:preview|cohort|waitlist)|verified safe|(?:please|you can|you should) disable (?:SmartScreen|Safe Browsing|antivirus)/i);
  }
});

test('download help is static, browser-specific, conditional and honest about illustrations', () => {
  const page = read('index.html');
  assert.match(page, /<details id="download-help">\s*<summary>Need help downloading\?/);
  assert.doesNotMatch(page, /<details id="download-help"[^>]*\bopen/);
  for (const browser of ['Microsoft Edge', 'Google Chrome']) {
    assert.ok(page.includes(browser));
  }
  assert.match(page, /Firefox on Windows/);
  assert.match(page, /Firefox download UI has not been captured/);
  assert.match(page, /Ctrl\+J/);
  assert.match(page, /Illustrative download flow, not a browser screenshot/);
  assert.match(page, /Browser wording and controls vary by version and managed policy/);
  assert.match(page, /does not prove the file is safe or digitally signed/);
  assert.match(page, /If verification fails, stop/);
  assert.match(page, /malware or policy block/);
  assert.match(page, /More info/);
  assert.match(page, /Run anyway/);
  for (const name of ['edge', 'chrome']) {
    assert.match(page, new RegExp(`src="/assets/${name}-downloads\\.png"[^>]+alt="[^"]+"`));
    assert.ok(readFileSync(new URL(`../assets/${name}-downloads.png`, import.meta.url))
      .subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')));
  }
  assert.match(page, /benign sample text file, not a Bloomstep installer/);
  assert.equal((page.match(/Example download view; installer\/security warnings may differ/g) ?? []).length, 2);
  const provenance = JSON.parse(read('assets/download-capture-provenance.json'));
  assert.equal(provenance.sampleName, 'bloomstep-download-help-sample.txt');
  assert.deepEqual(provenance.captures.map(value => value.browser), ['edge','chrome']);
  for (const capture of provenance.captures) {
    assert.ok(page.includes(`${capture.product} ${capture.version}`));
    assert.match(capture.context, /not an installer or security-warning validation/);
    assert.match(capture.version, /^\d+\.\d+\.\d+\.\d+$/);
  }
  assert.match(read('releases/index.html'), /href="\/#download-help"/);
  assert.match(page, /prefers-reduced-motion/);
  assert.match(page, /forced-colors: active/);
});

test('browser screenshots are behind collapsed native disclosure controls by default', () => {
  const page = read('index.html');
  assert.match(page, /<details id="download-help">\s*<summary>Need help downloading\?/);
  assert.doesNotMatch(page, /<details id="download-help"[^>]*\bopen/);
  for (const browser of ['Microsoft Edge', 'Google Chrome']) {
    assert.match(page, new RegExp(`<details><summary>${browser} on Windows</summary>`));
  }
  assert.doesNotMatch(page, /<details[^>]*\bopen(?:\s|>|=)/);
});

test('original teaching illustrations have text alternatives, self-contained vectors and no scripts', () => {
  const home = read('index.html');
  for (const name of ['anchor', 'tiny', 'celebrate']) {
    assert.match(home, new RegExp(`src="/assets/habit-${name}\\.svg"[^>]+alt="[^"]+"`));
    const svg = read(`assets/habit-${name}.svg`);
    assert.match(svg, /<svg[^>]+viewBox=/);
    assert.match(svg, /<title>/);
    assert.doesNotMatch(svg, /<script|<image|href=|https?:\/\/(?!www.w3.org)/);
  }
  assert.doesNotMatch(home, /<iframe|<video|autoplay/);
  assert.match(home, /id="website-consent" type="checkbox">/);
  assert.match(home, /id="receipt-consent" type="checkbox">/);
});

test('product screenshot is a provenance-backed isolated synthetic app capture', () => {
  const proof = JSON.parse(read('assets/sample-garden-provenance.json'));
  const image = readFileSync(new URL('../assets/sample-garden.png', import.meta.url));
  assert.equal(proof.file, 'sample-garden.png');
  assert.equal(proof.syntheticContent, true);
  assert.equal(proof.customerData, false);
  assert.equal(proof.accountOrCloud, false);
  assert.equal(proof.releaseBuild, false);
  assert.equal(proof.captureSource, 'tool/preview.dart');
  assert.equal(proof.sourceRevision, '121a8f6747e0ff2a11fa3e9026838c3d1a7d2f0d');
  assert.equal(proof.workflowRun, 37450083076);
  assert.equal(proof.architecture, 'windows-arm64');
  assert.equal(proof.screenshotSha256, '9c4a8a4d91b141059522f915839f5369477758835bb8a4472271032aa0f76a1c');
  assert.equal(image.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
});
