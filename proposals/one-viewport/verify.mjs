import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { chromium } from '../../site/node_modules/playwright/index.mjs';

const root = new URL('./', import.meta.url);
const html = await readFile(new URL('index.html', root));
const server = createServer((req, res) => {
  if (!['/', '/index.html'].includes(new URL(req.url, 'http://localhost').pathname)) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(html);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
  headless: true,
  args: ['--no-sandbox'],
});
const evidence = {
  scope: 'Static proposal only; not production or customer data',
  sourceSha256: createHash('sha256').update(html).digest('hex'),
  checks: [],
};
await mkdir(new URL('screenshots/', root), { recursive: true });
const errors = [];

async function textContrast(page) {
  return page.evaluate(() => {
    const parse = value => {
      const nums = value.match(/[\d.]+/g)?.map(Number);
      if (!nums || nums.length < 3) throw Error(`Unsupported color ${value}`);
      return [...nums.slice(0, 3), nums[3] ?? 1];
    };
    const over = (fg, bg) => [...fg.slice(0, 3).map((v, i) => v * fg[3] + bg[i] * (1 - fg[3])), 1];
    const background = node => {
      const chain = [];
      for (let el = node; el; el = el.parentElement) chain.unshift(el);
      return chain.reduce((bg, el) => over(parse(getComputedStyle(el).backgroundColor), bg), [255, 255, 255, 1]);
    };
    const luminance = color => color.slice(0, 3).map(v => v / 255)
      .map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
      .reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
    const failures = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const text = walker.currentNode;
      const el = text.parentElement;
      if (!text.textContent.trim() || ['SCRIPT', 'STYLE', 'OPTION', 'TITLE'].includes(el.tagName)) continue;
      const rect = el.getBoundingClientRect(), style = getComputedStyle(el);
      if (!rect.width || !rect.height || style.visibility === 'hidden') continue;
      const bg = background(el), fg = over(parse(style.color), bg);
      const a = luminance(fg), b = luminance(bg), ratio = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
      const large = parseFloat(style.fontSize) >= 24 || (parseFloat(style.fontSize) >= 18.66 && parseInt(style.fontWeight) >= 700);
      if (ratio < (large ? 3 : 4.5)) failures.push({ text: text.textContent.trim(), ratio, foreground: style.color });
    }
    return failures;
  });
}

try {
  for (const theme of ['light', 'dark']) {
    for (const size of [{ width: 1920, height: 1080 }, { width: 1366, height: 768 }]) {
      for (const variant of ['a', 'b', 'c']) {
        const page = await browser.newPage({ viewport: size, reducedMotion: 'reduce' });
        page.on('pageerror', error => errors.push(error.message));
        const requests = [];
        page.on('request', request => requests.push(request.url()));
        await page.goto(`${origin}/?scoutTheme=${theme}&variant=${variant}`);
        const layout = await page.evaluate(() => {
          const rect = selector => {
            const r = document.querySelector(selector).getBoundingClientRect();
            return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
          };
          return {
            title: rect('h1'), cta: rect('#download-cta'), safety: rect('.preview-note'),
            methodLink: rect('.learn-link'), illustration: rect('.product'),
            fold: rect('.first-screen'), method: rect('#method'),
            width: document.documentElement.scrollWidth, viewport: innerWidth,
          };
        });
        for (const target of ['title', 'cta', 'safety', 'methodLink', 'illustration']) {
          assert(layout[target].top >= 0 && layout[target].bottom <= size.height, `${theme}/${variant}/${size.width}: ${target} outside first viewport`);
        }
        assert(layout.method.top >= size.height, 'Optional method starts below the first viewport');
        assert(layout.width <= layout.viewport, 'No horizontal overflow');
        assert.deepEqual(await textContrast(page), [], `${theme}: text contrast`);
        const brokenImages = await page.locator('img:not([alt])').count();
        assert.equal(brokenImages, 0);
        assert.equal(await page.locator('svg:not([aria-hidden]):not([role="img"])').count(), 0);
        await page.keyboard.press('Tab');
        assert.equal(await page.locator(':focus').textContent(), 'Skip to content');
        await page.locator('#download-cta').focus();
        await page.keyboard.press('Enter');
        assert(await page.locator('#preview-dialog').evaluate(node => node.open));
        assert.deepEqual(await textContrast(page), [], `${theme}: dialog text contrast`);
        const focusable = await page.locator('#preview-dialog a, #preview-dialog button').count();
        for (let i = 0; i <= focusable; i++) {
          await page.keyboard.press('Tab');
          assert(await page.evaluate(() => document.activeElement.closest('#preview-dialog') !== null), 'Modal focus stays inside dialog');
        }
        await page.keyboard.press('Escape');
        assert.equal(await page.locator(':focus').getAttribute('id'), 'download-cta');
        await page.locator('#variant').selectOption(variant === 'a' ? 'b' : 'a');
        assert.equal(await page.locator('#hero-title').textContent(), variant === 'a' ? 'A tiny habit. A little more you.' : 'Build a habit small enough to start today.');
        await page.locator('#variant').selectOption(variant);
        assert(requests.every(url => url.startsWith(origin)), 'No external requests or analytics');
        const motion = await page.evaluate(() => [...document.querySelectorAll('*')].some(el => {
          const s = getComputedStyle(el);
          return s.animationName !== 'none' || parseFloat(s.transitionDuration) > 0;
        }));
        assert.equal(motion, false);
        await page.locator('#download-cta').blur();
        if ((theme === 'light' && variant === 'a') || (size.width === 1366 && (theme === 'light' || variant === 'a'))) {
          await page.screenshot({ path: fileURLToPath(new URL(`screenshots/${theme}-${variant}-${size.width}x${size.height}.png`, root)) });
        }
        evidence.checks.push({ theme, variant, ...size, layout, textContrast: 'WCAG AA pass', keyboardDialog: 'pass', reducedMotion: 'pass', externalRequests: 0 });
        await page.close();
      }
    }
  }
  for (const width of [320, 390, 683]) {
    const page = await browser.newPage({ viewport: { width, height: width === 683 ? 384 : 844 } });
    await page.goto(`${origin}/?scoutTheme=light`);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `No overflow at ${width}px`);
    assert.deepEqual(await textContrast(page), []);
    evidence.checks.push({ width, responsiveReflow: 'pass (vertical scrolling expected on mobile/zoom)' });
    if (width === 390) await page.screenshot({ path: fileURLToPath(new URL('screenshots/light-a-mobile-390.png', root)), fullPage: true });
    await page.close();
  }
  const noJs = await browser.newPage({ javaScriptEnabled: false, viewport: { width: 1366, height: 768 } });
  await noJs.goto(origin);
  await noJs.locator('#download-cta').click();
  assert.equal(new URL(noJs.url()).hash, '#preview-details');
  await noJs.locator('#preview-details summary').click();
  assert(await noJs.locator('#preview-details').evaluate(node => node.open));
  evidence.checks.push({ javaScriptDisabled: 'Native preview details and release link available' });
  await noJs.close();
  assert.deepEqual(errors, []);
  evidence.pageErrors = errors;
  await writeFile(new URL('verification.json', root), JSON.stringify(evidence, null, 2) + '\n');
  console.log(`PASS: ${evidence.checks.length} proposal scenarios; viewport, contrast, keyboard, motion, no-JS and reflow checks.`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
