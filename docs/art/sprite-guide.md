# Sprite Import Guide

Drop a PNG in the right folder with the right name and it loads automatically —
no `.tres` editing, no code changes.

---

## How it works

`SpriteRegistry` (`autoloads/SpriteRegistry.gd`) is loaded at startup. When a scene needs
a sprite it asks the registry, which derives the file path from the resource's name and calls
`ResourceLoader.exists()` before loading. If the file is missing, a warning is printed and the
caller keeps its placeholder (a colored rectangle in battle).

---

## Combatant battle sprites

Each combatant gets its own subfolder. The folder name is the combatant's `combatant_name`
field lowercased with spaces replaced by underscores.

```
assets/sprites/combatants/
  player/
  grunt/
  soldier/
  knight/
```

Inside each folder, place one PNG per animation state. The filename must match exactly:

| File | When it plays |
|------|--------------|
| `idle.png` | Standing still between rounds |
| `attack_melee.png` | During a physical strike |
| `cast_spell.png` | During a cantrip or true spell |
| `hurt.png` | On receiving a wound |
| `die.png` | On defeat |

You don't have to supply all five — any subset works. Missing animations simply won't play
(the sprite stays on whatever frame it last showed).

**Example — adding a Grunt idle sprite:**
```
assets/sprites/combatants/grunt/idle.png
```
Launch the game and the Grunt's colored rectangle is replaced by the sprite.

**Adding a new enemy combatant:**
If a new `CombatantData` is added with `combatant_name = "Bandit"`, create:
```
assets/sprites/combatants/bandit/idle.png   ← minimum to replace the placeholder
assets/sprites/combatants/bandit/hurt.png
... etc.
```
No code change needed.

---

## Icons (weapons · spells · nodes)

Static icons live under `assets/sprites/icons/`, split by category:

```
assets/sprites/icons/
  weapons/
  spells/
  nodes/
```

### Naming convention

**Weapons** — derive from `EquipmentData.item_name`: lowercase, spaces → underscores.

| item_name | File |
|-----------|------|
| `"Iron Sword"` | `weapons/iron_sword.png` |
| `"Crude Club"` | `weapons/crude_club.png` |
| `"Greatsword"` | `weapons/greatsword.png` |
| `"Heater Shield"` | `weapons/heater_shield.png` |

**Spells** — derive from `SpellData.spell_name`: same rule.

| spell_name | File |
|------------|------|
| `"Fire Orb"` | `spells/fire_orb.png` |
| `"Void Bolt"` | `spells/void_bolt.png` |
| `"Arcane Touch"` | `spells/arcane_touch.png` |
| `"Arcane Bolt"` | `spells/arcane_bolt.png` |
| *(all 9 spells follow the same pattern)* | |

**Constellation nodes** — use `NodeData.node_id` directly (already snake_case, no conversion needed).

| node_id | File |
|---------|------|
| `"dom_core"` | `nodes/dom_core.png` |
| `"fire_magic_1"` | `nodes/fire_magic_1.png` |
| `"minor_studies"` | `nodes/minor_studies.png` |
| *(all 50 nodes follow the same pattern)* | |

> **Note:** Icon display in the campfire weapon selector, spell selector panel, and constellation
> is not yet wired into the UI — that's the next art-pass task. The registry already loads the
> icons; they just aren't rendered anywhere yet.

---

## Verifying your sprite loaded

Run the game normally. If a combatant sprite loads correctly, the colored rectangle disappears and
the image plays `idle` automatically.

For icons (once UI wiring is done), the icon will appear next to the item name.

**If the sprite doesn't appear**, check the Godot Output panel for a line like:
```
SpriteRegistry: missing icon — res://assets/sprites/icons/weapons/iron_sword.png
```
This means the file path didn't match. Double-check:
- The folder is under `assets/sprites/` (case-sensitive on non-Windows platforms)
- The filename matches the derivation rule exactly (all lowercase, underscores not spaces, `.png` extension)
- The file was saved and Godot has imported it (a `.import` sidecar file should appear next to the PNG after the first run)

---

## Quick reference

| What you're adding | Where it goes | Name rule |
|--------------------|---------------|-----------|
| Combatant animation | `assets/sprites/combatants/{name}/` | `idle` · `attack_melee` · `cast_spell` · `hurt` · `die` |
| Weapon icon | `assets/sprites/icons/weapons/` | `item_name` → lowercase + underscores |
| Spell icon | `assets/sprites/icons/spells/` | `spell_name` → lowercase + underscores |
| Node icon | `assets/sprites/icons/nodes/` | `node_id` (already snake_case) |
