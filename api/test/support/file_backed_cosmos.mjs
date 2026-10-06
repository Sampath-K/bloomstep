import { randomUUID } from 'node:crypto';
import { access, mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, normalize, relative, sep } from 'node:path';

const clone = value => value === undefined ? undefined : structuredClone(value);
const conflict = code => Object.assign(new Error('Test store concurrency conflict.'), { code });

export class FileBackedCosmosContainer {
  #documents = new Map();
  #revision = 0;
  #tail = Promise.resolve();

  constructor(path) {
    this.path = path;
    this.item = (id, partition) => ({
      read: async () => ({ resource: clone(this.#read(id, partition)) }),
      replace: (document, options = {}) => this.#mutate(async () => {
        const current = this.#read(id, partition);
        if (!current || options.accessCondition?.condition !== current._etag) throw conflict(412);
        return { resource: this.#put(document) };
      }),
      delete: () => this.#mutate(async () => {
        this.#documents.delete(this.#key(id, partition));
      }),
    });
    this.items = {
      create: document => this.#mutate(async () => {
        if (this.#read(document.id, document.userId)) throw conflict(409);
        return { resource: this.#put(document) };
      }),
      batch: (operations, partition) => this.#mutate(async () => {
        for (const operation of operations) {
          const id = operation.id ?? operation.resourceBody?.id;
          const current = this.#read(id, partition);
          if (operation.operationType === 'Create' && current) return { code: 409 };
          if (operation.operationType === 'Replace' &&
              (!current || current._etag !== operation.ifMatch)) return { code: 412 };
          if (!['Create', 'Replace', 'Delete'].includes(operation.operationType)) {
            throw new Error('Unsupported test-store batch operation.');
          }
        }
        for (const operation of operations) {
          const id = operation.id ?? operation.resourceBody?.id;
          if (operation.operationType === 'Delete') this.#documents.delete(this.#key(id, partition));
          else this.#stage(operation.resourceBody);
        }
        return { code: 200 };
      }),
      query: (spec, options = {}) => ({
        fetchAll: async () => ({ resources: this.#query(spec, options) }),
      }),
    };
  }

  static async openFresh(path) {
    const fullPath = normalize(path);
    if (!isAbsolute(fullPath)) throw new Error('Disposable test store path must be absolute.');
    await mkdir(dirname(fullPath), { recursive: true });
    try {
      await access(fullPath);
      throw new Error('Disposable test store already exists.');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    const store = new FileBackedCosmosContainer(fullPath);
    await store.#persist();
    return store;
  }

  static async openExisting(path) {
    const fullPath = normalize(path);
    if (!isAbsolute(fullPath)) throw new Error('Disposable test store path must be absolute.');
    const parsed = JSON.parse(await readFile(fullPath, 'utf8'));
    if (parsed?.schemaVersion !== 1 ||
        !Number.isSafeInteger(parsed.revision) ||
        parsed.revision < 0 ||
        !Array.isArray(parsed.documents)) {
      throw new Error('Disposable test store is invalid.');
    }
    const store = new FileBackedCosmosContainer(fullPath);
    store.#revision = parsed.revision;
    for (const document of parsed.documents) {
      if (!document ||
          typeof document.id !== 'string' ||
          typeof document.userId !== 'string' ||
          typeof document._etag !== 'string' ||
          store.#documents.has(store.#key(document.id, document.userId))) {
        throw new Error('Disposable test store is invalid.');
      }
      store.#documents.set(store.#key(document.id, document.userId), clone(document));
    }
    return store;
  }

  #key(id, partition) {
    return `${partition}/${id}`;
  }

