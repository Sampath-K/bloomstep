"""Generate original Budlark app icons, sign-in wordmark and social card."""

import argparse
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CANVAS = "#F7F4EF"
INK = "#242424"
MUTED = "#5C5C5C"
GREEN = "#2F6F4E"
LEAF = "#527B43"
OCHRE = "#B87828"
PETAL = "#B11F4B"
SVG_NS = "http://www.w3.org/2000/svg"

# These paths form a rising wing/flight stroke with a small rooted bud. They are
# original project artwork, drawn here rather than adapted from a third-party mark.
MARK_PATHS = (
    (
        "M 8 76 C 35 42 75 17 119 9 C 108 32 90 51 67 68 "
        "C 87 62 108 47 120 36 C 110 68 87 90 58 99 "
        "C 35 105 18 94 8 76 Z",
        GREEN,
    ),
    ("M 17 117 C 26 102 37 91 51 81", GREEN),
    (
        "M 24 91 C 13 88 10 78 13 69 C 25 72 32 79 32 88 "
        "C 29 89 26 90 24 91 Z",
        CANVAS,
    ),
    (
        "M 42 88 C 55 81 71 68 91 47",
        CANVAS,
    ),
    (
        "M 23 104 C 12 99 10 89 14 82 C 25 85 32 92 32 101 "
        "C 29 102 26 103 23 104 Z",
        OCHRE,
    ),
    (
        "M 33 99 C 35 88 44 81 54 80 C 54 91 47 99 34 103 Z",
        LEAF,
    ),
)


def svg_master():
    paths = []
    for index, item in enumerate(MARK_PATHS):
        path, color = item
        if index == 1:
            paths.append(
                f'<path d="{path}" fill="none" stroke="{color}" '
                'stroke-width="5" stroke-linecap="round"/>'
            )
        elif index in (2, 3):
            paths.append(
                f'<path d="{path}" fill="none" stroke="{color}" '
                'stroke-width="8" stroke-linecap="round"/>'
            )
        else:
            paths.append(f'<path d="{path}" fill="{color}"/>')
    return f"""<svg xmlns="{SVG_NS}" viewBox="0 0 128 128" role="img">
  <title>Budlark rising wing and bud mark</title>
  <desc>An original, abstract upward wing stroke joined to a two-leaf bud.</desc>
  <!-- Original vector drawn for this project; no external image assets used. -->
  {"".join(paths)}
</svg>
"""


def _path_points(path, scale, samples=24):
    tokens = re.findall(r"[MCZ]|-?\d+(?:\.\d+)?", path)
    points = []
    cursor = 0
    current = None
    start = None
    while cursor < len(tokens):
        command = tokens[cursor]
        cursor += 1
        if command == "M":
            current = (float(tokens[cursor]), float(tokens[cursor + 1]))
            start = current
            cursor += 2
            points.append((current[0] * scale, current[1] * scale))
        elif command == "C":
            values = [float(value) for value in tokens[cursor:cursor + 6]]
            cursor += 6
            p0 = current
            p1 = (values[0], values[1])
            p2 = (values[2], values[3])
            p3 = (values[4], values[5])
            for step in range(1, samples + 1):
                t = step / samples
                inverse = 1 - t
                x = (
                    inverse ** 3 * p0[0]
                    + 3 * inverse ** 2 * t * p1[0]
                    + 3 * inverse * t ** 2 * p2[0]
                    + t ** 3 * p3[0]
                )
                y = (
                    inverse ** 3 * p0[1]
                    + 3 * inverse ** 2 * t * p1[1]
                    + 3 * inverse * t ** 2 * p2[1]
                    + t ** 3 * p3[1]
                )
                points.append((x * scale, y * scale))
            current = p3
        elif command == "Z":
            if start is not None:
                points.append((start[0] * scale, start[1] * scale))
                current = start
        else:
            raise ValueError(f"Unsupported vector path command: {command}")
    return points


