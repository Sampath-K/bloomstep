import { createRequire } from 'node:module';

const require = createRequire(new URL('../api/package.json', import.meta.url));
const { CosmosClient } = require('@azure/cosmos');
if (!process.env.COSMOS_CONNECTION_STRING || !process.argv.includes('--confirm-empty')) {
  throw new Error('Set the approved database connection in memory and pass --confirm-empty. No secrets are printed.');
}
const data = new CosmosClient(process.env.COSMOS_CONNECTION_STRING).database('bloomstep').container('data');
const existing = (await data.item('budget', '__preview_budget').read()).resource;
if (existing) {
  console.log('Existing preview budget preserved; no counters reset.');
} else {
  const { resources } = await data.items.query('SELECT VALUE COUNT(1) FROM c').fetchAll();
  if (resources[0] !== 0) {
    throw new Error('Database is not empty. Establish a reviewed historical baseline before admission; never silently initialize usage to zero.');
  }
  const day = new Date().toISOString().slice(0, 10);
  const actions = Object.fromEntries(['metrics_read', 'feedback_read', 'feedback_reply']
    .map(name => [name, { day, daily: 0, lifetime: 0 }]));
  await data.items.create({
    id: 'budget', userId: '__preview_budget', type: 'budget', ttl: -1,
    operations: 1000, records: 100, accounts: 10, day, daily: 0, actions,
  });
  console.log('Empty database census verified. Conservative preview headroom reserved: 1000 operations, 100 documents, 10 account slots. This is a volume guard, not an Azure spending cap.');
}
