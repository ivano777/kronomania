#!/usr/bin/env python3
"""Converts CC0 environment/background pack art into static scene backgrounds.

Reads tools/sprites/env.json, composites the listed layers (back -> front),
integer-upscales with NEAREST to cover the 640x360 design viewport, center-
crops, optionally darkens, and writes:

    assets/sprites/backgrounds/<key>.png

— loaded by SpriteRegistry.get_background(key).

Integer scaling keeps the source pixel grid intact (no fractional resampling
artifacts); the crop picks the horizontal/vertical center of the upscaled art.

Usage:
    python tools/sprites/import_env.py [--check]
    python tools/sprites/import_env.py --scan   # inventory images in packs/

--check validates sources and prints the report without writing.
--scan lists every image under tools/sprites/packs/ with its size (used to
       author env.json after downloading new packs).
"""

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageEnhance

ROOT = Path(__file__).parent.parent.parent
PACKS = Path(__file__).parent / "packs"
MANIFEST = Path(__file__).parent / "env.json"
DEST = ROOT / "assets" / "sprites" / "backgrounds"

VIEW_W, VIEW_H = 640, 360


def scan() -> None:
    if not PACKS.is_dir():
        raise SystemExit(f"no packs directory: {PACKS}")
    exts = {".png", ".gif", ".bmp"}
    for p in sorted(PACKS.rglob("*")):
        if p.suffix.lower() in exts:
            try:
                with Image.open(p) as im:
                    print(f"{im.size[0]:>5}x{im.size[1]:<5} {p.relative_to(PACKS)}")
            except OSError:
                print(f"  ?x?   {p.relative_to(PACKS)} (unreadable)")


def cover_int(im: Image.Image) -> Image.Image:
    """Integer-upscale (NEAREST) to cover the viewport, then center-crop."""
    factor = max(math.ceil(VIEW_W / im.width), math.ceil(VIEW_H / im.height), 1)
    im = im.resize((im.width * factor, im.height * factor), Image.NEAREST)
    left = (im.width - VIEW_W) // 2
    top = (im.height - VIEW_H) // 2
    return im.crop((left, top, left + VIEW_W, top + VIEW_H))


def build(entry: dict, check_only: bool) -> None:
    key = entry["key"]
    layers = entry["layers"]
    canvas = None
    for rel in layers:
        src = PACKS / rel
        if not src.is_file():
            raise SystemExit(f"[{key}] missing source: {src}")
        layer = cover_int(Image.open(src).convert("RGBA"))
        canvas = layer if canvas is None else Image.alpha_composite(canvas, layer)
    if canvas is None:
        raise SystemExit(f"[{key}] no layers listed")
    darken = float(entry.get("darken", 1.0))
    if darken != 1.0:
        canvas = ImageEnhance.Brightness(canvas.convert("RGB")).enhance(darken).convert("RGBA")
    print(f"[{key}] {len(layers)} layer(s) -> {VIEW_W}x{VIEW_H}"
          + (f", darken {darken}" if darken != 1.0 else ""))
    if not check_only:
        DEST.mkdir(parents=True, exist_ok=True)
        canvas.convert("RGB").save(DEST / f"{key}.png")
        print(f"        wrote {DEST / (key + '.png')}")


def main() -> None:
    if "--scan" in sys.argv:
        scan()
        return
    check_only = "--check" in sys.argv
    cfg = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for entry in cfg["backgrounds"]:
        build(entry, check_only)
    print("OK (check only — nothing written)" if check_only else "OK")


if __name__ == "__main__":
    main()
