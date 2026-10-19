import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('startup failure recovery does not assume an invitation or another window caused it', () => {
  const main = readFileSync(new URL('../lib/main.dart', import.meta.url), 'utf8');
  const failure = main.slice(main.indexOf('} catch (_) {'), main.indexOf('if (Platform.isWindows) {', main.indexOf('} catch (_) {')));
  assert.match(failure, /The app could not start\. Try opening it again\. If this continues, contact support\./);
  assert.match(failure, /No new garden or session was opened\./);
  assert.doesNotMatch(failure, /Use a valid|close an existing/);
  assert.match(failure, /runApp\(/);
  assert.match(failure, /return;/);
});
