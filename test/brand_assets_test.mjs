import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const file = path => readFileSync(new URL(`../${path}`, import.meta.url));
const pngSize = path => {
  const image = file(path);
  assert.equal(image.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', path);
  assert.equal(image[25], 2, `${path} should be opaque RGB`);
  return [image.readUInt32BE(16), image.readUInt32BE(20)];
};

test('original Budlark mark is used for the site and supported launcher icons', () => {
  const expected = new Map([
    ['site/assets/budlark-icon.png', 256],
    ['site/assets/budlark-favicon.png', 32],
    ['windows/runner/resources/app_icon.ico', null],
    ['android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48],
    ['android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72],
    ['android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96],
    ['android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144],
    ['android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192],
  ]);
  for (const [path, size] of expected) {
    if (size !== null) assert.deepEqual(pngSize(path), [size, size], path);
  }

  for (const path of [
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png',
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png',
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png',
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
  ]) {
    const [width, height] = pngSize(path);
    assert.equal(width, height, path);
  }

  const ico = file('windows/runner/resources/app_icon.ico');
  assert.equal(ico.readUInt16LE(2), 1);
  const count = ico.readUInt16LE(4);
  assert.equal(count, 7);
  assert.deepEqual(
    Array.from({ length: count }, (_, index) => ico[6 + index * 16]),
    [16, 24, 32, 48, 64, 128, 0],
  );

  const iosDirectory = new URL(
    '../ios/Runner/Assets.xcassets/AppIcon.appiconset/',
    import.meta.url,
  );
  for (const filename of readdirSync(iosDirectory).filter(name => name.endsWith('.png'))) {
    const dimensions = filename.match(/^Icon-App-(\d+(?:\.\d+)?)x\d+(?:\.\d+)?@(\d)x\.png$/);
    assert.ok(dimensions, filename);
    const pixels = Math.round(Number(dimensions[1]) * Number(dimensions[2]));
    assert.deepEqual(pngSize(`ios/Runner/Assets.xcassets/AppIcon.appiconset/${filename}`), [pixels, pixels]);
  }

  const macDirectory = new URL(
    '../macos/Runner/Assets.xcassets/AppIcon.appiconset/',
    import.meta.url,
  );
  for (const filename of readdirSync(macDirectory).filter(name => name.endsWith('.png'))) {
    const dimensions = filename.match(/^app_icon_(\d+)\.png$/);
    assert.ok(dimensions, filename);
    const pixels = Number(dimensions[1]);
    assert.deepEqual(pngSize(`macos/Runner/Assets.xcassets/AppIcon.appiconset/${filename}`), [pixels, pixels]);
  }
});

test('generated wordmark keeps the exact product spelling and original vector source', () => {
  const wordmark = file('site/assets/budlark-wordmark.png');
  assert.equal(wordmark.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  assert.deepEqual([wordmark.readUInt32BE(16), wordmark.readUInt32BE(20)], [245, 36]);

  const master = file('assets/brand/budlark-mark.svg').toString('utf8');
  assert.match(master, /Budlark rising wing and bud mark/);
  assert.match(master, /Original vector drawn for this project/);
  assert.match(master, /<path d="M 8 76/);
  assert.doesNotMatch(master, /Bud\s+Lark|songbird|mascot/i);

  const generator = file('tool/generate_brand_assets.py').toString('utf8');
  for (const path of [
    'budlark-icon.png',
    'budlark-favicon.png',
    'app_icon.ico',
    'mipmap-',
    'Icon-App-',
    'app_icon_',
  ]) {
    assert.ok(generator.includes(path), `generator output path ${path}`);
  }
  assert.match(generator, /"Budlark"/);
});
