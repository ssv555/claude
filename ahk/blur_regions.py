"""Blur specified regions in an image.

Usage:
  py blur_regions.py <image_path> <x,y,w,h> [<x,y,w,h> ...] [--radius N] [--output PATH]

Examples:
  py blur_regions.py screenshot.webp 730,365,80,28 730,415,80,28
  py blur_regions.py screenshot.png 100,200,150,30 --radius 15 --output blurred.png
"""

import sys
import argparse
from pathlib import Path
from PIL import Image, ImageFilter


def blur_regions(image_path: str, regions: list[tuple[int, int, int, int]], radius: int = 20, output: str | None = None):
    img = Image.open(image_path)

    for x, y, w, h in regions:
        box = (x, y, x + w, y + h)
        region = img.crop(box)
        blurred = region.filter(ImageFilter.GaussianBlur(radius=radius))
        img.paste(blurred, box)

    out_path = output or image_path
    img.save(out_path)
    print(f"Saved: {out_path} ({len(regions)} region(s) blurred, radius={radius})")


def parse_region(s: str) -> tuple[int, int, int, int]:
    parts = s.split(",")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(f"Region must be x,y,w,h — got '{s}'")
    return tuple(int(p) for p in parts)


def main():
    parser = argparse.ArgumentParser(description="Blur regions in an image")
    parser.add_argument("image", help="Path to image file")
    parser.add_argument("regions", nargs="+", type=parse_region, help="Regions as x,y,w,h")
    parser.add_argument("--radius", type=int, default=20, help="Blur radius (default: 20)")
    parser.add_argument("--output", "-o", help="Output path (default: overwrite original)")
    args = parser.parse_args()

    blur_regions(args.image, args.regions, args.radius, args.output)


if __name__ == "__main__":
    main()
