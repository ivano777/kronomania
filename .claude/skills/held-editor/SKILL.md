---
name: held-editor
description: >
  Open the visual Held-Anchor Editor window to author hand positions and
  weapon angles for hero held-equipment overlays (combatants/<hero>/held.json).
  Use this skill whenever held-item placement needs adjusting — hands
  misaligned, weapon angle wrong, new hero or animation needs anchor tables.
  Never hand-edit anchor coordinates from pixel guesses; launch this editor
  and let the user place them visually.
---

# Held-Anchor Editor

Interactive window for authoring `assets/sprites/combatants/<hero>/held.json`
— per-frame hand anchors + weapon rotation for the held-equipment overlay
system (`SpriteRegistry` manifests, applied by `Combatant.gd`).

## Launch

```
"$GODOT" --path . tools/held_editor/HeldEditor.tscn
```

Run windowed (NOT `--headless` — it renders). The window blocks the shell
until closed; launch it in the background. Autoloads boot normally, so
`SpriteRegistry` and `Combatant` statics behave exactly like the game.

## What the user sees

Two modes, toggled by the PLAYER / ITEMS buttons top-left:

- **PLAYER mode** — hero list (only `combatants/<key>/` dirs that already
  have a `held.json`), animation list (idle / attack_melee / cast_spell /
  hurt), per-frame hand/rotation editing on the canvas. SAVE writes the
  hero manifest.
- **ITEMS mode** — held-art list (iron_sword, greatsword, crude_club,
  wizard_staff, heater_shield, arcane_focus); the item renders zoomed and
  clicking anywhere places the GRIP (yellow) crosshair on the handle pixel.
  SAVE writes `assets/sprites/held/<key>.json` (preserves `"planted"`).
  Grip edits feed the PLAYER-mode preview live (unsaved until SAVE).

PLAYER-mode layout:

- **Left**: mode toggle, hero list, animation list, SAVE button,
  unsaved-changes marker.
- **Center canvas**: the current frame zoomed, with:
  - **MAIN hand crosshair — orange**; **OFF hand crosshair — cyan**
    (legend top-right). Drag to move; integer pixel snap.
  - **Rotation gumball**: ring + lever knob around the selected hand;
    drag the knob to set the weapon angle for that frame.
  - **Live item preview** rendered with the exact runtime math (grip pixel
    pinned to the anchor, rotation pivoting at the grip). Defaults to the
    STUB sword (steel blade / gold handle zones, yellow grip cross); the
    right-panel pickers swap in any real held art (iron_sword, greatsword,
    crude_club, wizard_staff, heater_shield, arcane_focus) for both hands —
    this is the "final result" view.
- **Bottom bar**: frame stepper, PLAY (animates with items attached),
  FLIP (battle/equip orientation preview), zoom.

## Controls

| Input | Action |
|---|---|
| LMB drag crosshair | move that hand (selects it) |
| LMB drag knob | rotate weapon (5° snap; Shift = 1°) |
| Tab | switch selected hand |
| Arrows | nudge selected hand 1 px |
| Q / E | rotate −/+5° (Shift = 1°) |
| , / . | previous / next frame |
| P | play / pause animation |
| F | flip preview (battle orientation) |
| RMB / MMB drag | pan · wheel / +/− zoom |
| C / CENTER | re-center view on the character or item |
| ALL FRMS | copy selected hand's [x, y, rot] to every frame of the current anim |
| item alpha slider | preview transparency of held items (aid only, never saved) |
| behind checkbox | draw items behind the hero sprite (aid only, never saved) |
| Ctrl+S / SAVE | write the current mode's JSON |

ITEMS mode: LMB click/drag places the grip; arrows nudge it; frame
stepper / PLAY / FLIP / item pickers are hidden (not applicable).

## Data notes

- Coordinates and rotations are authored in RAW (unflipped) sheet space;
  FLIP preview only mirrors the view, values stay raw. Rotation 0° = held
  art vertical (tip up); positive = clockwise in raw facing.
- SAVE writes dense per-frame `[x, y, rot]` tables for all four anims and
  preserves legacy top-level `main` / `off` / `idle_bob` keys. Once an
  `"anims"` idle table exists it wins over legacy+bob at runtime — bob is
  baked per-frame by editing idle frames individually.
- After saving, the game picks changes up on next scene load — no import
  step needed (JSON is read directly, not a Godot resource).

## Claude workflow

1. Launch the editor for the user (background shell).
2. Tell them which hero/anim to select and what to adjust.
3. After they save and close, diff `held.json`, sanity-check values
   (in-frame bounds), and run `python scripts/run_tests.py` before shipping.
