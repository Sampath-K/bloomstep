import test from 'node:test';
import assert from 'node:assert/strict';
import { experimentPanels } from '../experiment-panels.mjs';

const base = {
  schemaVersion: 1, environment: 'production', policyHash: 'a'.repeat(64), enabled: false, reason: 'production_disabled', killed: false,
  active: null, activeCounts: null, activeCountsWithheld: false, concluded: [], promotions: [], audit: [], catalog: ['download-heading-v1'],
  definition: 'Unit: consented website visit.',
};

test('production OFF renders explicit off state, empty history and no fabricated counts', () => {
  const text = JSON.stringify(experimentPanels(base));
  assert.match(text, /Off \(production_disabled\)/);
  assert.match(text, /No concluded experiments/);
  assert.match(text, /no live efficacy claim/);
});

test('active experiment counts stay withheld and malformed or count-leaking reports fail closed', () => {
  const text = JSON.stringify(experimentPanels({ ...base, enabled: true, active: { experimentId: 'x.1', endAt: '2026-10-15T00:00:00.000Z' }, activeCountsWithheld: true }));
  assert.match(text, /Withheld until the pre-registered final analysis/);
  assert.throws(() => experimentPanels({ ...base, activeCounts: { control: 1 } }), /Incomplete experiment report/);
  assert.throws(() => experimentPanels({ ...base, policyHash: 'x' }), /Incomplete experiment report/);
  assert.throws(() => experimentPanels(null), /Incomplete experiment report/);
});

test('concluded decisions render with uncertainty and isolated environment is labeled synthetic', () => {
  const text = JSON.stringify(experimentPanels({ ...base, environment: 'isolated', concluded: [{ key: 'k', experimentId: 'k.1', decision: 'rollback_harm',
    stats: { p0: 0.3, p1: 0.1, ci95: [-0.25, -0.15] } }] }));
  assert.match(text, /synthetic, not customers/);
  assert.match(text, /Rolled back: pre-registered harm look; control 30.0% vs candidate 10.0%; 95% CI of difference -25.0% to -15.0%/);
});
