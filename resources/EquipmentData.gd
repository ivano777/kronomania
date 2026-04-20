# EquipmentData — immutable config for a single piece of equipment.
# Set in .tres files; referenced by CombatantData.equipped_weapon.
class_name EquipmentData
extends Resource

## Display name shown in logs and UI.
@export var item_name: String = ""

## Potency — caps how much Tier is expressed: effective_tier = min(tier, potency).
@export_range(1, 4) var potency: int = 1

## Forging: flat bonus added to the attack total after Keep.
@export_range(0, 5) var flat_attack_bonus: int = 0

## Warding: flat bonus added to the defense roll total after Keep.
@export_range(0, 5) var flat_guard_bonus: int = 0

## Fortitude: added to max_wounds when combat is initialised.
@export_range(0, 3) var max_wounds_bonus: int = 0

## Surge (+) or Drain (-): modifier to the attack pool size (added to net_advantage).
@export_range(-3, 3) var pool_bonus: int = 0

## Weapon tags (e.g. "Sharp", "Blunt", "Flame") for future skill prerequisites.
@export var tags: PackedStringArray = PackedStringArray()
