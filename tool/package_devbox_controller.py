"""Package the reviewed private Dev Box connection source, never credentials."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

FILES = {
    name: f"tool/devbox-controller/{name}"
    for name in (
        "Connect-DevBox.ps1", "Invoke-ControllerTrial.ps1", "connection-dependencies.json",
        "validate.yml", "Verify-Candidate.ps1", "approved-candidates.json", "README.md",
    )
}
FILES.update({
    "Bootstrap.Common.ps1": "tool/protected-vm/Bootstrap.Common.ps1",
    "harness/Run-InstallerTrial.ps1": "tool/devbox-trial/Run-InstallerTrial.ps1",
    "harness/Trial.Common.ps1": "tool/devbox-trial/Trial.Common.ps1",
    "harness/verify_onboarding_wizard.ps1": "tool/verify_onboarding_wizard.ps1",
    "harness/universal_integrity_contract.ps1": "tool/universal_integrity_contract.ps1",
    "harness/process_token_probe.cs": "tool/process_token_probe.cs",
})


def build(source, output):
    source = subprocess.check_output(
        ["git", "rev-parse", "--verify", f"{source}^{{commit}}"], text=True
    ).strip()
    files = {
        target: subprocess.check_output(["git", "show", f"{source}:{path}"])
        for target, path in FILES.items()
    }
    manifest = {
        "kind": "bloomstep-private-controller-connection-v1",
        "source": source,
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
            info = zipfile.ZipInfo(f"bloomstep-private-controller/{name}", (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return hashlib.sha256(output.read_bytes()).hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(f"{build(args.source, args.output)}  {args.output.name}")
