import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FileBackedCosmosContainer } from './support/file_backed_cosmos.mjs';

test('disposable store partitions owners, rejects stale writes, and validates batch conflicts atomically across restart', async () => {
  const root = await mkdtemp(join(tmpdir(), 'bloomstep-it-'));
  const path = join(root, 'server.json');
  const ownerA = 'owner-a';
  const ownerB = 'owner-b';
  try {
    let container = await FileBackedCosmosContainer.openFresh(path);
    const first = {
      id: 'same-record-id',
      userId: ownerA,
      type: 'habits',
      record: { id: 'same-record-id', behavior: 'synthetic-a' },
    };
    await container.items.create(first);
    await container.items.create({
      ...first,
      userId: ownerB,
      record: { ...first.record, behavior: 'synthetic-b' },
    });
    const concurrent = {
      id: 'concurrent-create',
      userId: ownerA,
      type: 'habits',
      record: { id: 'concurrent-create' },
    };
    const competingCreates = await Promise.allSettled([
      container.items.create(concurrent),
      container.items.create(concurrent),
    ]);
    assert.equal(
      competingCreates.filter(result => result.status === 'fulfilled').length,
      1,
    );
    assert.equal(
      competingCreates.filter(result => result.status === 'rejected')[0].reason.code,
      409,
    );
    const read = await container.item(first.id, ownerA).read();
    const pending = {
      id: 'pending-record',
      userId: ownerA,
      type: 'habits',
      record: { id: 'pending-record' },
    };
    assert.deepEqual(
      await container.items.batch([
        { operationType: 'Create', resourceBody: pending },
        { operationType: 'Create', resourceBody: first },
      ], ownerA),
      { code: 409 },
    );
    assert.equal(
      (await container.item(pending.id, ownerA).read()).resource,
      undefined,
    );
    await container.item(first.id, ownerA).replace(
      { ...read.resource, record: { ...first.record, behavior: 'edited' } },
      { accessCondition: { condition: read.resource._etag } },
    );
    await assert.rejects(
      container.item(first.id, ownerA).replace(first, {
        accessCondition: { condition: read.resource._etag },
      }),
      error => error.code === 412,
    );
    await container.close();

    container = await FileBackedCosmosContainer.openExisting(path);
    assert.equal(
      (await container.item(first.id, ownerA).read()).resource.record.behavior,
      'edited',
    );
    assert.equal(
      (await container.item(first.id, ownerB).read()).resource.record.behavior,
      'synthetic-b',
    );
    assert.equal(
      (await container.item(pending.id, ownerA).read()).resource,
      undefined,
    );
    assert.doesNotMatch(await readFile(path, 'utf8'), /Bearer|test-auth-key/);
    await container.close();
    await assert.rejects(FileBackedCosmosContainer.openFresh(path));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
