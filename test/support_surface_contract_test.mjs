import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('native export source wires tested owner preparation, cancellation, save guards and visible partial warning', () => {
  const source = readFileSync(new URL('../lib/features/garden/garden_screen.dart', import.meta.url), 'utf8');
  const start = source.indexOf("title: const Text('Export my data (JSON)')");
  const end = source.indexOf("title: const Text('Check for updates')", start);
  assert.ok(start >= 0 && end > start);
  const exportSource = source.slice(start, end);
  assert.match(exportSource, /if \(target == null\) return;/);
  assert.match(exportSource, /prepareOwnerExport\(/);
  assert.match(exportSource, /refreshStatus\(\s*export: true,\s*\)/);
  assert.match(exportSource, /data = prepared\.data;/);
  assert.match(exportSource, /warnings\.addAll\(prepared\.warnings\)/);
  const save = exportSource.indexOf('.saveTo(target.path)');
  const ownerGuard = exportSource.lastIndexOf('requireSyncSession(owner, generation)');
  assert.ok(ownerGuard > exportSource.indexOf('prepareOwnerExport(') && ownerGuard < save);
  assert.ok(exportSource.indexOf('widget.identity!.account != owner') < save);
  assert.ok(exportSource.indexOf('ScaffoldMessenger.of(this.context).showSnackBar(') > save);
  assert.match(exportSource, /Local export saved\..*not a complete server export/);
});

test('support export does not migrate SQLite or introduce a separate unpurged collector', () => {
  const store = readFileSync(new URL('../lib/core/garden_store.dart', import.meta.url), 'utf8');
  assert.match(store, /version: 5,/);
  assert.match(store, /deletedVoiceIds\(\) => _deletedRecordIds\('voice'\)/);
  assert.doesNotMatch(store, /CREATE TABLE.*(?:support|receipt)/i);
  const backend = readFileSync(new URL('../api/src/backend.mjs', import.meta.url), 'utf8');
  assert.match(backend, /IIF\(IS_ARRAY\(STRINGTOARRAY\(c\.record\.replies\)\) AND NOT EXISTS\(SELECT VALUE r FROM r IN STRINGTOARRAY\(c\.record\.replies\) WHERE NOT IS_STRING\(r\) OR LENGTH\(r\) > 2100\), ARRAY_LENGTH\(STRINGTOARRAY\(c\.record\.replies\)\) > 0, null\) AS hasResponses/);
  const projection = backend.split('async function rawSupport(scan)')[1].split('async function')[0];
  assert.doesNotMatch(projection, /c\.record\.body|SELECT.*c\.record\.replies\s*,/);
  assert.match(readFileSync(new URL('../docs/backend-contracts.md', import.meta.url), 'utf8'),
    /malformed\s+JSON,\s+non-array values,\s+non-string replies or replies over2100 characters yield\s+invalid provenance/);
});

test('public trust notice discloses service support facts separately from optional analytics without filling historical gaps', () => {
  const site = readFileSync(new URL('../site/index.html', import.meta.url), 'utf8');
  assert.match(site, /server receipt and first committed team-reply times/);
  assert.match(site, /Service-operational support records are separate from optional product-event analytics/);
  assert.match(site, /Historical missing times are not backfilled/);
});
