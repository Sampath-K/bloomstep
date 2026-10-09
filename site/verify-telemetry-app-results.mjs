import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { linkedWebFunnel } from '../api/src/website-funnel.mjs';
import { normalizedEvents, dashboardSummaries } from '../api/src/dashboards.mjs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

if (!process.env.EVIDENCE_DIR) throw Error('EVIDENCE_DIR required.');
const dir = process.env.EVIDENCE_DIR;
const raw = await readFile(join(dir, 'app-events.json'));
const receipt = JSON.parse(await readFile(join(dir, 'app-telemetry-receipt.json'), 'utf8'));
assert.equal(receipt.eventsSha256, createHash('sha256').update(raw).digest('hex'));
assert.equal(receipt.passed, true);
assert.equal(receipt.cleanupVerified, true);
assert.equal(receipt.receiptOrigin, 'browser_export', 'Functional harness must consume the actual browser export, never the unit fixture.');
const rows = JSON.parse(raw), events = normalizedEvents(rows);
assert.equal(events.length, receipt.persistedEvents);
assert.equal(events.filter(row => row.record.name === 'first_checkin' && row.record.properties.result === 'did').length, 1);
assert.equal(events.filter(row => row.record.name === 'download_click').length, 1);
const dates = events.map(row => row.record.ts.slice(0, 10)).sort();
const start = dates[0], end = dates.at(-1);
const linked = linkedWebFunnel(rows, start, end);
assert.equal(linked.stages.install_completed, null, 'Browser export never proves installation.');
assert.equal(linked.stages.first_launch, null);
assert.equal(linked.stages.signin_succeeded, null, 'Missing installer chain must not invent conversion.');
const summary = dashboardSummaries(rows, start, end, end);
assert.equal(summary.funnel.stages.first_checkin.users, null, 'One synthetic account must not defeat publication threshold.');
const sourceHashes = {};
for (const path of ['lib/core/garden_store.dart', 'lib/core/measurement_receipt.dart', 'lib/services/sync_service.dart',
  'test/telemetry_http_test.dart', 'integration_test/support/local_test_api.dart', 'integration_test/support/test_only_app.dart',
  'api/src/backend.mjs', 'api/src/dashboards.mjs', 'site/verify-telemetry-app-results.mjs', 'tool/verify_telemetry.ps1']) {
  sourceHashes[path] = createHash('sha256').update(await readFile(new URL('../' + path, import.meta.url))).digest('hex');
}
await writeFile(join(dir, 'app-computed-results.json'), JSON.stringify({ schemaVersion: 1,
  kind: 'isolated-synthetic-persisted-event-report', customerAcceptance: false,
  sourceHashes,
  eventCount: events.length, linked, summary }, null, 2), { flag: 'wx' });
const artifacts = {};
for (const name of ['telemetry-receipt.json', 'computed-reports.json', 'website-receipt.json', 'app-events.json',
  'app-telemetry-receipt.json', 'app-computed-results.json', 'default-off.png', 'consented-observations.png']) {
  artifacts[name] = createHash('sha256').update(await readFile(join(dir, name))).digest('hex');
}
await writeFile(join(dir, 'functional-acceptance.json'), JSON.stringify({ schemaVersion: 1, passed: true,
  kind: 'isolated-synthetic-functional-acceptance', customerAcceptance: false, installerExecuted: false,
  sourceRevision: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: fileURLToPath(new URL('../', import.meta.url)), encoding: 'utf8' }).trim(),
  artifacts, sourceHashes, cleanupVerified: true }, null, 2), { flag: 'wx' });
process.stdout.write('Independent app persisted-event report assertions passed; missing installation remains unknown.\n');
