---
name: pixel-sprites
description: >
  Create pixel-art sprites for Kronomania game objects (items, potions,
  spells, projectiles, UI icons). Use this skill whenever a new game object
  is created that needs a visual asset, when the user asks to generate
  sprites for existing objects, or when an animation clip is needed.
  Covers authoring XPM frames, validating them, compiling to PNG /
  sprite sheets, and wiring the texture into the Godot resource.
---

# Pixel Sprites for Kronomania

## Pipeline overview

Sprites are authored as **XPM text frames** (1 char = 1 pixel), validated and
compiled to PNG by `tools/sprites/compile.py` (requires Pillow —
`pip install -r tools/sprites/requirements.txt`). Never draw PNGs directly and
never skip validation.

```
tools/sprites/frames/*.xpm   ->  compile.py  ->  out/frames/*.png  + out/preview/*@8x.png
tools/sprites/clips.json     ->  compile.py  ->  out/<Clip>_sheet.png + .json (+ preview)
```

A PostToolUse hook auto-runs `compile.py --check` on every `.xpm` /
`clips.json` write — validation errors come back immediately; fix them before
anything else.

## Mandatory workflow

1. **Author** the frame in `tools/sprites/frames/<object_name>.xpm`.
2. **Validate**: `python tools/sprites/compile.py --check tools/sprites`
   - Errors report file, line, pixel row/column. Fix and re-check until clean.
   - Never proceed with validation errors. (The hook already runs this on
     save; a clean hook pass counts.)
3. **Compile**: `python tools/sprites/compile.py tools/sprites`
4. **Visual self-check**: view `tools/sprites/out/preview/<name>@8x.png`
   (Read tool renders it). Judge against the checklist below. Iterate at
   least once before installing.
5. **Install** — copy from `tools/sprites/out/` into the game's
   convention-based folders (loaded by `SpriteRegistry`, **no `.tres` editing**):

   | Asset kind | Copy | Install to | Key rule |
   |---|---|---|---|
   | Weapon icon | `out/frames/<key>.png` | `assets/sprites/icons/weapons/<key>.png` | `item_name.to_lower().replace(" ", "_")` |
   | Spell icon | `out/frames/<key>.png` | `assets/sprites/icons/spells/<key>.png` | `spell_name.to_lower().replace(" ", "_")` |
   | Node icon | `out/frames/<key>.png` | `assets/sprites/icons/nodes/<key>.png` | `node_id` as-is |
   | Item/consumable icon | `out/frames/<key>.png` | `assets/sprites/icons/items/<key>.png` | future item system; same lowering rule |
   | Animated effect | `out/<Clip>_sheet.png` + `out/<Clip>_sheet.json` | `assets/sprites/effects/` | clip `name` from clips.json, verbatim |

6. **Import**: run `"$GODOT" --headless --import --path .` so Godot generates
   the `.png.import` file — without it the texture is invisible to
   `ResourceLoader`. Commit the PNG **and** its `.import` (and the sheet JSON).
7. **Consume**: icons load at runtime via
   `SpriteRegistry.get_icon(category, key)`; effect clips via
   `SpriteRegistry.get_effect_frames(clip_name)` (returns `SpriteFrames`,
   animation `"default"`, fps/loop from the metadata JSON). Both return `null`
   + `push_warning` on miss. Verify with
   `python scripts/run_tests.py` (`tests/integration/test_sprite_registry.gd`
   covers the loader) — or at minimum a clean headless run.

## Canvas and style rules

- **Items / icons: 16x16.** Projectiles and effects: 16x16. Larger objects: 32x32 max.
- Mixed sizes are allowed across frames; **all frames of one clip must share
  the same size** (validator enforces per-clip).
- Transparent background (`None`), symbol `.`
- Dark outline `#202020`, symbol `#`, around the full silhouette
- Single light source: **top-left**. Highlights up-left, shading down-right.
- Shade by **hue shift**, not just darkening (red shadows go toward purple,
  yellow highlights toward white).
- Keep silhouettes readable at 1x: if the object isn't recognizable from
  the outline alone, redesign the outline before adding detail.

## Standard material palettes (reuse for coherence)

Always reuse these symbols/colors so the item set looks consistent:

```
# c #202020   outline
w c #FFF4C0   hot core / strong highlight
G c #C0C8D0   glass light      g c #708090   glass dark
M c #B8B8C0   metal light      m c #606070   metal dark
W c #A0703C   wood light       d c #6B4A26   wood dark
R c #D83030   liquid red       r c #8E1A28   liquid red shadow
B c #3878D8   liquid blue      b c #22448E   liquid blue shadow
V c #38B848   liquid green     v c #1E6E30   liquid green shadow
o c #FFB000   fire yellow      x c #FF6A00   fire orange
```

Declare in each XPM only the symbols actually used. A healing potion is
typically: `.` `#` `G` `g` `R` `r` `w` (glass flask, red liquid, highlight).

## XPM template

```
/* XPM */
static char *healing_potion[] = {
"16 16 7 1",
". c None",
"# c #202020",
"G c #C0C8D0",
"g c #708090",
"R c #D83030",
"r c #8E1A28",
"w c #FFF4C0",
"<16 rows of exactly 16 chars>"
};
```

Header is `W H ncolors chars_per_pixel` — keep chars_per_pixel = 1.
Every row must be exactly W characters; the validator enforces this.

## Animations

Only for effects (projectiles, explosions, buffs). Add frames
`<name>_start / _mid / _end` (or more) and register a clip in
`tools/sprites/clips.json`:

```json
{ "name": "Fireball", "frames": ["fireball_start","fireball_mid","fireball_end"],
  "fps": 12, "loop": true }
```

The compiler emits a horizontal strip sheet plus metadata
(`frame_width`, `frame_count`, `fps`, `loop`). Installed under
`assets/sprites/effects/`, the pair is loaded by
`SpriteRegistry.get_effect_frames("<Clip>")` — sheet is sliced into
`AtlasTexture` frames automatically. (Reference sample: the Fireball clip,
also used as the loader's test fixture — don't delete it.)

## Out of scope

Combatant battle sprites (`assets/sprites/combatants/<key>/idle.png` etc.)
are larger multi-animation art — not authorable at 16–32 px. Leave them to a
dedicated art pass.

## Quality checklist (before declaring done)

- [ ] `--check` passes with zero errors (hook or manual)
- [ ] Silhouette readable at 1x
- [ ] Outline closed, no stray pixels outside it
- [ ] Standard material palette used
- [ ] Light from top-left
- [ ] Viewed `out/preview/<name>@8x.png` and iterated at least once
- [ ] PNG installed under `assets/sprites/` per the table (correct key name)
- [ ] `"$GODOT" --headless --import --path .` run; `.png.import` exists and is committed
- [ ] Tests + headless still green
