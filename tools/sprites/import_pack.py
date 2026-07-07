#!/usr/bin/env python3
"""Converts CC0 asset-pack sprite strips into the project's combatant format.

Reads tools/sprites/packs.json, slices each horizontal strip (square frames:
frame_width == sheet_height), computes the union content bbox across ALL of a
character's animations (keeps feet/baseline aligned between anims), crops
every frame to that box, and writes:

    assets/sprites/combatants/<key>/<anim>_sheet.png
    assets/sprites/combatants/<key>/<anim>_sheet.json

— the exact format SpriteRegistry._add_sheet_animation() loads.

Usage:
    python tools/sprites/import_pack.py [--check]

--check validates sources and prints the crop report without writing.
"""

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).parent.parent.parent
PACKS = Path(__file__).parent / "packs"
MANIFEST = Path(__file__).parent / "packs.json"
DEST = ROOT / "assets" / "sprites" / "combatants"


def frames_of(sheet: Image.Image, flip: bool):
    """Split a horizontal strip of square frames; optionally mirror each."""
    fh = sheet.height
    if sheet.width % fh:
        raise SystemExit(f"non-square frames: {sheet.width}x{fh}")
    out = []
    for i in range(sheet.width // fh):
        fr = sheet.crop((i * fh, 0, (i + 1) * fh, fh))
        if flip:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        out.append(fr)
    return out


def union_bbox(all_frames):
    box = None
    for fr in all_frames:
        b = fr.getbbox()
        if b is None:
            continue
        box = b if box is None else (
            min(box[0], b[0]), min(box[1], b[1]),
            max(box[2], b[2]), max(box[3], b[3]))
    return box


def main(check_only: bool):
    cfg = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for char in cfg["characters"]:
        key, src_dir, flip = char["key"], PACKS / char["dir"], char["flip"]
        per_anim = {}
        for anim, meta in char["anims"].items():
            sheet_path = src_dir / meta["file"]
            if not sheet_path.exists():
                raise SystemExit(f"missing source: {sheet_path}")
            per_anim[anim] = frames_of(Image.open(sheet_path).convert("RGBA"), flip)

        box = union_bbox([f for frs in per_anim.values() for f in frs])
        bw, bh = box[2] - box[0], box[3] - box[1]
        print(f"{key}: crop {bw}x{bh} (from {next(iter(per_anim.values()))[0].width}px frames)")
        if check_only:
            continue

        out_dir = DEST / key
        out_dir.mkdir(parents=True, exist_ok=True)
        for anim, frs in per_anim.items():
            meta = char["anims"][anim]
            cropped = [f.crop(box) for f in frs]
            strip = Image.new("RGBA", (bw * len(cropped), bh))
            for i, f in enumerate(cropped):
                strip.paste(f, (i * bw, 0))
            strip.save(out_dir / f"{anim}_sheet.png")
            (out_dir / f"{anim}_sheet.json").write_text(json.dumps({
                "name": f"{key}_{anim}",
                "sheet": f"{anim}_sheet.png",
                "frame_width": bw,
                "frame_height": bh,
                "frame_count": len(cropped),
                "fps": meta["fps"],
                "loop": meta["loop"],
                "layout": "horizontal_strip",
                "source": char["source"],
            }, indent=2), encoding="utf-8")
            print(f"  {anim}: {len(cropped)} frames @ {meta['fps']} fps"
                  f"{' (loop)' if meta['loop'] else ''}")
    if not check_only:
        print(f"Output in {DEST}")


if __name__ == "__main__":
    main("--check" in sys.argv[1:])
