class_name CombatPreferences
extends Resource

@export var atk_mode: String = "manual"
@export var def_mode: String = "auto"
## Saved action defaults.
##  "attack_weapon"  → item_name (e.g. "Iron Sword") or "bare_hands"
##  "attack_action"  → action_key (e.g. "strike")
##  "magic"          → spell_name
@export var defaults: Dictionary = {}
