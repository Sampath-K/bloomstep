import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const expectedSources = [
  '2f3a4ffd0e8c1192d7fb38a53f127649849453dd32b0df61b44402a888d319e1',
  '069f4a96060d4716ce0286f9079dc0e105a3c5be7be3ec921d7d19d4a004ecb2',
  '53e89b0e7aaa9c91f64eb651ae89fb055e8b241e678fa52f801d05a313a6a391',
  '4415aa34880c5e4b8784de6f2ed6b42d084b853c84c6630106c596652eb9fe42',
  '29a4a289f74c4343bf31b2ae4a8da3e95ed336e11506439108225945fce4ee55',
];
const expectedTransforms = [
  [[32, 102, 541, 354], 'e396f0580452e1ae88efaf5343fc17c8f3dc115bc9142a8acca0bf2a412d05ba'],
  [[7, 0, 293, 300], '2035bff84a40a5098914709c89520280f3f81f2ff198b8b46efcc6ac81931df2'],
  [[0, 4, 529, 733], 'e1522e80c17a245b67e70ae7ee7d1e3365f9b5a9afb48e045e794917bd6d9c61'],
  [[4, 1, 798, 746], 'cb0e35ef40092694fa2deb12da379280a919b86cd57420fab25cbce4f605b3d5'],
  [[0, 4, 798, 746], '89fcf9812b4c0cfc93e41a3914fbbe40ec09f11e44c471007c8115c5cc3c5481'],
];

test('five actual customer warning images preserve source and transformed hashes with private-region provenance', () => {
  const raw = read('assets/customer-warning-provenance.json');
  const proof = JSON.parse(raw);
  assert.equal(proof.captureSource, 'customer-provided screenshots');
  assert.equal(proof.release, '0.1.0-preview.8');
  assert.equal(proof.architecture, 'arm64');
  assert.equal(proof.browserVersion, null);
  assert.equal(proof.osVersion, null);
  assert.equal(proof.ciCapture, false);
  assert.equal(proof.binaryHashEstablished, false);
  assert.equal(proof.executionSuccessEstablished, false);
  assert.equal(proof.appAcceptanceEstablished, false);
  assert.equal(proof.safetyEstablished, false);
  assert.equal(proof.universalWarningsEstablished, false);
  assert.equal(proof.privateOriginalsPublished, false);
  assert.doesNotMatch(raw, /C:\\|Users|attachments|Gratuity|Nomination|clipboard/);
  assert.deepEqual(proof.images.map(image => image.sourceSha256), expectedSources);
  assert.equal(proof.images.length, 5);
  for (const [index, image] of proof.images.entries()) {
    assert.match(image.file, /^warning-(edge|windows)-[a-z-]+\.png$/);
    assert.equal(image.transform.resized, false);
    assert.equal(image.transform.warningPixelsReconstructed, false);
    assert.equal(image.transform.metadataStripped, true);
    assert.equal(image.transform.crop.length, 4);
    assert.deepEqual(image.transform.crop, expectedTransforms[index][0]);
    assert.equal(image.sha256, expectedTransforms[index][1]);
    assert.ok(image.transform.privacyReason);
    const bytes = readFileSync(new URL(`../assets/${image.file}`, import.meta.url));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), image.sha256);
    assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.deepEqual([bytes.readUInt32BE(16), bytes.readUInt32BE(20)], image.dimensions);
    assert.doesNotMatch(bytes.toString('latin1'), /eXIf|tEXt|iTXt|zTXt/);
    assert.match(read('index.html'), new RegExp(`src="/assets/${image.file}"[^>]+alt="[^"]+"`));
  }
  assert.ok(proof.images[0].transform.crop[1] >= 102, 'Profile toolbar must be excluded');
  assert.ok(proof.images[2].transform.redactions.length > 0, 'Unrelated document below warning must be redacted');
  assert.deepEqual(proof.images[2].transform.redactions[0].rectangle, [0, 707, 368, 26]);
});

test('genuine warning captions bound evidence and conditional actions without a benign fallback', () => {
  const page = read('index.html');
  assert.equal((page.match(/Real customer-provided preview\.8 ARM64 screenshot, not CI/g) ?? []).length, 5);
  assert.match(page, /Browser and OS versions unknown; safety and universal warning behavior are not established/);
  assert.match(page, /Screenshots do not prove the binary's SHA-256, successful execution or app acceptance/);
  assert.match(page, /\(1\).*duplicate-download suffix/);
  const edge = /<details><summary>Microsoft Edge on Windows<\/summary>([\s\S]*?)<\/details>/.exec(page)?.[1];
  assert.ok(edge);
  assert.match(edge, /Only for an unknown-reputation prompt,[\s\S]*exact source[\s\S]*SHA-256 match[\s\S]*policy permits[\s\S]*accept the risk/);
  assert.match(edge, /More options[\s\S]*Keep[\s\S]*Keep anyway/);
  assert.match(edge, /See more/);
  assert.doesNotMatch(edge, /edge-downloads\.png|sample\.txt/);
  assert.match(page, /Windows protected your PC[\s\S]*More info[\s\S]*Run anyway/);
  assert.match(page, /malware or policy blocks, stop/);
  assert.match(page, /checksum.*consistency.*not.*safety|matching SHA-256.*does not prove the file is safe/is);
  assert.doesNotMatch(page, /<details[^>]*\bopen(?:\s|>|=)/);
  const workflow = readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const gate = /edge-download-observation:\s+if: ([^\r\n]+)/.exec(workflow)?.[1];
  assert.ok(gate);
  assert.doesNotMatch(gate, /pull_request/, 'Ordinary follow-up CI must not retry installer download observation');
});
