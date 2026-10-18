"""Build a deterministic ZIP with the retained, hash-pinned CI installer candidate."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

SOURCE_FILES = (
    "Run-InstallerTrial.ps1",
    "Trial.Common.ps1",
    "trial-manifest.json",
    "README.md",
)
ARTIFACT_FILES = (
    "Budlark-0.1.0-preview-windows-universal-setup.exe",
    "universal-manifest.json",
    "payload-manifest-x64.json",
    "payload-manifest-arm64.json",
)


def build(source, artifact_dir, output):
    source = subprocess.check_output(
        ["git", "rev-parse", "--verify", f"{source}^{{commit}}"], text=True
    ).strip()
    root = "tool/devbox-trial/"
    files = {
        name: subprocess.check_output(["git", "show", f"{source}:{root}{name}"])
        for name in SOURCE_FILES
    }
    artifact_dir = Path(artifact_dir)
    for name in ARTIFACT_FILES:
        files[name] = (artifact_dir / name).read_bytes()
    trial = json.loads(files["trial-manifest.json"])
    installer = trial["artifact"]["installerFile"]
    if (hashlib.sha256(files[installer]).hexdigest() != trial["artifact"]["installerSha256"] or
            len(files[installer]) != trial["artifact"]["bytes"] or
            trial["artifact"]["signatureStatus"] != "NotSigned" or
            trial["artifact"]["published"] is not False or
            trial["protectedGatesAccepted"] is not False):
        raise ValueError("The retained installer artifact does not match its pinned SHA-256.")
    universal = json.loads(files["universal-manifest.json"])
    if universal["source"] != trial["source"] or universal["installerSha256"] != trial["artifact"]["installerSha256"]:
        raise ValueError("The universal manifest does not match the retained installer identity.")
    for arch in ("x64", "arm64"):
        payload = f"payload-manifest-{arch}.json"
        if hashlib.sha256(files[payload]).hexdigest() != trial["payloadManifests"][arch]:
            raise ValueError(f"The {arch} payload manifest does not match its pinned SHA-256.")
    manifest = {
        "kind": "budlark-devbox-installer-trial-package-v1",
        "sourceCommit": source,
        "files": [
            {"path": name, "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in sorted(files.items())
        ],
    }
    files["package-manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(f"budlark-devbox-installer-trial/{name}", (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return hashlib.sha256(output.read_bytes()).hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--artifact-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(f"{build(args.source, args.artifact_dir, args.output)}  {args.output.name}")
