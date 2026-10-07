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
  assert.match(home, /no third-party product analytics scripts/i);
  assert.match(home, /Website measurement is off by default/);
  assert.match(home, /AI features, if added, will be explained and optional/);
});
