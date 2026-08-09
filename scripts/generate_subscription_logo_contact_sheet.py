#!/usr/bin/env python3
"""Render a local, offline contact sheet for the subscription logo catalog.

This is a development/QA tool. It reads only tracked mapping/catalog data and
local artwork already present in the checkout; it never performs network I/O.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
MAPPING = ROOT / "scripts/subscription_logo_mapping.json"
CATALOG = ROOT / "app/Sa7tot/Models/SubscriptionServiceCatalog.swift"
ASSETS = ROOT / "app/Sa7tot/Assets.xcassets/SubscriptionLogos"
OVERRIDES = ROOT / "scripts/subscription_logo_overrides"

COLS = 5
CELL_SIZE = (250, 150)
ICON_SIZE = (76, 76)
BACKGROUND = (24, 24, 28, 255)
CARD = (43, 43, 49, 255)
TEXT = (245, 245, 247, 255)
SECONDARY = (174, 174, 178, 255)


def catalog_names() -> dict[str, str]:
    pattern = re.compile(r'service\("([^"]+)",\s*"([^"]+)"')
    return {service_id: display for service_id, display in pattern.findall(CATALOG.read_text())}


def source_label(entry: dict) -> str:
    source = entry["source"]
    if source == "app-store":
        return "App Store • " + entry["sourceClass"]
    if source == "official-product":
        return "Official product"
    if entry.get("fallbackSimpleIcon"):
        return "Simple Icons fallback"
    return "SF Symbol fallback"


def local_source(entry: dict) -> Path | None:
    service_id = entry["serviceID"]
    source = entry["source"]
    if source == "app-store":
        return ASSETS / f"subscription-app-icon-{service_id}.imageset/icon.png"
    if source == "official-product":
        return ROOT / entry["assetFile"]
    if entry.get("fallbackSimpleIcon"):
        return ASSETS / f"subscription-logo-{service_id}.imageset/icon.svg"
    return None


def rasterize(path: Path, temporary: Path) -> Image.Image | None:
    if path.suffix.lower() == ".png":
        return Image.open(path).convert("RGBA")

    output = temporary / f"{path.stem}.png"
    result = subprocess.run(
        ["sips", "-s", "format", "png", str(path), "--out", str(output)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0 or not output.exists():
        return None
    return Image.open(output).convert("RGBA")


def fallback_tile(entry: dict, font: ImageFont.ImageFont) -> Image.Image:
    color = entry.get("brandHex") or "777777"
    try:
        rgb = tuple(int(color[index : index + 2], 16) for index in (0, 2, 4))
    except ValueError:
        rgb = (119, 119, 119)
    tile = Image.new("RGBA", ICON_SIZE, (*rgb, 255))
    draw = ImageDraw.Draw(tile)
    draw.text((ICON_SIZE[0] // 2, ICON_SIZE[1] // 2), "SF", fill="white", font=font, anchor="mm")
    return tile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/tmp/Sa7tot-subscription-logo-contact-sheet.png"),
    )
    args = parser.parse_args()

    mapping = json.loads(MAPPING.read_text())
    names = catalog_names()
    entries = mapping["services"]
    missing: list[str] = []

    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15)
        small_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
        small_font = font

    width = COLS * CELL_SIZE[0]
    rows = (len(entries) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (width, rows * CELL_SIZE[1]), BACKGROUND)
    draw = ImageDraw.Draw(sheet)

    with tempfile.TemporaryDirectory(prefix="sa7tot-logo-sheet-") as temporary_dir:
        temporary = Path(temporary_dir)
        for index, entry in enumerate(entries):
            column = index % COLS
            row = index // COLS
            x = column * CELL_SIZE[0]
            y = row * CELL_SIZE[1]
            draw.rounded_rectangle(
                (x + 8, y + 8, x + CELL_SIZE[0] - 8, y + CELL_SIZE[1] - 8),
                radius=16,
                fill=CARD,
            )

            source = local_source(entry)
            image = None
            if source and source.exists():
                try:
                    image = rasterize(source, temporary)
                except OSError:
                    image = None
            if image is None:
                missing.append(entry["serviceID"])
                image = fallback_tile(entry, font)

            image = ImageOps.contain(image, ICON_SIZE)
            image_x = x + 20 + (ICON_SIZE[0] - image.width) // 2
            image_y = y + 18 + (ICON_SIZE[1] - image.height) // 2
            sheet.alpha_composite(image, (image_x, image_y))

            display_name = names.get(entry["serviceID"], entry["serviceID"])
            draw.text((x + 108, y + 24), display_name, fill=TEXT, font=font)
            draw.text((x + 108, y + 52), source_label(entry), fill=SECONDARY, font=small_font)
            draw.text((x + 108, y + 74), entry["serviceID"], fill=SECONDARY, font=small_font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(args.output, format="PNG", optimize=True)
    print(f"contact sheet: {args.output}")
    print(f"services: {len(entries)}")
    print(f"unreadable local artwork: {', '.join(missing) if missing else 'none'}")


if __name__ == "__main__":
    main()
