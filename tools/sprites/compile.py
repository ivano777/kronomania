#!/usr/bin/env python3
"""
SPA pipeline: XPM frames + clips.json -> PNG, sprite sheet, metadata.

Uso:
    python compile.py [--check] [--scale N] [project_dir]

Struttura progetto:
    frames/*.xpm     frame in formato XPM standard
    clips.json       definizione animazioni
    out/             output generato (frames/, preview/, sheet + json)

I frame possono avere dimensioni diverse tra loro; i frame di uno stesso
clip devono avere tutti la stessa dimensione. Ogni build emette anche
out/preview/<nome>@8x.png (ingrandito NEAREST) per il controllo visivo.

Errori di validazione riportati per file e per riga, pensati per
il feedback loop con un LLM che scrive/corregge i frame.
"""

import json
import re
import sys
from pathlib import Path

from PIL import Image

# ---------------------------------------------------------------- errori

class SpaError(Exception):
    def __init__(self, file, line, code, msg):
        self.file, self.line, self.code, self.msg = file, line, code, msg
        loc = f"{file}" + (f":{line}" if line else "")
        super().__init__(f"[{code}] {loc}: {msg}")


# ---------------------------------------------------------------- parser XPM

_HEX6 = re.compile(r"^#([0-9A-Fa-f]{6})$")
_HEX8 = re.compile(r"^#([0-9A-Fa-f]{8})$")

def _parse_color(spec, file, line):
    """Ritorna RGBA. Supporta 'None' (trasparente), #RRGGBB, #RRGGBBAA."""
    if spec.lower() == "none":
        return (0, 0, 0, 0)
    m = _HEX8.match(spec)
    if m:
        v = m.group(1)
        return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4, 6))
    m = _HEX6.match(spec)
    if m:
        v = m.group(1)
        return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    raise SpaError(file, line, "INVALID_COLOR",
                   f"colore non riconosciuto: {spec!r} (usa None, #RRGGBB o #RRGGBBAA)")


def _xpm_strings(path):
    """Estrae le stringhe C ("...") dal file XPM, con numero di riga."""
    out = []
    text = Path(path).read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), 1):
        # ignora commenti /* */ a riga intera e codice C
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
            out.append((lineno, m.group(1)))
    return out


def parse_xpm(path):
    """Parsa un XPM (1 char per pixel). Ritorna (w, h, pixels RGBA row-major)."""
    file = Path(path).name
    strings = _xpm_strings(path)
    if not strings:
        raise SpaError(file, None, "EMPTY_FILE", "nessuna stringa XPM trovata")

    # header: "W H ncolors chars_per_pixel"
    lineno, header = strings[0]
    parts = header.split()
    if len(parts) < 4:
        raise SpaError(file, lineno, "BAD_HEADER",
                       f"header atteso 'W H ncolors cpp', trovato {header!r}")
    w, h, ncolors, cpp = (int(p) for p in parts[:4])
    if cpp != 1:
        raise SpaError(file, lineno, "UNSUPPORTED_CPP",
                       "supportato solo chars_per_pixel=1")

    # palette
    palette = {}
    for lineno, s in strings[1:1 + ncolors]:
        if len(s) < 1:
            raise SpaError(file, lineno, "BAD_PALETTE_ENTRY", "entry vuota")
        sym = s[0]
        m = re.search(r"\bc\s+(\S+)", s[1:])
        if not m:
            raise SpaError(file, lineno, "BAD_PALETTE_ENTRY",
                           f"manca 'c <colore>' in {s!r}")
        if sym in palette:
            raise SpaError(file, lineno, "DUPLICATE_SYMBOL",
                           f"simbolo {sym!r} già definito")
        palette[sym] = _parse_color(m.group(1), file, lineno)

    # righe pixel
    rows = strings[1 + ncolors:]
    if len(rows) != h:
        raise SpaError(file, None, "ROW_COUNT_MISMATCH",
                       f"attese {h} righe pixel, trovate {len(rows)}")

    pixels = []
    for y, (lineno, row) in enumerate(rows):
        if len(row) != w:
            raise SpaError(file, lineno, "ROW_LENGTH_MISMATCH",
                           f"riga {y}: lunghezza {len(row)}, attesa {w}")
        for x, sym in enumerate(row):
            if sym not in palette:
                raise SpaError(file, lineno, "INVALID_SYMBOL",
                               f"riga {y}, colonna {x}: simbolo {sym!r} non in palette")
            pixels.append(palette[sym])
    return w, h, pixels


