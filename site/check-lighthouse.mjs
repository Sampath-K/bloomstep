import { readFile } from 'node:fs/promises';
const report = JSON.parse(await readFile(process.argv[2], 'utf8'));
let failed = false;
for (const category of ['performance','accessibility','best-practices','seo']) {
  const score = report.categories?.[category]?.score;
  if (typeof score !== 'number' || score < 0.9) {
    console.error(`${category}: ${score ?? 'unknown'}; expected >= 0.90`);
    failed = true;
  }
}
if (failed) process.exitCode = 1;
else console.log('All four customer-page quality scores >= 90.');
