"""Generate original Bloomstep flower icons and the customer sign-in wordmark."""

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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", default=r"C:\Windows\Fonts\segoeuib.ttf")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    icon = flower(256)
    assets = root / "site" / "assets"
    assets.mkdir(exist_ok=True)
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
    draw.text((42, 0), "Bloomstep", font=font, fill="#242424")
    wordmark.save(assets / "bloomstep-wordmark.png")


if __name__ == "__main__":
    main()
