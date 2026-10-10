import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

export async function snapshot({ repo, token, request = fetch, now = new Date() }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo) || !token) throw Error('Repository and GitHub token required.');
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28' };
  async function get(path, optional = false) {
    const response = await request(`https://api.github.com/repos/${repo}/${path}`, { headers });
    if (!response.ok) {
      if (optional && [403, 404].includes(response.status)) {
        return { available: false, status: response.status,
          reason: 'Repository traffic permission unavailable; not zero. See analytics-sandbox.md.' };
      }
      throw Error(`GitHub snapshot ${path}: HTTP ${response.status}`);
    }
    return { available: true, data: await response.json() };
  }
  const releases = [];
  for (let page = 1; ; page++) {
    const result = await get(`releases?per_page=100&page=${page}`);
    releases.push(...result.data.map(release => ({
      tag: release.tag_name, publishedAt: release.published_at,
      assets: release.assets.map(asset => ({ id: asset.id, name: asset.name, downloads: asset.download_count })),
    })));
    if (result.data.length < 100) break;
    if (page === 100) throw Error('Release pagination limit reached; snapshot would be incomplete.');
  }
  const [views, clones, referrers, paths] = await Promise.all([
    get('traffic/views', true), get('traffic/clones', true),
    get('traffic/popular/referrers', true), get('traffic/popular/paths', true),
  ]);
  return { schemaVersion: 1, repo, capturedAt: now.toISOString(), releases,
    traffic: { views, clones, referrers, paths },
    interpretation: 'Cumulative asset downloads and rolling 14-day traffic; not people, installs or attributable conversions. Overlapping daily traffic must not be summed.' };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const data = await snapshot({ repo: process.env.GITHUB_REPOSITORY, token: process.env.GITHUB_TOKEN });
  const directory = new URL('../build/acquisition/', import.meta.url);
  await mkdir(directory, { recursive: true });
  await writeFile(new URL(`${data.capturedAt.slice(0, 10)}.json`, directory), JSON.stringify(data, null, 2));
  if (Object.values(data.traffic).some(value => !value.available)) {
    console.warn('::warning::Traffic unavailable with current token; download counts saved, traffic is unknown.');
  }
}
