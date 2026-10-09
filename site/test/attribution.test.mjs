import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyAttribution, createWebObserver } from '../customer.mjs';

test('only fixed campaign labels and known referrer domains survive classification', () => {
  const value = classifyAttribution('https://www.google.com/search?q=private', '?utm_source=newsletter&utm_medium=email&utm_campaign=launch&token=secret', 'https://site.test');
  assert.deepEqual(value, { source: 'campaign', referrerDomain: 'google.com',
    campaignSource: 'newsletter', campaignMedium: 'email', campaignName: 'launch' });
  const unknown = classifyAttribution('https://private.example/path?secret', '?utm_source=alice&utm_medium=email', 'https://site.test');
  assert.equal(unknown.referrerDomain, 'other');
  assert.equal(unknown.campaignSource, 'unknown');
  assert.equal(unknown.source, 'unknown');
  assert.doesNotMatch(JSON.stringify(unknown), /alice|private|secret/);
  assert.equal(classifyAttribution('', '', 'https://site.test').referrerDomain, 'none');
  assert.equal(classifyAttribution('https://site.test/path', '', 'https://site.test').referrerDomain, 'same_origin');
  assert.equal(classifyAttribution('', '?utm_source=newsletter&utm_source=google', 'https://site.test').campaignSource, 'unknown');
});

test('failed upload retries the same observation, concurrent clicks dedup, reset rotates the consent epoch', async () => {
  const sent = [];
  let fail = true;
  const observer = createWebObserver({ source: 'direct', send: async value => {
    sent.push(value);
    if (fail) throw Error('offline');
  } });
  assert.equal(await observer.record('landing_view'), false);
  fail = false;
  await Promise.all([observer.record('landing_view'), observer.record('landing_view')]);
  assert.equal(sent.length, 2);
  assert.equal(sent[0].eventId, sent[1].eventId);
  observer.reset();
  await observer.record('landing_view');
  assert.notEqual(sent[2].eventId, sent[1].eventId);
});
