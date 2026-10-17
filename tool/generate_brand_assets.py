"""Generate original Bud Lark flower icons, sign-in wordmark and social card."""

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def flower(size):
    scale = 4
    image = Image.new("RGBA", (size * scale, size * scale))
    draw = ImageDraw.Draw(image)
    center = size * scale / 2
    radius = size * scale * 0.18
    petal = size * scale * 0.16
    for index in range(5):
        angle = index * 2 * math.pi / 5 - math.pi / 2
        x = center + math.cos(angle) * radius
        y = center + math.sin(angle) * radius
        draw.ellipse((x - petal, y - petal, x + petal, y + petal), fill="#b11f4b")
    seed = size * scale * 0.105
    draw.ellipse(
        (center - seed, center - seed, center + seed, center + seed),
        fill="#f7f4ef",
    )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def social(font_path, regular_font_path):
    image = Image.new("RGB", (1200, 630), "#f7f4ef")
    draw = ImageDraw.Draw(image)
    draw.text(
        (64, 48), "Bud Lark",
        font=ImageFont.truetype(font_path, 61), fill="#242424",
    )
    draw.text(
        (68, 140), "A little is enough.",
        font=ImageFont.truetype(regular_font_path, 35), fill="#5c5c5c",
    )
    draw.line((64, 544, 1136, 544), fill="#dedede", width=12)
    for x, top in [(240, 460), (560, 360), (920, 252)]:
        draw.line((x, top, x, 534), fill="#16a34a", width=12)
        draw.ellipse((x - 74, top + 20, x, top + 52), fill="#16a34a")
        draw.ellipse((x, top + 48, x + 74, top + 80), fill="#16a34a")
    for angle in range(0, 360, 60):
        radians = math.radians(angle)
        x = 920 + 32 * math.cos(radians)
        y = 252 + 32 * math.sin(radians)
        draw.ellipse((x - 25, y - 25, x + 25, y + 25), fill="#b11f4b")
    draw.ellipse((898, 230, 942, 274), fill="#f7f4ef")
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", default=r"C:\Windows\Fonts\segoeuib.ttf")
    parser.add_argument("--regular-font", default=r"C:\Windows\Fonts\segoeui.ttf")
    parser.add_argument("--text-only", action="store_true",
                        help="Regenerate wordmark/social text without replacing existing icons.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    icon = flower(256)
    assets = root / "site" / "assets"
    assets.mkdir(exist_ok=True)
    if not args.text_only:
        icon.save(assets / "bloomstep-icon.png")
        flower(32).save(assets / "bloomstep-favicon.png")
        icon.save(
            root / "windows" / "runner" / "resources" / "app_icon.ico",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
    wordmark = Image.new("RGBA", (245, 36))
    wordmark.alpha_composite(flower(36))
    draw = ImageDraw.Draw(wordmark)
    font = ImageFont.truetype(args.font, 28)
    draw.text((42, 0), "Bud Lark", font=font, fill="#242424")
    wordmark.save(assets / "bloomstep-wordmark.png")
    social(args.font, args.regular_font).save(assets / "bloomstep-social.png")


if __name__ == "__main__":
    main()
