# Group 8 — Sprite Registry & Art Infrastructure

Convention-based asset loader. Drop a PNG in the right folder with the right name; the system picks
it up automatically — no `.tres` editing required.

**Scope:** `SpriteRegistry` autoload + combatant sprite wiring in `Combatant.gd`.
UI icon display (campfire weapon selector, spell selector, constellation node icons) is deferred.

---

## Folder structure & naming convention

```
assets/
  sprites/
    combatants/
      player/    idle.png  attack_melee.png  cast_spell.png  hurt.png  die.png
      grunt/     idle.png  attack_melee.png  cast_spell.png  hurt.png  die.png
      soldier/   idle.png  ...
      knight/    idle.png  ...
    icons/
      weapons/   iron_sword.png   crude_club.png   greatsword.png   heater_shield.png
      spells/    fire_orb.png     fireball.png     void_bolt.png    ...  (all 9 spells)
      nodes/     dom_core.png     dom_brutal.png   neg_core.png     ...  (all 50 nodes)
```

**Key derivation rules:**

| Source | Field used | Derivation | Example |
|--------|-----------|------------|---------|
| Combatant | `combatant_name` | `.to_lower().replace(" ", "_")` | `"Grunt"` → `grunt/` |
| Weapon icon | `item_name` | `.to_lower().replace(" ", "_")` | `"Iron Sword"` → `iron_sword.png` |
| Spell icon | `spell_name` | `.to_lower().replace(" ", "_")` | `"Fire Orb"` → `fire_orb.png` |
| Node icon | `node_id` | direct (already snake_case) | `"dom_core"` → `dom_core.png` |

Animation names match the existing stub API on `Combatant.gd`:
`idle` · `attack_melee` · `cast_spell` · `hurt` · `die`

---

## Files to create / modify

### 1. `autoloads/SpriteRegistry.gd` (new)

```gdscript
extends Node

const _ICON_ROOT := "res://assets/sprites/icons/"
const _COMB_ROOT := "res://assets/sprites/combatants/"
const _ANIM_NAMES := ["idle", "attack_melee", "cast_spell", "hurt", "die"]

# Converts a display name to a file-system key.
static func icon_key(display_name: String) -> String:
    return display_name.to_lower().replace(" ", "_")

# Returns Texture2D or null. Prints a warning on miss so missing art is easy to spot.
func get_icon(category: String, key: String) -> Texture2D:
    var path := "%s%s/%s.png" % [_ICON_ROOT, category, key]
    if ResourceLoader.exists(path):
        return load(path) as Texture2D
    push_warning("SpriteRegistry: missing icon — %s" % path)
    return null

# Builds SpriteFrames from per-animation PNGs in combatants/{key}/.
# Returns null if no PNGs are found (caller keeps the ColorRect fallback).
func get_combatant_frames(combatant_name: String) -> SpriteFrames:
    var key := combatant_name.to_lower().replace(" ", "_")
    var frames := SpriteFrames.new()
    if frames.has_animation("default"):
        frames.remove_animation("default")
    var has_any := false
    for anim: String in _ANIM_NAMES:
        frames.add_animation(anim)
        var path := "%s%s/%s.png" % [_COMB_ROOT, key, anim]
        if ResourceLoader.exists(path):
            frames.add_frame(anim, load(path) as Texture2D)
            has_any = true
    return frames if has_any else null
```

### 2. `project.godot` (modify — `[autoload]` section)

```
SpriteRegistry="*res://autoloads/SpriteRegistry.gd"
```

### 3. `scenes/battle/Combatant.gd` (modify — `setup()` only)

```gdscript
func setup(data: CombatantData, is_player: bool) -> void:
    _name_label.text = data.combatant_name
    _body.color = COLOR_PLAYER if is_player else COLOR_ENEMY
    _sprite.flip_h = is_player
    var frames := SpriteRegistry.get_combatant_frames(data.combatant_name)
    if frames != null:
        _sprite.sprite_frames = frames
        _sprite.play("idle")
    _body.visible = _sprite.sprite_frames == null
```

---

## Deferred (not in this group)

- `CampfireScene.gd` — weapon buttons with icon + name
- `RoundHUD.gd` — spell selector entries with icon + name
- `ConstellationScene.gd` — node cards with icon (`NodeData.icon` field already exists)

---

## Validation steps

1. Headless run must be clean (no SCRIPT ERRORs).
2. `SpriteRegistry` registered as autoload — verify it loads without error in headless output.
3. Manual smoke test: drop a test PNG at `assets/sprites/combatants/grunt/idle.png`, launch the
   game, confirm the Grunt ColorRect is replaced by the sprite and `play_idle()` is called.
   Remove the PNG — confirm ColorRect returns.