def render_frame(path):
    w, h, pixels = parse_xpm(path)
    img = Image.new("RGBA", (w, h))
    img.putdata(pixels)
    return img


# ---------------------------------------------------------------- clips

def load_clips(project):
    cfg_path = project / "clips.json"
    if not cfg_path.exists():
        raise SpaError("clips.json", None, "MISSING_CLIPS", "file clips.json non trovato")
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    clips = cfg.get("clips", [])
    for c in clips:
        for key in ("name", "frames", "fps"):
            if key not in c:
                raise SpaError("clips.json", None, "BAD_CLIP",
                               f"clip senza campo obbligatorio {key!r}: {c}")
        c.setdefault("loop", False)
    return clips


# ---------------------------------------------------------------- build

PREVIEW_SCALE = 8


def build(project, scale=1, check_only=False):
    project = Path(project)
    frames_dir = project / "frames"
    out_dir = project / "out"

    # 1. parse + validazione di tutti i frame
    frame_imgs = {}
    errors = []
    for xpm in sorted(frames_dir.glob("*.xpm")):
        try:
            frame_imgs[xpm.stem] = render_frame(xpm)
        except SpaError as e:
            errors.append(e)
    if errors:
        for e in errors:
            print(f"ERRORE {e}", file=sys.stderr)
        sys.exit(1)
    if not frame_imgs:
        print("Nessun frame .xpm trovato in frames/", file=sys.stderr)
        sys.exit(1)

    print(f"OK  {len(frame_imgs)} frame validati")

    clips = load_clips(project)
    for clip in clips:
        missing = [f for f in clip["frames"] if f not in frame_imgs]
        if missing:
            print(f"ERRORE [UNKNOWN_FRAME] clip {clip['name']!r}: "
                  f"frame non trovati {missing}", file=sys.stderr)
            sys.exit(1)
        # dimensione uniforme richiesta solo all'interno dello stesso clip
        clip_sizes = {frame_imgs[f].size for f in clip["frames"]}
        if len(clip_sizes) > 1:
            print(f"ERRORE [SIZE_MISMATCH] clip {clip['name']!r}: "
                  f"frame con dimensioni diverse {sorted(clip_sizes)}",
                  file=sys.stderr)
            sys.exit(1)
    print(f"OK  {len(clips)} clip validate")

    if check_only:
        return

    # 2. output
    out_dir.mkdir(exist_ok=True)
    (out_dir / "frames").mkdir(exist_ok=True)
    (out_dir / "preview").mkdir(exist_ok=True)

    def up(img, factor):
        return img.resize((img.width * factor, img.height * factor), Image.NEAREST) \
            if factor > 1 else img

    for name, img in frame_imgs.items():
        up(img, scale).save(out_dir / "frames" / f"{name}.png")
        up(img, PREVIEW_SCALE).save(
            out_dir / "preview" / f"{name}@{PREVIEW_SCALE}x.png")

    for clip in clips:
        fw, fh = frame_imgs[clip["frames"][0]].size
        n = len(clip["frames"])
        sheet = Image.new("RGBA", (fw * n, fh))
        for i, fname in enumerate(clip["frames"]):
            sheet.paste(frame_imgs[fname], (fw * i, 0))
        up(sheet, scale).save(out_dir / f"{clip['name']}_sheet.png")
        up(sheet, PREVIEW_SCALE).save(
            out_dir / "preview" / f"{clip['name']}_sheet@{PREVIEW_SCALE}x.png")

        meta = {
            "name": clip["name"],
            "sheet": f"{clip['name']}_sheet.png",
            "frame_width": fw * scale,
            "frame_height": fh * scale,
            "frame_count": n,
            "frames": clip["frames"],
            "fps": clip["fps"],
            "loop": clip["loop"],
            "layout": "horizontal_strip",
        }
        (out_dir / f"{clip['name']}_sheet.json").write_text(
            json.dumps(meta, indent=2), encoding="utf-8")
        print(f"OK  clip {clip['name']!r}: sheet {fw*n*scale}x{fh*scale}, "
              f"{n} frame @ {clip['fps']} fps")

    print(f"Output in {out_dir}/")


if __name__ == "__main__":
    args = sys.argv[1:]
    check = "--check" in args
    scale = 1
    if "--scale" in args:
        scale = int(args[args.index("--scale") + 1])
        args.remove("--scale")
        args = [a for a in args if a != str(scale)]
    args = [a for a in args if not a.startswith("--")]
    build(args[0] if args else ".", scale=scale, check_only=check)