def mark(size, supersample=4):
    factor = size * supersample / 128
    canvas_size = round(128 * factor)
    image = Image.new("RGB", (canvas_size, canvas_size), CANVAS)
    draw = ImageDraw.Draw(image)
    for index, (path, color) in enumerate(MARK_PATHS):
        points = _path_points(path, factor)
        if index == 1:
            draw.line(points, fill=color, width=max(1, round(5 * factor)), joint="curve")
        elif index in (2, 3):
            draw.line(points, fill=color, width=max(1, round(8 * factor)), joint="curve")
        else:
            draw.polygon(points, fill=color)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def _font(path, size, bold=False):
    candidate = Path(path)
    if candidate.is_file():
        return ImageFont.truetype(str(candidate), size)
    fallback = (
        Path("/usr/share/fonts/truetype/freefont/FreeSansBold.ttf")
        if bold
        else Path("/usr/share/fonts/truetype/freefont/FreeSans.ttf")
    )
    if fallback.is_file():
        return ImageFont.truetype(str(fallback), size)
    raise FileNotFoundError(
        f"Font not found: {path}. Pass a local font file with --font/--regular-font."
    )


def wordmark(font_path):
    image = Image.new("RGBA", (245, 36), (0, 0, 0, 0))
    image.alpha_composite(mark(36).convert("RGBA"), (0, 0))
    draw = ImageDraw.Draw(image)
    font = _font(font_path, 27, bold=True)
    draw.text((42, 1), "Budlark", font=font, fill=INK)
    return image


def social(font_path, regular_font_path):
    image = Image.new("RGB", (1200, 630), CANVAS)
    draw = ImageDraw.Draw(image)
    draw.text((64, 48), "Budlark", font=_font(font_path, 61, bold=True), fill=INK)
    draw.text(
        (68, 140), "A little is enough.",
        font=_font(regular_font_path, 35), fill=MUTED,
    )
    draw.line((64, 544, 1136, 544), fill="#DEDEDE", width=12)
    for x, top in [(240, 460), (560, 360), (920, 252)]:
        draw.line((x, top, x, 534), fill=GREEN, width=12)
        draw.ellipse((x - 74, top + 20, x, top + 52), fill=GREEN)
        draw.ellipse((x, top + 48, x + 74, top + 80), fill=GREEN)
    for angle in range(0, 360, 60):
        radians = math.radians(angle)
        x = 920 + 32 * math.cos(radians)
        y = 252 + 32 * math.sin(radians)
        draw.ellipse((x - 25, y - 25, x + 25, y + 25), fill=PETAL)
    draw.ellipse((898, 230, 942, 274), fill=CANVAS)
    return image


def write_png(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", default=r"C:\Windows\Fonts\segoeuib.ttf")
    parser.add_argument("--regular-font", default=r"C:\Windows\Fonts\segoeui.ttf")
    parser.add_argument(
        "--text-only", action="store_true",
        help="Regenerate wordmark/social text without replacing icons.",
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    assets = root / "site" / "assets"
    assets.mkdir(exist_ok=True)
    if not args.text_only:
        vector = root / "assets" / "brand" / "budlark-mark.svg"
        vector.parent.mkdir(parents=True, exist_ok=True)
        vector.write_text(
            svg_master(), encoding="utf-8"
        )
        write_png(mark(256), assets / "bloomstep-icon.png")
        write_png(mark(32), assets / "bloomstep-favicon.png")
        mark(256).convert("RGBA").save(
            root / "windows" / "runner" / "resources" / "app_icon.ico",
            format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
        for density, size in {
            "mdpi": 48,
            "hdpi": 72,
            "xhdpi": 96,
            "xxhdpi": 144,
            "xxxhdpi": 192,
        }.items():
            write_png(
                mark(size),
                root / "android" / "app" / "src" / "main" / "res"
                / f"mipmap-{density}" / "ic_launcher.png",
            )
        ios_icons = root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
        for path in ios_icons.glob("Icon-App-*.png"):
            dimensions, scale = path.name.removesuffix(".png").rsplit("@", 1)
            width, height = dimensions.removeprefix("Icon-App-").split("x")
            pixels = round(float(width) * int(scale.removesuffix("x")))
            write_png(mark(pixels), path)
        mac_icons = root / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
        for path in mac_icons.glob("app_icon_*.png"):
            write_png(mark(int(path.stem.removeprefix("app_icon_"))), path)
    write_png(wordmark(args.font), assets / "bloomstep-wordmark.png")
    write_png(
        social(args.font, args.regular_font),
        assets / "bloomstep-social.png",
    )


if __name__ == "__main__":
    main()
