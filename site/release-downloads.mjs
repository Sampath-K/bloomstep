export function validateRelease(release) {
  if (!/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(release.tag)) throw Error('Explicit release tag required.');
  for (const arch of ['arm64', 'x64', ...(release.universal !== undefined ? ['universal'] : [])]) {
    const asset = release[arch];
    const expected = `https://github.com/Sampath-K/bloomstep/releases/download/${release.tag}/Bloomstep-${release.tag.slice(1)}-windows-${arch}-setup.exe`;
    if (asset?.url !== expected || !/^[a-f0-9]{64}$/.test(asset?.sha256)) {
      throw Error('Verified release assets and checksums required.');
    }
  }
}

export function renderDownloads(html, release) {
  validateRelease(release);
  if (!release.universal) {
    if (html.includes('data-universal-download')) throw Error('Restore the per-architecture source before reverting a unified pointer.');
    return html;
  }
  const secondary = `<details><summary>Secondary architecture-specific downloads</summary>
        <p class="small">For support only. The primary Windows installer selects the native payload automatically; a browser CPU hint is not used.</p>
        <p><a data-download="x64" href="${release.x64.url}">Bloomstep x64</a> · <a data-download="arm64" href="${release.arm64.url}">Bloomstep ARM64</a></p>
      </details>`;
  const primary = `<p id="architecture-guidance">One Windows installer. Windows selects the native x64 or ARM64 payload, including when setup runs under emulation. Unsupported 32-bit Windows cannot install. Both payloads are included; no internet is needed to install after downloading. Sign-in still needs a connection.</p>
      <p class="small"><a href="/#windows-install-help">Windows installation help before opening the installer</a></p>
      <p class="choices" data-universal-download><a class="button" data-download="unknown" href="${release.universal.url}">Download Bloomstep for Windows</a></p>
      ${secondary}`;
  if (html.includes('id="download-title"')) {
    const pattern = /<p id="architecture-guidance">[\s\S]*?(?=\s*<p class="small">The current Windows download)/;
    if (!pattern.test(html)) throw Error('Customer download region missing.');
    return html.replace(pattern, primary);
  }
  const pattern = /<p>Choose ARM64[\s\S]*?(?=\s*<p class="small">Unsigned preview)|<p id="architecture-guidance">[\s\S]*?(?=\s*<p class="small">Unsigned preview)/;
  if (!pattern.test(html)) throw Error('Releases download region missing.');
  return html.replace(pattern, `${primary}
      <p><a href="https://github.com/Sampath-K/bloomstep/releases/tag/${release.tag}">Release notes &amp; SHA-256 checksums</a></p>
      <p class="small"><code>Bloomstep-${release.tag.slice(1)}-windows-universal-setup.exe</code><br><code>Universal SHA-256: ${release.universal.sha256}</code></p>
      <details><summary>Secondary installer checksums</summary><p class="small"><code>ARM64 SHA-256: ${release.arm64.sha256}</code><br><code>x64 SHA-256: ${release.x64.sha256}</code></p></details>`);
}
