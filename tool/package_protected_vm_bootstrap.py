"""Build a deterministic, source-pinned bootstrap ZIP from committed files."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

FILES = {
    "Bootstrap.ps1": "tool/protected-vm/Bootstrap.ps1",
    "Bootstrap.Common.ps1": "tool/protected-vm/Bootstrap.Common.ps1",
    "Install-Inno.ps1": "tool/protected-vm/Install-Inno.ps1",
    "dependencies.json": "tool/protected-vm/dependencies.json",
    "README.md": "tool/protected-vm/README.md",
    "harness/setup_defender_test_vm.ps1": "tool/setup_defender_test_vm.ps1",
    "harness/inno_compiler_version.ps1": "tool/inno_compiler_version.ps1",
    "harness/inno-toolchain-probe.iss": "packaging/inno-toolchain-probe.iss",
}


def build(source, output):
    source = subprocess.check_output(
        ["git", "rev-parse", "--verify", f"{source}^{{commit}}"], text=True
    ).strip()
    files = {
        target: subprocess.check_output(["git", "show", f"{source}:{path}"])
        for target, path in FILES.items()
    }
    manifest = {
        "kind": "bloomstep-vm-bootstrap-package-v1",
        "source": source,
        "files": [
            {"path": name, "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in sorted(files.items())
        ],
    }
    files["package-manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(f"bloomstep-vm-bootstrap/{name}", (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return hashlib.sha256(output.read_bytes()).hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(f"{build(args.source, args.output)}  {args.output.name}")
