"""Render original canonical SVGs with installed headless Edge; no runtime dependency."""
import argparse
from pathlib import Path

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", default="msedge")
    parser.add_argument("--verify", action="store_true", help="Compare rendered bytes without changing files")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    asset_root = root / "assets" / "garden_themes"
    vectors = sorted(asset_root.glob("*/*.svg"))
    if len(vectors) != 54:
        raise RuntimeError(f"Expected 54 canonical SVGs, found {len(vectors)}; run node tool/garden_assets.mjs first")

    def emit(destination, image):
        if args.verify:
            if destination.read_bytes() != image:
                raise RuntimeError(f"Raster regeneration differs: {destination}")
        else:
            destination.parent.mkdir(exist_ok=True)
            destination.write_bytes(image)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            channel=args.channel, headless=True,
            args=["--disable-gpu", "--force-color-profile=srgb"],
        )
        try:
            for scale in (1, 2, 3):
                context = browser.new_context(device_scale_factor=scale)
                page = context.new_page()
                try:
                    for source in vectors:
                        page.goto(source.as_uri())
                        svg = page.locator("svg")
                        box = svg.bounding_box()
                        if not box or box["width"] <= 0 or box["height"] <= 0:
                            raise RuntimeError(f"Missing vector bounds: {source}")
                        page.set_viewport_size({"width": int(box["width"]), "height": int(box["height"])})
                        destination = source.with_suffix(".png") if scale == 1 else source.parent / f"{scale}.0x" / f"{source.stem}.png"
                        if source.name != "garden.svg":
                            geometry = page.locator("#artwork").evaluate(
                                "(e)=>{const b=e.getBBox();const v=e.ownerSVGElement.viewBox.baseVal;"
                                "return b.x>=0 && b.y>=0 && b.x+b.width<=v.width && b.y+b.height<=v.height}"
                            )
                            if not geometry:
                                raise RuntimeError(f"Clipped vector path bounds: {source}")
                        emit(destination, svg.screenshot(omit_background=True, animations="disabled"))
                finally:
                    context.close()
            page = browser.new_page(viewport={"width": 960, "height": 640}, device_scale_factor=1)
            for source in sorted((root / "docs" / "design" / "garden-themes" / "production-previews").glob("*.svg")):
                page.goto(source.as_uri())
                emit(source.with_suffix(".png"), page.locator("svg").screenshot(omit_background=True))
            page.close()
        finally:
            browser.close()
    action = "Verified" if args.verify else "Exported"
    print(f"{action} 162 density PNGs and 6 theme previews; unclipped vector layers; headless browser closed.")


if __name__ == "__main__":
    main()
