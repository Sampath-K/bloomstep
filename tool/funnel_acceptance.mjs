// One bounded command for the composed funnel acceptance: telemetry → AARRR report → guarded experiment loop.
// Usage: node tool/funnel_acceptance.mjs --out <fresh dir>
// Exits nonzero if any stage fails, times out, or an independent receipt/segregation assertion fails.
// Scope: isolated synthetic evidence only. The native installer is explicitly excluded (see `excluded` below).
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outIndex = process.argv.indexOf('--out');
if (outIndex < 0 || !process.argv[outIndex + 1]) { console.error('Usage: node tool/funnel_acceptance.mjs --out <fresh dir>'); process.exit(2); }
const out = resolve(process.argv[outIndex + 1]);
if (existsSync(out)) { console.error('--out must be a fresh directory owned by this run.'); process.exit(2); }
await mkdir(out, { recursive: true });

const git = (/** @type {string[]} */ args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const sha256 = (/** @type {Buffer|string} */ data) => createHash('sha256').update(data).digest('hex');
// Windows checkouts rewrite CRLF on site build; only content changes count as source modification.
const tracked = () => git(['diff', '--ignore-cr-at-eol', '--stat', 'HEAD']);
const revision = git(['rev-parse', 'HEAD']);
const dirtyAtStart = tracked();
const shell = process.platform === 'win32' ? (existsSync('C:\\Program Files\\PowerShell\\7\\pwsh.exe') ? 'pwsh' : 'powershell') : 'pwsh';
const stageTimeoutMs = 25 * 60 * 1000;

/** @type {{name:string, command:string[], env?:Record<string,string>, dir:string}[]} */
const stages = [
  { name: 'telemetry-validation', dir: join(out, 'telemetry'),
    command: [shell, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(root, 'tool', 'verify_telemetry.ps1'), '-EvidenceDir', join(out, 'telemetry')] },
  { name: 'aarrr-validation', dir: join(out, 'aarrr'), command: [process.execPath, join(root, 'site', 'verify-aarrr.mjs')],
    env: { EVIDENCE_DIR: join(out, 'aarrr') } },
  { name: 'experiment-loop-validation', dir: join(out, 'experiments'),
    command: [process.execPath, join(root, 'tool', 'experiment_acceptance.mjs'), '--out', join(out, 'experiments')] },
];

function run(/** @type {typeof stages[number]} */ stage) {
  return new Promise(done => {
    const started = Date.now(); let log = '';
    const child = spawn(stage.command[0], stage.command.slice(1), { cwd: root, env: { ...process.env, ...stage.env }, stdio: ['ignore', 'pipe', 'pipe'] });
    const keep = (/** @type {Buffer} */ chunk) => { const text = chunk.toString(); log = (log + text).slice(-200000); process.stdout.write(text); };
    child.stdout.on('data', keep); child.stderr.on('data', keep);
    const timer = setTimeout(() => { log += `\nTIMEOUT after ${stageTimeoutMs} ms`; child.kill(); }, stageTimeoutMs);
    child.on('error', error => { log += `\n${error.message}`; });
    child.on('close', code => { clearTimeout(timer); done({ code: code ?? 1, seconds: Math.round((Date.now() - started) / 1000), log }); });
  });
}

async function evidence(/** @type {string} */ dir) {
  /** @type {Record<string,string>} */ const hashes = {};
  if (!existsSync(dir)) return hashes;
  for (const entry of await readdir(dir, { recursive: true, withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const path = join(entry.parentPath ?? entry.path, entry.name);
    hashes[relative(out, path).replaceAll('\\', '/')] = sha256(await readFile(path));
  }
  return hashes;
}
const json = async (/** @type {string} */ path) => JSON.parse(await readFile(path, 'utf8'));

/** Independent assertions over each stage's own receipts (segregation, synthetic labels, installer exclusion). */
const checks = {
  'telemetry-validation': async (/** @type {string} */ dir) => {
    const receipt = await json(join(dir, 'telemetry-receipt.json')), functional = await json(join(dir, 'functional-acceptance.json'));
    const failures = [];
    if (receipt.passed !== true || receipt.customerAcceptance !== false || receipt.installerExecuted !== false) failures.push('telemetry receipt labels');
    if (functional.passed !== true || functional.customerAcceptance !== false || functional.installerExecuted !== false) failures.push('functional receipt labels');
    if (receipt.sourceRevision !== revision) failures.push('telemetry receipt revision mismatch');
    return { failures, summary: { kind: receipt.kind, stages: receipt.stages, steps: receipt.steps, cleanupVerified: receipt.cleanupVerified } };
  },
  'aarrr-validation': async (/** @type {string} */ dir) => {
    const receipt = await json(join(dir, 'aarrr-receipt.json'));
    const failures = [];
    if (receipt.isolatedSynthetic !== true) failures.push('AARRR receipt not labeled isolated synthetic');
    if (receipt.sourceRevision !== revision) failures.push('AARRR receipt revision mismatch');
    if (JSON.stringify(receipt.oracle?.stages) !== '[150,100,50]' || receipt.oracle?.activationRate !== 0.5 || receipt.oracle?.revenue !== null) failures.push('AARRR oracle mismatch');
    return { failures, summary: { oracle: receipt.oracle, checks: receipt.checks?.length ?? 0 } };
  },
  'experiment-loop-validation': async (/** @type {string} */ dir) => {
    const receipt = await json(join(dir, 'acceptance-receipt.json')), gate = await json(join(dir, 'acceptance-gate-check.json'));
    const report = await json(join(dir, 'acceptance-report-export.json'));
    const failures = [];
    const seg = receipt.segregation ?? {};
    if (receipt.result !== 'passed' || seg.environment !== 'isolated' || seg.productionDocuments !== 0 || seg.syntheticOnly !== true) failures.push('experiment segregation');
    if (receipt.costs?.paidServices?.length !== 0 || receipt.costs?.newBillableResources?.length !== 0 || receipt.costs?.actualHostingBill !== 'not_measured') failures.push('paid/billable dependency recorded');
    if (!receipt.scenarios?.every((/** @type {any} */ row) => row.passed === true) || receipt.scenarios.length < 12) failures.push('experiment scenarios');
    if (gate.tamperedStatus !== 409 || gate.verifiedStatus !== 200) failures.push('server receipt verification');
    if (report.environment !== 'isolated' || report.activeCounts !== null) failures.push('report environment/withholding');
    if (!receipt.limitations?.some((/** @type {string} */ text) => text.includes('Defender-quarantined'))) failures.push('installer quarantine limitation missing');
    return { failures, summary: { receiptSha256: gate.receiptSha256, decisions: report.concluded.map((/** @type {any} */ row) => `${row.key}:${row.decision}`),
      promotions: report.promotions.map((/** @type {any} */ row) => `${row.key}:${row.status}`), scenarios: receipt.scenarios.length } };
  },
};

const results = [];
let failed = false;
for (const stage of stages) {
  console.log(`\n=== STAGE ${stage.name} ===`);
  const before = tracked();
  const result = /** @type {{code:number,seconds:number,log:string}} */ (await run(stage));
  await mkdir(stage.dir, { recursive: true });
  await writeFile(join(out, `${stage.name}.log`), result.log);
  let verdict = { failures: /** @type {string[]} */ ([]), summary: /** @type {any} */ (null) };
  if (result.code !== 0) verdict.failures.push(`exit ${result.code}`);
  else {
    try { verdict = await checks[/** @type {keyof typeof checks} */ (stage.name)](stage.dir); }
    catch (error) { verdict.failures.push(`receipt assertion error: ${/** @type {Error} */ (error).message}`); }
  }
  const after = tracked();
  if (after !== before) verdict.failures.push('stage modified tracked source files');
  const passed = verdict.failures.length === 0;
  failed ||= !passed;
  results.push({ stage: stage.name, passed, exitCode: result.code, seconds: result.seconds, failures: verdict.failures, summary: verdict.summary, evidence: await evidence(stage.dir) });
  console.log(`=== ${passed ? 'PASS' : 'FAIL'} ${stage.name} (${result.seconds}s) ${verdict.failures.join('; ')}`);
}

const sourceFiles = git(['ls-files', 'api/src', 'site/*.mjs', 'site/*.html', 'site/experiment-promotions.json', 'tool/funnel_acceptance.mjs',
  'tool/experiment_acceptance.mjs', 'tool/verify_telemetry.ps1', '.github/workflows/ci.yml', '.github/workflows/aggregates.yml']).split(/\r?\n/).filter(Boolean);
/** @type {Record<string,string>} */ const sources = {};
for (const file of sourceFiles) sources[file] = sha256(await readFile(join(root, file)));

const receipt = {
  schemaVersion: 1, kind: 'bloomstep-composed-funnel-acceptance', passed: !failed, generatedAt: new Date().toISOString(),
  sourceRevision: revision, sourceDirty: dirtyAtStart !== '', platform: `${process.platform}-${process.arch}`, node: process.version,
  stages: results,
  segregation: { syntheticOnly: true, customerData: false, productionWrites: false,
    units: { telemetry: 'anonymous website event counts + synthetic account events', aarrr: 'consented_account (synthetic, isolated)', experiments: 'consented page visit (synthetic, isolated)' },
    note: 'Account, website-event and experiment-visit denominators are separate units and are never joined.' },
  excluded: {
    nativeInstaller: 'Not exercised. PR26 zero-click installer candidate was Defender-quarantined (Behavior:Win32/DefenseEvasion.A!ml) and withdrawn; real install/launch validation remains blocked.',
    liveTraffic: 'No live customer traffic or production efficacy claim; production experiments remain OFF.',
    unsupported: ['sent/referral activation', 'payment/revenue', 'experiment exposure completeness for AARRR eligibility'],
  },
  costs: { declaration: 'run_dependencies_only', paidServices: [], newBillableResources: [], actualHostingBill: 'not_measured' },
  sources,
};
const text = JSON.stringify(receipt, null, 2) + '\n';
await writeFile(join(out, 'composed-receipt.json'), text);
console.log(`\nCOMPOSED ${failed ? 'FAIL' : 'PASS'} revision=${revision} dirty=${receipt.sourceDirty} receipt=${sha256(text)}`);
process.exit(failed ? 1 : 0);
