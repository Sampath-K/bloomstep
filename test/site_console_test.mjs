import test from 'node:test';
import assert from 'node:assert/strict';
import { approvedConnection, formatMetric, replyAttempt, metricPanels } from '../site/console.mjs';

test('operator never sends bearer tokens to a different origin', () => {
  assert.equal(approvedConnection('https://example.test', 'aa.bb.cc', 'https://example.test').origin, 'https://example.test');
  for (const origin of ['https://other.test', 'http://example.test', 'https://example.test/path', 'https://user@example.test']) {
    assert.throws(() => approvedConnection(origin, 'aa.bb.cc', 'https://example.test'));
  }
});
test('unknown or suppressed counts are never rendered as zeros', () => {
  assert.equal(formatMetric(null), 'Unavailable / suppressed');
  assert.equal(formatMetric(0), '0');
  assert.throws(() => formatMetric(undefined));
  assert.throws(() => formatMetric(-1));
  assert.throws(() => metricPanels({ daily: [], minimumCohort: 50, limitations: [] }));
});
test('reply retry IDs persist only for the same payload', () => {
  const payload = { id: 'synthetic', status: 'planned', reply: 'Synthetic test' };
  const first = replyAttempt(null, payload, () => 'first');
  assert.equal(replyAttempt(first, payload, () => 'second').requestId, 'first');
  assert.equal(replyAttempt(first, { ...payload, status: 'shipped' }, () => 'second').requestId, 'second');
});
