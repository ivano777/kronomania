#!/usr/bin/env python3
"""Bakes two-tone 9-slice UI textures from the Kenney Fantasy UI Borders pack.

The Kenney "Default" panels are flat white silhouettes (border and fill are
the same white), so a plain modulate gives no visible frame. This script
composites a real two-tone frame:

    fill  = Panel/panel-<idx>.png              (full silhouette)  -> bg colour
    ring  = Transparent center/panel-...-<idx>  (border only)      -> border colour

Output (committed) — one PNG per themed look:

    assets/sprites/ui/panel.png
    assets/sprites/ui/button_<state>.png   (normal|hover|pressed|disabled|focus)

Colours mirror the StyleBoxFlat values in theme/dark_fantasy.tres so the skin
reads identically, just framed. Source pack (CC0):
    https://kenney.nl/assets/fantasy-ui-borders
Staged (gitignored) at tools/sprites/packs/kenney_fantasy_ui/.

Usage:
    python tools/sprites/bake_ui.py            # write textures + previews
    python tools/sprites/bake_ui.py --check    # report only, no writes
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).parent.parent.parent
PACK = Path(__file__).parent / "packs" / "kenney_fantasy_ui" / "PNG" / "Default"
DEST = ROOT / "assets" / "sprites" / "ui"
PREVIEW = Path(__file__).parent / "out" / "preview"


def _c(*rgb: float) -> tuple:
    return tuple(int(round(v * 255)) for v in rgb)


# (fill_rgb, ring_rgba) — from theme/dark_fantasy.tres StyleBoxFlat entries.
LOOKS = {
    "panel":           (_c(0.10, 0.09, 0.15), _c(0.30, 0.25, 0.45) + (255,)),
    "button_normal":   (_c(0.14, 0.12, 0.22), _c(0.30, 0.25, 0.45) + (255,)),
    "button_hover":    (_c(0.22, 0.18, 0.35), _c(0.50, 0.40, 0.70) + (255,)),
    "button_pressed":  (_c(0.32, 0.25, 0.48), _c(0.85, 0.70, 0.20) + (255,)),
    "button_disabled": (_c(0.10, 0.09, 0.15), _c(0.20, 0.18, 0.28) + (255,)),
    # focus: transparent fill, gold ring only (drawn over the normal box).
    "button_focus":    (None,                 _c(0.85, 0.70, 0.20) + (204,)),
}
# Frame index per element (Kenney panel variant). idx 15 = plain 2px-stroke
# rounded-rect frame; consistent across panels and buttons at this scale
# (ornate corner variants render as heavy brackets on tiny controls).
FRAME = {}
DEFAULT_FRAME = 15
MARGIN = 6  # 9-slice corner size in source pixels


def _masks(idx: int):
    full = Image.open(PACK / "Panel" / f"panel-{idx:03d}.png").convert("RGBA").getchannel("A")
    ring = Image.open(
        PACK / "Transparent center" / f"panel-transparent-center-{idx:03d}.png"
    ).convert("RGBA").getchannel("A")
    return full, ring


def bake(name: str, fill, ring_rgba, check: bool) -> Image.Image:
    idx = FRAME.get(name.split("_")[0], DEFAULT_FRAME)
    full, ring = _masks(idx)
    out = Image.new("RGBA", full.size, (0, 0, 0, 0))
    if fill is not None:
        out.paste(fill + (255,), (0, 0), full)
    out.paste(ring_rgba, (0, 0), ring)
    print(f"[{name}] frame {idx}  {out.size}")
    if not check:
        DEST.mkdir(parents=True, exist_ok=True)
        out.save(DEST / f"{name}.png")
    return out


def nine_slice(tex: Image.Image, w: int, h: int, m: int) -> Image.Image:
    """Emulate Godot StyleBoxTexture 9-slice (corners 1:1, edges/center stretched)."""
    tw, th = tex.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    xs_s = [0, m, tw - m, tw]
    ys_s = [0, m, th - m, th]
    xs_d = [0, m, w - m, w]
    ys_d = [0, m, h - m, h]
    for r in range(3):
        for c in range(3):
            piece = tex.crop((xs_s[c], ys_s[r], xs_s[c + 1], ys_s[r + 1]))
            dw = xs_d[c + 1] - xs_d[c]
            dh = ys_d[r + 1] - ys_d[r]
            if dw <= 0 or dh <= 0:
                continue
            piece = piece.resize((dw, dh), Image.NEAREST)
            out.alpha_composite(piece, (xs_d[c], ys_d[r]))
    return out


def main() -> None:
    check = "--check" in sys.argv
    if not PACK.is_dir():
        raise SystemExit(f"Kenney pack not staged at {PACK}")
    baked = {name: bake(name, fill, ring, check) for name, (fill, ring) in LOOKS.items()}
    # Preview: a mock button row and a panel at design scale, upscaled 4x.
    PREVIEW.mkdir(parents=True, exist_ok=True)
    bg = Image.new("RGBA", (240, 90), _c(0.06, 0.06, 0.09) + (255,))
    bg.alpha_composite(nine_slice(baked["panel"], 150, 80, MARGIN), (10, 5))
    bg.alpha_composite(nine_slice(baked["button_normal"], 90, 18, MARGIN), (20, 15))
    bg.alpha_composite(nine_slice(baked["button_hover"], 90, 18, MARGIN), (20, 38))
    bg.alpha_composite(nine_slice(baked["button_pressed"], 90, 18, MARGIN), (20, 61))
    bg = bg.resize((240 * 4, 90 * 4), Image.NEAREST)
    bg.convert("RGB").save(PREVIEW / "ui_skin_mock@4x.png")
    print(f"preview -> {PREVIEW / 'ui_skin_mock@4x.png'}")
    print("OK (check)" if check else "OK")


if __name__ == "__main__":
    main()
