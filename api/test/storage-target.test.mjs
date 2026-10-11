import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { storageTarget } from '../src/storage-target.mjs';

test('production storage defaults remain bloomstep/data', () => {
  assert.deepEqual(storageTarget({}), { database: 'bloomstep', container: 'data' });
});

test('explicit paired storage names select only that target', () => {
  assert.deepEqual(storageTarget({
    COSMOS_DATABASE_NAME: 'alternate', COSMOS_CONTAINER_NAME: 'records',
  }), { database: 'alternate', container: 'records' });
});

test('synthetic acceptance requires explicit synthetic-only names with no production fallback', () => {
  const enabled = { BLOOMSTEP_SYNTHETIC_ACCEPTANCE: 'enabled' };
  for (const names of [
    {},
    { COSMOS_DATABASE_NAME: 'synthetic-pr34' },
    { COSMOS_CONTAINER_NAME: 'synthetic-data' },
    { COSMOS_DATABASE_NAME: 'bloomstep', COSMOS_CONTAINER_NAME: 'data' },
    { COSMOS_DATABASE_NAME: 'bloomstep', COSMOS_CONTAINER_NAME: 'synthetic-data' },
    { COSMOS_DATABASE_NAME: 'synthetic-pr34', COSMOS_CONTAINER_NAME: 'data' },
    { COSMOS_DATABASE_NAME: 'alternate', COSMOS_CONTAINER_NAME: 'records' },
  ]) {
    assert.throws(() => storageTarget({ ...enabled, ...names }), /storage target/i);
  }
  assert.deepEqual(storageTarget({
    ...enabled, COSMOS_DATABASE_NAME: 'synthetic-pr34', COSMOS_CONTAINER_NAME: 'synthetic-data',
  }), { database: 'synthetic-pr34', container: 'synthetic-data' });
});

test('partial, empty, invalid and ambiguous settings fail closed', () => {
  for (const settings of [
    { COSMOS_DATABASE_NAME: 'alternate' },
    { COSMOS_CONTAINER_NAME: 'records' },
    { COSMOS_DATABASE_NAME: '', COSMOS_CONTAINER_NAME: '' },
    { COSMOS_DATABASE_NAME: '../bloomstep', COSMOS_CONTAINER_NAME: 'data' },
    { COSMOS_DATABASE_NAME: ' bloomstep', COSMOS_CONTAINER_NAME: 'data' },
    { COSMOS_DATABASE_NAME: 'a'.repeat(65), COSMOS_CONTAINER_NAME: 'data' },
    { BLOOMSTEP_SYNTHETIC_ACCEPTANCE: 'true' },
    { BLOOMSTEP_SYNTHETIC_ACCEPTANCE: '' },
  ]) {
    assert.throws(() => storageTarget(settings), /storage target/i);
  }
});

test('real entrypoint binds the explicit synthetic target and rejects unsafe startup before storage access', () => {
  const script = `
    import azureFunctions from '@azure/functions';
    import { CosmosClient } from '@azure/cosmos';
    const selections = [];
    let registrations = 0;
    azureFunctions.app.http = () => { registrations++; };
    CosmosClient.prototype.database = function(database) {
      return { container(container) { selections.push({database, container}); return {}; } };
    };
    process.env.COSMOS_CONNECTION_STRING = 'AccountEndpoint=https://database.example.invalid/;AccountKey=' + Buffer.alloc(32).toString('base64') + ';';
    process.env.BLOOMSTEP_SYNTHETIC_ACCEPTANCE = 'enabled';
    const safe = process.argv[1] === 'safe';
    process.env.COSMOS_DATABASE_NAME = safe ? 'synthetic-pr34' : 'bloomstep';
    process.env.COSMOS_CONTAINER_NAME = safe ? 'synthetic-data' : 'data';
    let rejected = false;
    try { await import('./src/functions.mjs'); }
    catch(error) {
      if (!error.message.includes('Invalid storage target')) throw error;
      rejected = true;
    }
    console.log(JSON.stringify({ selections, registrations, rejected }));
  `;
  for (const mode of ['safe', 'unsafe']) {
    const result = JSON.parse(execFileSync(process.execPath, ['--input-type=module', '-e', script, mode], {
      cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 30000,
    }));
    assert.deepEqual(result, mode === 'safe'
      ? { selections: [{ database: 'synthetic-pr34', container: 'synthetic-data' }], registrations: 21, rejected: false }
      : { selections: [], registrations: 0, rejected: true });
  }
});
