/** @param {Record<string, string | undefined>} settings */
export function storageTarget(settings) {
  const database = settings.COSMOS_DATABASE_NAME;
  const container = settings.COSMOS_CONTAINER_NAME;
  const mode = settings.BLOOMSTEP_SYNTHETIC_ACCEPTANCE;
  if (mode !== undefined && mode !== 'enabled') {
    throw new Error('Invalid storage target: synthetic acceptance must be explicitly enabled or unset.');
  }
  if (database === undefined && container === undefined && mode === undefined) {
    return { database: 'bloomstep', container: 'data' };
  }
  const validName = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/;
  if (!database || !container || !validName.test(database) || !validName.test(container)) {
    throw new Error('Invalid storage target: explicit valid database and container names are required together.');
  }
  if (mode === 'enabled' &&
      (!database.startsWith('synthetic-') || !container.startsWith('synthetic-'))) {
    throw new Error('Invalid storage target: acceptance requires synthetic-only database and container names.');
  }
  return { database, container };
}
