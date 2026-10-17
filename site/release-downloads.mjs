export function validateRelease(release) {
  if (!/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(release.tag)) throw Error('Explicit release tag required.');
  for (const arch of ['arm64', 'x64', ...(release.universal !== undefined ? ['universal'] : [])]) {
    const asset = release[arch];
    const expected = `https://github.com/Sampath-K/bloomstep/releases/download/${release.tag}/Bloomstep-${release.tag.slice(1)}-windows-${arch}-setup.exe`;
    if (asset?.url !== expected || !/^[a-f0-9]{64}$/.test(asset?.sha256)) {
      throw Error('Verified release assets and checksums required.');
    }
  }
  if (release.universal?.bytes !== undefined &&
      (!Number.isSafeInteger(release.universal.bytes) || release.universal.bytes <= 0)) {
    throw Error('Verified release size must be a positive integer.');
  }
}

export function renderDownloads(html, release) {
  validateRelease(release);
  if (!release.universal) {
    if (html.includes('data-universal-download')) throw Error('Restore the per-architecture source before reverting a unified pointer.');
    return html;
  }
  const exactSize = release.universal.bytes === undefined ? '' :
    `<p class="small">Exact download size: ${(release.universal.bytes / 1e6).toFixed(2)} MB (${release.universal.bytes.toLocaleString('en-US')} bytes).</p>`;
  const secondary = `<details><summary>Other files (owner testing only)</summary>
        <p class="small">The secondary x64 and ARM64 installers are for troubleshooting by designated testers. Windows needs a 64-bit version; 32-bit Windows is not supported.</p>
        ${exactSize}
        <p><a data-download="x64" href="${release.x64.url}">Bud Lark x64</a> · <a data-download="arm64" href="${release.arm64.url}">Bud Lark ARM64</a></p>
      </details>`;
  const size = release.universal.bytes === undefined ? '' :
    `\n      <p class="small">Download size: ${(release.universal.bytes / 1e6).toFixed(2)} MB.</p>`;
  const primary = `<p id="architecture-guidance">One installer for 64-bit Windows. It chooses the right version for your PC. Installation works offline; signing in requires an internet connection.</p>
      <p class="small"><a href="${html.includes('id="download-title"') ? '#windows-install-help' : '/#windows-install-help'}">Windows installation help before opening the installer</a></p>
      <p class="choices" data-universal-download><a class="button" data-download="unknown" href="${release.universal.url}">Owner-test download (designated testers only)</a></p>${size}
      ${secondary}`;
  if (html.includes('id="download-title"')) {
    const pattern = /<p id="architecture-guidance">[\s\S]*?(?=\s*<p class="small">The preview is free)/;
    if (!pattern.test(html)) throw Error('Customer download region missing.');
    return html.replace(pattern, primary);
  }
  const pattern = /<p>Choose ARM64[\s\S]*?(?=\s*<p class="small">The preview installer is unsigned)|<p id="architecture-guidance">[\s\S]*?(?=\s*<p class="small">The preview installer is unsigned)/;
  if (!pattern.test(html)) throw Error('Releases download region missing.');
  return html.replace(pattern, `${primary}
      <p class="small"><strong>Owner-test file fingerprint:</strong> <code>Bloomstep-${release.tag.slice(1)}-windows-universal-setup.exe</code><br><code>Universal SHA-256: ${release.universal.sha256}</code></p>
      <details><summary>Other owner-test file fingerprints</summary><p class="small"><code>ARM64 SHA-256: ${release.arm64.sha256}</code><br><code>x64 SHA-256: ${release.x64.sha256}</code></p></details>`);
}
