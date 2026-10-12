import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const categorical = /\bno (?:hosted )?ai\b|\bno ads\b|\bad-free\b/i;

test('customer surfaces and current product documents make bounded privacy claims, not categorical feature promises', () => {
  const paths = ['site/index.html', 'site/releases/index.html', 'packaging/bloomstep.iss',
    'lib/features/garden/garden_screen.dart', 'README.md', 'CHANGELOG.md',
    ...readdirSync(join(root, 'docs')).filter(name => name.endsWith('.md')).map(name => `docs/${name}`)];
  for (const path of paths) {
    const text = readFileSync(join(root, path), 'utf8');
    assert.doesNotMatch(text, categorical, path);
  }
  const home = readFileSync(join(root, 'site/index.html'), 'utf8');
  assert.match(home, /habit text is never sold or used for ads/i);
  assert.match(home, /public website does not use third-party product analytics/i);
  assert.match(home, /separate testing website uses Google Analytics only when its tester chooses to allow it/i);
  assert.match(home, /Early preview — not yet verified for general use/);
  assert.match(home, /owner-test candidate, not a general customer release/);
  assert.match(home, /Website measurement is off by default/);
  assert.match(home, /does not include AI features; any future AI feature would be explained and optional/);
});
