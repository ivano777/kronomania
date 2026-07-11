# EquipmentData — immutable config for a single piece of equipment.
# Set in .tres files; referenced by CombatantData.equipped_weapon.
class_name EquipmentData
extends Resource

## Display name shown in logs and UI.
@export var item_name: String = ""

## Forging: flat bonus added to the attack total after Keep.
@export_range(0, 5) var flat_attack_bonus: int = 0

## Warding: flat bonus added to the defense roll total after Keep.
@export_range(0, 5) var flat_guard_bonus: int = 0

## Fortitude: added to max_wounds when combat is initialised.
@export_range(0, 3) var max_wounds_bonus: int = 0

## Surge (+) or Drain (-): modifier to the attack pool size (added to net_advantage).
@export_range(-3, 3) var pool_bonus: int = 0

## Weapon tags (e.g. "Sharp", "Blunt", "TwoHanded") for skill prerequisites and slot logic.
@export var tags: PackedStringArray = PackedStringArray()

## Action-keyed modifiers. When non-empty, supersedes the deprecated flat fields above.
@export var action_modifiers: Array[ActionModifier] = []

## Combatant animation played when striking with this weapon. "" = default "attack_melee".
## Presentation only — missing animations degrade to the default pose at runtime.
@export var attack_anim: String = ""


## Returns how many hand slots this item requires, derived from tags.
## "TwoHanded" → 2; "NoHanded" → 0 (future zero-slot items); default → 1.
func get_hands_required() -> int:
	if "TwoHanded" in tags:
		return 2
	if "NoHanded" in tags:
		return 0
	return 1
