import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const output = process.env.BLOOMSTEP_EDGE_EVIDENCE_DIR;
const profile = process.env.BLOOMSTEP_EDGE_PROFILE_DIR;
const preflightOnly = process.env.BLOOMSTEP_EDGE_PREFLIGHT_ONLY === 'true';
const config = JSON.parse(await readFile(join(root, 'site', 'customer-config.json'), 'utf8'));
const { url: assetUrl, sha256: expectedHash } = config.release.x64;
const assetFile = 'Bloomstep-0.1.0-preview.8-windows-x64-setup.exe';
if (config.release.tag !== 'v0.1.0-preview.8' ||
    new URL(assetUrl).pathname.split('/').at(-1) !== assetFile ||
    expectedHash !== 'ecd122fd8cc222fc197157595960210ed413e1aa4824c25b24bf3793649e2ae3') {
  throw new Error('Only the hash-pinned public preview.8 x64 installer is in scope.');
}
if (!output || !profile) throw new Error('Isolated evidence and browser profile paths are required.');
if (existsSync(profile) || existsSync(output)) throw new Error('Refusing to reuse an evidence or browser profile path.');
const require = createRequire(join(root, 'site', 'package.json'));
const puppeteer = (await import(pathToFileURL(require.resolve('puppeteer-core')).href)).default;
const edgeCandidates = [
  join(process.env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
];
const edgePath = edgeCandidates.find(existsSync);
if (!edgePath) throw new Error('Microsoft Edge executable was not found on the hosted Windows runner.');
const edgeVersion = execFileSync(
  'powershell.exe',
  ['-NoProfile', '-Command', `(Get-Item -LiteralPath ${JSON.stringify(edgePath)}).VersionInfo.ProductVersion`],
  { encoding: 'utf8' },
).trim();
await mkdir(output, { recursive: false });
await mkdir(profile, { recursive: false });
const downloads = join(profile, 'Downloads');
await mkdir(downloads);
const defaultProfile = join(profile, 'Default');
await mkdir(defaultProfile);
await writeFile(join(defaultProfile, 'Preferences'), JSON.stringify({
  download: { default_directory: downloads, directory_upgrade: true },
}));
const evidence = {
  schemaVersion: 1,
  product: 'Microsoft Edge',
  edgeVersion,
  os: `Windows ${os.release()} ${os.arch()}`,
  workflowRun: process.env.GITHUB_RUN_ID ?? null,
  assetUrl,
  assetFile,
  sha256: expectedHash,
  authenticodeStatus: 'NotSigned',
  protectionsChanged: false,
  installerExecuted: false,
  warningCategory: 'not-yet-observed',
  effectivePolicies: {},
  urlZones: {},
  settings: {},
  observedStrings: [],
  screenshots: [],
};

let browser;
let page;
const screenshot = async name => {
  await page.screenshot({ path: join(output, name), fullPage: true });
  evidence.screenshots.push(name);
};
const deepText = async () => page.evaluate(() => {
  const visit = root => {
    let result = '';
    for (const node of root.childNodes) {
      if (node.nodeType === Node.TEXT_NODE &&
          !node.parentElement?.closest('script,style,template,noscript')) {
        result += `${node.textContent} `;
      } else if (node.nodeType === Node.ELEMENT_NODE &&
          !['SCRIPT', 'STYLE', 'TEMPLATE', 'NOSCRIPT'].includes(node.tagName) &&
          !node.hidden && node.getAttribute('aria-hidden') !== 'true') {
        result += visit(node);
        if (node.shadowRoot) result += visit(node.shadowRoot);
      }
    }
    return result;
  };
  return visit(document.body).replace(/\s+/g, ' ').trim();
});
const parsePolicy = (text, name) => {
  const match = text.match(new RegExp(
    `(?:^|\\s)${name}\\s+(true|false|\\d+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)`,
    'i',
  ));
  return match ? {
    value: match[1].toLowerCase(),
    source: match[2],
    appliesTo: match[3],
    level: match[4],
    status: match[5],
  } : null;
};
const saveEvidence = async () => {
  await writeFile(join(output, 'edge-preview8-warning-provenance.json'),
    `${JSON.stringify(evidence, null, 2)}\n`);
};

try {
  browser = await puppeteer.launch({
    executablePath: edgePath,
    headless: false,
    userDataDir: profile,
    defaultViewport: { width: 1280, height: 900, deviceScaleFactor: 1 },
    args: ['--no-first-run', '--no-default-browser-check'],
  });
  page = await browser.newPage();
  await page.goto('edge://policy/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  let policyText = '';
  for (let attempt = 0; attempt < 20; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 500));
    policyText = await deepText();
    if (/\bReload Policies\b/i.test(policyText) &&
        /\bPolicy Name\b/i.test(policyText) &&
        /\bPolicy Value\b/i.test(policyText) &&
        /\bSource\b/i.test(policyText) &&
        /\bApplies To\b/i.test(policyText) &&
        /\bStatus\b/i.test(policyText)) break;
  }
  evidence.effectivePolicies.policyPageReadStatus =
    /\bReload Policies\b/i.test(policyText) &&
    /\bPolicy Name\b/i.test(policyText) &&
    /\bPolicy Value\b/i.test(policyText) &&
    /\bSource\b/i.test(policyText) &&
    /\bApplies To\b/i.test(policyText) &&
    /\bStatus\b/i.test(policyText) ? 'complete' : 'unavailable';
  const microsoftEdgePolicySection = policyText.match(
    /\bMicrosoft Edge Policies\b([\s\S]*?)(?=\bPolicy Precedence\b|\bExtension Install Policies\b|$)/i,
  )?.[1] ?? '';
  evidence.effectivePolicies.microsoftEdgePoliciesAbsent =
    evidence.effectivePolicies.policyPageReadStatus === 'complete' &&
    /\bNo policies set\b/i.test(microsoftEdgePolicySection);
  for (const name of [
    'SmartScreenEnabled',
    'SmartScreenPuaEnabled',
    'SmartScreenForTrustedDownloadsEnabled',
    'DownloadRestrictions',
  ]) evidence.effectivePolicies[name] = parsePolicy(policyText, name);
  evidence.effectivePolicies.downloadExemptionRulesPresent =
    /\bExemptSmartScreenDownloadWarnings\b/.test(policyText);
  evidence.effectivePolicies.trustedDownloadDomainsPresent =
    /\bSmartScreenTrustedDownloadDomains\b/.test(policyText);
  await screenshot('edge-policy-page.png');

  await page.goto('edge://settings/privacy/security', { waitUntil: 'domcontentloaded', timeout: 30000 });
  const accessibility = await page.createCDPSession();
  await accessibility.send('Accessibility.enable');
  let smartScreenSwitch;
  let nodes = [];
  for (let attempt = 0; attempt < 20; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 500));
    ({ nodes } = await accessibility.send('Accessibility.getFullAXTree'));
    smartScreenSwitch = nodes.find(node =>
      node.role?.value === 'switch' &&
      /^Protect from harmful sites and downloads$/i.test(node.name?.value?.trim() ?? ''),
    );
    if (smartScreenSwitch) break;
  }
  const checkedProperty = smartScreenSwitch?.properties?.find(property => property.name === 'checked');
  const smartScreenChecked = checkedProperty?.value?.value;
  const disabledProperty = smartScreenSwitch?.properties?.find(property => property.name === 'disabled');
  const smartScreenDisabled = disabledProperty?.value?.value;
  evidence.settings.smartScreenSwitchFound = Boolean(smartScreenSwitch);
  evidence.settings.smartScreenEnabled =
    smartScreenChecked === true || smartScreenChecked === 'true' ? true :
      smartScreenChecked === false || smartScreenChecked === 'false' ? false : null;
  evidence.settings.smartScreenSwitchLabel = smartScreenSwitch?.name?.value ?? null;
  evidence.settings.smartScreenSwitchDisabled =
    smartScreenDisabled === true || smartScreenDisabled === 'true';
  const enforcedSetting = evidence.effectivePolicies.SmartScreenEnabled?.value;
  evidence.settings.smartScreenEnforcementSource = smartScreenSwitch
    ? 'accessibility-switch'
    : enforcedSetting === 'true' ? 'effective-policy' : 'unconfirmed';
  await screenshot('edge-protection-settings.png');

  const zoneScript = join(root, 'tool', 'map_windows_url_zone.ps1');
  for (const host of [
    'https://github.com/',
    'https://release-assets.githubusercontent.com/',
    'https://objects.githubusercontent.com/',
  ]) {
    const value = execFileSync(
      'powershell.exe',
      ['-NoProfile', '-File', zoneScript, '-Url', host],
      { encoding: 'utf8' },
    ).trim();
    evidence.urlZones[new URL(host).hostname] = Number(value);
  }

  const smartScreenEnabled = evidence.settings.smartScreenSwitchFound
    ? evidence.settings.smartScreenEnabled === true
    : enforcedSetting === 'true';
  const policyPageReadable = evidence.effectivePolicies.policyPageReadStatus === 'complete';
  const enabled = smartScreenEnabled && policyPageReadable &&
    evidence.effectivePolicies.SmartScreenEnabled?.value !== 'false' &&
    evidence.effectivePolicies.SmartScreenPuaEnabled?.value !== 'false' &&
    (evidence.effectivePolicies.DownloadRestrictions?.value === '0' ||
      evidence.effectivePolicies.DownloadRestrictions === null);
  const allInternetZone = Object.values(evidence.urlZones).every(zone => zone === 3);
  const exemptionsAbsent = policyPageReadable &&
    !evidence.effectivePolicies.downloadExemptionRulesPresent &&
    !evidence.effectivePolicies.trustedDownloadDomainsPresent;
  if (!enabled || !policyPageReadable || !allInternetZone || !exemptionsAbsent) {
    evidence.warningCategory = 'capture-stopped-before-download';
    evidence.outcome = 'SmartScreen protection, a complete effective-policy read, Internet-zone classification, or absence of download exemptions could not be confirmed. No installer request was made.';
    await saveEvidence();
    throw Object.assign(new Error(evidence.outcome), { safeStop: true });
  }

  if (preflightOnly) {
    evidence.warningCategory = 'preflight-only';
    evidence.outcome = 'Read-only preflight confirmed protections, the complete policy table and Internet zones. No installer request was made.';
    await saveEvidence();
    throw Object.assign(new Error(evidence.outcome), { safeStop: true });
  }

  await page.goto(assetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(error => {
    if (!/ERR_ABORTED|Download is starting|net::ERR_ABORTED/i.test(error.message)) throw error;
  });
  await page.goto('edge://downloads/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  const deadline = Date.now() + 60000;
  let text = '';
  do {
    await new Promise(resolve => setTimeout(resolve, 750));
    text = await deepText();
    if (text.includes(assetFile)) break;
  } while (Date.now() < deadline);

  evidence.observedStrings = [...new Set(text.split(/\s{2,}|\n/)
    .map(value => value.trim()).filter(value => value && value.length < 400))];
  const dangerous = /malicious|virus|dangerous|unsafe|may harm your device|blocked by your organization|blocked by your administrator|your organization.{0,40}blocked|managed by your organization/i.test(text);
  const unknownReputation = /uncommon download|not commonly downloaded|unknown reputation|unknown publisher|doesn't have a known footprint|does not have a known footprint|can't be verified|can't verify/i.test(text);
  const securityMessage = /warning|blocked|danger|unsafe|reputation|uncommon|malicious|virus|harm your device|verify this file/i.test(text);
  if (dangerous) evidence.warningCategory = 'dangerous-or-managed-policy-block';
  else if (unknownReputation) evidence.warningCategory = 'unknown-reputation';
  else if (text.includes(assetFile) && !securityMessage) evidence.warningCategory = 'no-warning-observed';
  else if (securityMessage) evidence.warningCategory = 'unclassified-warning';
  else evidence.warningCategory = 'download-not-listed';
  await screenshot('edge-download-initial.png');

  if (evidence.warningCategory === 'unknown-reputation') {
    const actions = await page.evaluate(() => {
      const result = [];
      const visit = root => {
        for (const element of root.querySelectorAll('*')) {
          if (element.shadowRoot) visit(element.shadowRoot);
          if (!element.matches('button,cr-button,cr-icon-button,[role=button]')) continue;
          const label = [element.getAttribute('aria-label'), element.getAttribute('title'),
            element.innerText, element.textContent].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
          if (label) result.push({ element, label, disabled: Boolean(element.disabled) ||
            element.getAttribute('aria-disabled') === 'true' });
        }
      };
      visit(document);
      return result.filter(action => /more actions|more options/i.test(action.label) && !action.disabled)
        .map(action => action.label);
    });
    const more = actions[0];
    if (more) {
      await page.evaluate(label => {
        const visit = root => {
          for (const element of root.querySelectorAll('*')) {
            const text = [element.getAttribute('aria-label'), element.getAttribute('title'),
              element.innerText, element.textContent].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
            if (element.matches('button,cr-button,cr-icon-button,[role=button]') && text === label) {
              element.click();
              return true;
            }
            if (element.shadowRoot && visit(element.shadowRoot)) return true;
          }
          return false;
        };
        return visit(document);
      }, more);
      await new Promise(resolve => setTimeout(resolve, 300));
      const menu = await deepText();
      evidence.menuOffersKeep = /\bKeep\b/i.test(menu);
      if (evidence.menuOffersKeep) {
        evidence.observedStrings = [...new Set([...evidence.observedStrings,
          ...menu.split(/\s{2,}|\n/).map(value => value.trim()).filter(value => /\bKeep\b/.test(value))])];
        await screenshot('edge-download-menu.png');
      }
    }
    evidence.outcome = 'Captured the observed reputation prompt and available details menu only. No Keep or other download action was selected.';
  } else if (dangerous) {
    evidence.outcome = 'Captured a dangerous-file or managed-policy block and stopped without opening actions or overriding it.';
  } else if (evidence.warningCategory === 'unclassified-warning') {
    evidence.outcome = 'Captured a security-related Edge message that was not classified. No actions were opened or selected.';
  } else if (evidence.warningCategory === 'no-warning-observed') {
    evidence.outcome = 'Captured the completed download without a warning. This is not warning evidence.';
  } else {
    evidence.outcome = 'No completed download entry or classifiable warning appeared during the bounded wait.';
  }

  const downloadedPath = join(downloads, assetFile);
  if (existsSync(downloadedPath)) {
    const bytes = await readFile(downloadedPath);
    evidence.downloadedSha256 = createHash('sha256').update(bytes).digest('hex');
    evidence.downloadMatchesPublishedHash = evidence.downloadedSha256 === expectedHash;
  }
  await saveEvidence();
} catch (error) {
  if (!error.safeStop) {
    evidence.warningCategory = 'capture-error';
    evidence.outcome = error.message;
    await saveEvidence();
    throw error;
  }
} finally {
  if (browser) await browser.close();
  await rm(profile, { recursive: true, force: true });
}
