class_name CombatPreferences
extends Resource

@export var atk_mode: String = "manual"
@export var def_mode: String = "auto"
## Saved action defaults. Key format: "attack.strike.pool" → "stance"
@export var defaults: Dictionary = {}
