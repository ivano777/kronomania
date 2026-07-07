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
   | Combatant anims | — not from this pipeline — | `assets/sprites/combatants/<key>/` | converted from CC0 packs by `import_pack.py` (see combatant section) |

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

- **Global pixel grid: 640x360** (project viewport; integer-scaled 2x into a
  1280x720 window). Every sprite is authored at the size it occupies on that
  grid and installed at **scale 1** — never upscale at install time.
- **Items / icons: 16x16.** Projectiles and effects: 16x16 (up to 32x32 for
  big blasts). Characters are pack-sourced (~46–70px figures) — see the
  combatant section; keep effect sizes proportionate to them.
- Mixed sizes are allowed across frames; **all frames of one clip must share
  the same size** (validator enforces per-clip).
- Transparent background (`None`), symbol `.`
- Dark outline `#202020`, symbol `#`, around the full silhouette
- Single light source: **top-left**. Highlights up-left, shading down-right.
- Shade by **hue shift**, not just darkening (red shadows go toward purple,
  yellow highlights toward white).
- Keep silhouettes readable at 1x: if the object isn't recognizable from
  the outline alone, redesign the outline before adding detail.

## Craft rules for large effects / VFX (16px+ pieces)

1. **Unified hue-shifted ramps** — pick 3–4 ramps per sprite from the character
   palette below; shadows shift cool/purple, never just darker. One hot accent
   (blood red) per figure maximum.
2. **Selective outline** — near-black `K #181420` on the outer silhouette
   ONLY; interior forms separate by value steps, never by black lines.
3. **Cluster shading** — pixel clusters sculpt volume (chest planes, cloth
   folds); no flat fill larger than ~4x4; light from top-left.
4. **Dynamic asymmetric pose** — weight shift, weapon on a diagonal, strong
   silhouette readable at 1x. No symmetric mannequins.
5. **Heroic proportions** — small head (~1:6 of figure), long legs, oversized
   weapons. Draw weapons as separate solid parts blitted over the body
   (inline weapon pixels smear into the silhouette).

### Extended palette (large effects, ramp-shaded pieces)

```
K c #181420   outline / darkest (purple-black)
A c #2E3A44   steel dark        B c #51707D   steel mid
C c #7FA5AD   steel light       D c #C6E2DE   steel glint
E c #2E1622   wine darkest      F c #5C2438   wine dark      N c #93424E   wine light
P c #847258   parchment dark    Q c #BFA98C   parchment mid  w c #EFDFC0   parchment light
T c #7A4A44   skin dark         s c #B0745C   skin shadow    S c #E8B088   skin light
U c #C89040   gold              V c #F0C060   gold bright
R c #A82838   blood red         r c #D84848   blood light
l c #3E5A22   goblin dark       L c #6E923A   goblin mid     X c #A6C05C   goblin light
h c #4E3018   hair dark         H c #6B4226   hair brown
```

### Icon / effect palette (16px items — legacy, still canonical for icons)

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

## Combatant battle sprites — SOURCED FROM CC0 PACKS, NOT THIS PIPELINE

Combatant art (player/grunt/soldier/knight) is **not authored as XPM**. It is
converted from CC0 asset packs (LuizMelo, itch.io — see
`assets/sprites/combatants/LICENSE.md`) by `tools/sprites/import_pack.py`
driven by `tools/sprites/packs.json`:

- Manifest maps pack strips → anims (`idle`/`attack_melee`/`cast_spell`/
  `hurt`/`die`) with fps/loop; `flip: true` mirrors a left-facing pack to the
  project's facing-RIGHT convention (player is `flip_h`-mirrored in-game to
  face the enemies on its left; enemies render unflipped).
- Converter slices horizontal strips (square frames), crops to the **union
  content bbox across all of a character's anims** (keeps feet aligned), and
  emits `assets/sprites/combatants/<key>/<anim>_sheet.{png,json}` — the
  format `SpriteRegistry.get_combatant_frames()` loads.
- `die` must have `loop: false` (AnimatedSprite2D freezes on the last frame =
  corpse). `Combatant.gd` returns to idle on `animation_finished` for the
  other non-looping anims.
- Pack ZIPs live in `tools/sprites/packs/` (gitignored); re-download via the
  LICENSE.md links, re-run `python tools/sprites/import_pack.py`, then
  `"$GODOT" --headless --import --path .`.
- To swap or add a combatant: verify the pack license (CC0 preferred), add a
  manifest entry, convert, update `tests/integration/test_sprite_registry.gd`.

**This XPM pipeline's scope: icons, spell/skill VFX, particles, effects, UI
art** — everything except combatants.

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
