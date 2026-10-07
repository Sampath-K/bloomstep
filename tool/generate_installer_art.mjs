import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

// Original geometric garden art, rasterized without fonts or external assets.
function garden(width, height, small, growth = false) {
  const stride = Math.ceil(width * 3 / 4) * 4;
  const bmp = Buffer.alloc(54 + stride * height);
  bmp.write('BM');
  bmp.writeUInt32LE(bmp.length, 2);
  bmp.writeUInt32LE(54, 10);
  bmp.writeUInt32LE(40, 14);
  bmp.writeInt32LE(width, 18);
  bmp.writeInt32LE(height, 22);
  bmp.writeUInt16LE(1, 26);
  bmp.writeUInt16LE(24, 28);
  bmp.writeUInt32LE(stride * height, 34);
  const colors = { paper: [247, 244, 239], soil: [102, 86, 74],
    leaf: [56, 106, 71], flower: [177, 31, 75] };
  const ellipse = (x, y, cx, cy, rx, ry) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const nx = x / width, ny = y / height;
      let color = colors.paper;
      if (growth) {
        if (ny > .8 && ny < .83 && nx > .04 && nx < .96) color = colors.soil;
        for (let stage = 0; stage < 5; stage++) {
          const cx = .1 + stage * .2, top = .74 - stage * .12;
          if (stage === 0 && ellipse(nx, ny, cx, .77, .035, .04)) color = colors.flower;
          if (stage > 0) {
            if (Math.abs(nx - cx) < .009 && ny > top && ny < .8 ||
                ellipse(nx, ny, cx - .045, top + .09, .045, .026) ||
                ellipse(nx, ny, cx + .045, top + .03, .045, .026)) color = colors.leaf;
          }
          if (stage === 3 && ellipse(nx, ny, cx, top, .025, .03)) color = colors.flower;
          if (stage === 4) {
            for (const [dx, dy] of [[0, -.04], [-.04, 0], [.04, 0], [0, .04]]) {
              if (ellipse(nx, ny, cx + dx, top + dy, .035, .035)) color = colors.flower;
            }
            if (ellipse(nx, ny, cx, top, .018, .018)) color = colors.paper;
          }
        }
      } else if (small) {
        if (ny > .78 && ny < .83 && nx > .15 && nx < .85) color = colors.soil;
        if (nx > .46 && nx < .54 && ny > .34 && ny < .8 ||
            ellipse(nx, ny, .34, .48, .16, .08) ||
            ellipse(nx, ny, .65, .34, .16, .08)) color = colors.leaf;
      } else {
        if (ny > .84 && ny < .86 && nx > .1 && nx < .9) color = colors.soil;
        for (const [cx, top] of [[.23, .72], [.5, .55], [.77, .34]]) {
          if (Math.abs(nx - cx) < .015 && ny > top && ny < .85 ||
              ellipse(nx, ny, cx - .08, top + .07, .085, .026) ||
              ellipse(nx, ny, cx + .08, top + .02, .085, .026)) color = colors.leaf;
        }
        for (const [cx, cy] of [[.77, .30], [.69, .33], [.85, .33], [.77, .36]]) {
          if (ellipse(nx, ny, cx, cy, .065, .034)) color = colors.flower;
        }
        if (ellipse(nx, ny, .77, .33, .027, .014)) color = colors.paper;
      }
      const offset = 54 + (height - y - 1) * stride + x * 3;
      bmp[offset] = color[2]; bmp[offset + 1] = color[1]; bmp[offset + 2] = color[0];
    }
  }
  return bmp;
}

const check = process.argv.includes('--check');
const directory = new URL('../packaging/assets/', import.meta.url);
if (!check) mkdirSync(directory, { recursive: true });
for (const [name, width, height, small, growth] of [
  ['wizard-garden', 164, 314, false, false], ['wizard-seed', 55, 55, true, false],
]) {
  const path = new URL(`${name}.bmp`, directory);
  const bytes = garden(width, height, small, growth);
  if (check) assert.deepEqual(readFileSync(path), bytes, `Regenerate original ${name}.bmp`);
  else writeFileSync(path, bytes);
}

if (check) {
  const manifest = JSON.parse(readFileSync(new URL('education-art-provenance.json', directory), 'utf8'));
  assert.equal(manifest.kind, 'authored-illustrations-not-installer-screenshots');
  assert.equal(manifest.sourceNormalization, 'UTF-8 text with LF line endings');
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  assert.equal(manifest.sources.length, 3);
  for (const source of manifest.sources) {
    assert.equal(hash(readFileSync(new URL(`../${source.path}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n')), source.sha256,
      `Re-export authored illustrations after changing ${source.path}`);
  }
  assert.deepEqual(manifest.assets.map(asset => asset.file),
    ['education-seed.bmp', 'education-recipe.bmp', 'education-growth.bmp', 'education-hero.bmp']);
  for (const asset of manifest.assets) {
    const bytes = readFileSync(new URL(asset.file, directory));
    assert.equal(hash(bytes), asset.sha256, `Original illustration changed: ${asset.file}`);
    assert.equal(bytes.subarray(0, 2).toString(), 'BM');
    assert.equal(bytes.readInt32LE(18), asset.width);
    assert.equal(bytes.readInt32LE(22), asset.height);
    assert.equal(bytes.readUInt16LE(28), 24);
  }
}