  #read(id, partition) {
    return this.#documents.get(this.#key(id, partition));
  }

  #put(document) {
    this.#stage(document);
    return clone(this.#read(document.id, document.userId));
  }

  #stage(document) {
    const saved = clone({ ...document, _etag: String(++this.#revision) });
    this.#documents.set(this.#key(saved.id, saved.userId), saved);
  }

  #serialize(operation) {
    const result = this.#tail.then(operation);
    this.#tail = result.then(() => undefined, () => undefined);
    return result;
  }

  #mutate(operation) {
    return this.#serialize(async () => {
      const previousDocuments = this.#documents;
      const previousRevision = this.#revision;
      this.#documents = new Map(previousDocuments);
      try {
        const result = await operation();
        if (result?.code === 409 || result?.code === 412) return result;
        await this.#persist();
        return result;
      } catch (error) {
        this.#documents = previousDocuments;
        this.#revision = previousRevision;
        throw error;
      }
    });
  }

  async #persist() {
    const temporary = `${this.path}.${randomUUID()}.pending`;
    const contents = JSON.stringify({
      schemaVersion: 1,
      revision: this.#revision,
      documents: [...this.#documents.values()],
    });
    try {
      await writeFile(temporary, contents, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
      await rename(temporary, this.path);
    } catch (error) {
      try {
        await unlink(temporary);
      } catch (cleanupError) {
        if (cleanupError.code !== 'ENOENT') {
          throw new AggregateError(
            [error, cleanupError],
            'Test-store persistence and temporary-file cleanup both failed.',
          );
        }
      }
      throw error;
    }
  }

  #query(spec, options) {
    const query = spec?.query;
    if (typeof query !== 'string') throw new Error('Unsupported test-store query.');
    const parameters = Object.fromEntries((spec.parameters ?? []).map(item => [item.name, item.value]));
    let rows = [...this.#documents.values()];
    if (options.partitionKey) rows = rows.filter(row => row.userId === options.partitionKey);

    if (query.includes('c.type IN ("habits","checkins","reflections","voice","settings")')) {
      const types = new Set(['habits', 'checkins', 'reflections', 'voice', 'settings']);
      rows = rows.filter(row => types.has(row.type) && row.userId === parameters['@u']);
    } else if (query.includes('c.type != "account"') && parameters['@target'] !== undefined) {
      const target = parameters['@target'];
      const type = parameters['@targetType'];
      rows = rows.filter(row => row.userId === parameters['@u'] && row.type !== 'account' && (
        row.type === type && row.record?.id === target ||
        type === 'habits' && (row.record?.habitId === target || row.record?.properties?.habitId === target) ||
        type === 'voice' && row.type === 'audit' && row.targetId === target
      ));
    } else if (query.includes('c.type != "account"')) {
      rows = rows.filter(row => row.userId === parameters['@u'] && row.type !== 'account');
    } else if (query.includes('c.type = "events"')) {
      rows = rows.filter(row => row.type === 'events' &&
        (!parameters['@start'] || row.record?.ts >= parameters['@start']) &&
        (!parameters['@end'] || row.record?.ts < parameters['@end']));
    } else if (query.includes('c.type = "account"')) {
      rows = rows.filter(row => row.type === 'account');
    } else if (query.includes('c.type = "aggregate"')) {
      rows = rows.filter(row => row.type === 'aggregate');
    } else if (query.includes('c.type = "voice"')) {
      rows = rows.filter(row => row.type === 'voice');
    } else if (query.includes('c.type = "invitation_receipt"')) {
      rows = rows.filter(row => row.type === 'invitation_receipt');
    } else if (query.includes('c.type = "referral_reward"')) {
      rows = rows.filter(row => row.type === 'referral_reward');
    } else if (query.includes('c.type = "invitation_secret"')) {
      rows = rows.filter(row => row.type === 'invitation_secret');
    } else {
      throw new Error('Test store rejected an unsupported Cosmos query.');
    }

    rows.sort((a, b) => String(a.userId).localeCompare(String(b.userId)) || String(a.id).localeCompare(String(b.id)));
    if (parameters['@after']) rows = rows.filter(row => `${row.userId}:${row.id}` > parameters['@after']);
    const top = Number(/TOP\s+(\d+)/i.exec(query)?.[1] ?? rows.length);
    const projection = query.includes('AS kind')
      ? rows.map(row => ({
        userId: row.userId,
        id: row.id,
        kind: row.record?.kind,
        rating: row.record?.rating,
        support: row.support,
        hasResponses: Array.isArray(JSON.parse(row.record?.replies ?? '[]')) &&
          JSON.parse(row.record?.replies ?? '[]').length > 0,
      }))
      : rows;
    return clone(projection.slice(0, top));
  }

  async close() {
    await this.#tail;
  }
}

export function isWithinDisposableTestDirectory(databasePath) {
  const root = normalize(dirname(databasePath));
  const temp = normalize(tmpdir());
  if (!temp || !isAbsolute(root)) return false;
  const relativePath = relative(temp, root);
  return relativePath !== '' &&
    relativePath !== '..' &&
    !relativePath.startsWith(`..${sep}`) &&
    !isAbsolute(relativePath) &&
    root.split(sep).at(-1)?.startsWith('bloomstep-it-') === true;
}
