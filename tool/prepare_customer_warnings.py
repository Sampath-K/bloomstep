"""Transform only the five approved images; originals remain private inputs."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


SPECS = [
    ("warning-edge-uncommon.png", "2f3a4ffd0e8c1192d7fb38a53f127649849453dd32b0df61b44402a888d319e1",
     (574, 456), (32, 102, 541, 354), [], "Exclude profile face, toolbar and unrelated page background."),
    ("warning-edge-menu.png", "069f4a96060d4716ce0286f9079dc0e105a3c5be7be3ec921d7d19d4a004ecb2",
     (300, 300), (7, 0, 293, 300), [], "Exclude outside-menu left gutter."),
    ("warning-edge-keep-anyway.png", "53e89b0e7aaa9c91f64eb651ae89fb055e8b241e678fa52f801d05a313a6a391",
     (537, 737), (0, 4, 529, 733), [(0, 707, 368, 26)],
     "Exclude top/right background gutters; mask unrelated document title below dialog, outside Keep anyway."),
    ("warning-windows-protected.png", "4415aa34880c5e4b8784de6f2ed6b42d084b853c84c6630106c596652eb9fe42",
     (804, 751), (4, 1, 798, 746), [], "Exclude outside-modal background at edges."),
    ("warning-windows-run-anyway.png", "29a4a289f74c4343bf31b2ae4a8da3e95ed336e11506439108225945fce4ee55",
     (799, 750), (0, 4, 798, 746), [], "Exclude outside-modal top/right edge."),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs=5, type=Path,
                        help="Approved originals in order: Edge initial, menu, expanded, Windows initial, expanded")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    images = []
    # Validate every private input before writing any public output.
    for source, (_, expected, dimensions, _, _, _) in zip(args.sources, SPECS):
        if digest(source) != expected:
            raise ValueError("Input hash differs from the approved source")
        with Image.open(source) as image:
            if image.size != dimensions:
                raise ValueError("Input dimensions differ from the approved source")
    args.output.mkdir(parents=True, exist_ok=True)
    for source, (name, expected, dimensions, crop, masks, reason) in zip(args.sources, SPECS):
        x, y, width, height = crop
        with Image.open(source) as original:
            region = original.convert("RGB").crop((x, y, x + width, y + height))
        # New pixel-only image strips metadata. No resizing, OCR, UI drawing or repair.
        public = Image.frombytes("RGB", region.size, region.tobytes())
        draw = ImageDraw.Draw(public)
        for mx, my, mw, mh in masks:
            draw.rectangle((mx, my, mx + mw - 1, my + mh - 1), fill=(36, 36, 36))
        destination = args.output / name
        public.save(destination, format="PNG")
        with Image.open(destination) as saved:
            if saved.tobytes() != public.tobytes() or saved.info:
                raise ValueError("Saved asset pixels or metadata differ from transformation")
        images.append({
            "file": name, "sourceSha256": expected, "sourceDimensions": dimensions,
            "sha256": digest(destination), "dimensions": public.size,
            "transform": {
                "crop": crop, "coordinateSpace": "source pixels; x, y, width, height",
                "redactions": [{"rectangle": mask, "coordinateSpace": "cropped pixels; x, y, width, height",
                                "fillRgb": [36, 36, 36]} for mask in masks],
                "privacyReason": reason, "resized": False, "metadataStripped": True,
                "warningPixelsReconstructed": False,
            },
        })
    proof = {
        "schemaVersion": 1, "captureSource": "customer-provided screenshots",
        "release": "0.1.0-preview.8", "architecture": "arm64",
        "browser": "Microsoft Edge (customer-reported)", "browserVersion": None, "osVersion": None,
        "ciCapture": False, "privateOriginalsPublished": False,
        "binaryHashEstablished": False, "executionSuccessEstablished": False,
        "appAcceptanceEstablished": False, "safetyEstablished": False,
        "universalWarningsEstablished": False,
        "authorization": "User authorized warning-region cropping and privacy redaction for this walkthrough.",
        "observedFilename": "Bloomstep-0.1.0-preview.8-windows-arm64-setup (1).exe",
        "filenameNote": "(1) is the displayed duplicate-download suffix, not evidence of a different version or hash.",
        "transformationTool": "tool/prepare_customer_warnings.py",
        "transformationLibrary": "Pillow; lossless PNG, pixel-only RGB copy, no scaling",
        "images": images,
    }
    (args.output / "customer-warning-provenance.json").write_text(
        json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    print("Prepared five privacy-bounded warning assets; hashes and pixel transformations verified.")


if __name__ == "__main__":
    main()
