import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';

// Original geometric garden art, rasterized without fonts or external assets.
function garden(width, height, small) {
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
      if (small) {
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
for (const [name, width, height, small] of [['garden', 164, 314, false], ['seed', 55, 55, true]]) {
  const path = new URL(`wizard-${name}.bmp`, directory);
  const bytes = garden(width, height, small);
  if (check) assert.deepEqual(readFileSync(path), bytes, `Regenerate original wizard-${name}.bmp`);
  else writeFileSync(path, bytes);
}
