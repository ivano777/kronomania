# PlayerProgression — owns the player's Constellation state across scenes.
# Tracks unlocked nodes and available points. CombatManager reads from this
# at start_combat() to wire tier and training effects into the roll engine.
extends Node

const ALL_NODES: Array = [
	preload("res://resources/data/nodes/core_dominion_1.tres"),
	preload("res://resources/data/nodes/core_dominion_2.tres"),
	preload("res://resources/data/nodes/core_negation_1.tres"),
	preload("res://resources/data/nodes/core_negation_2.tres"),
	preload("res://resources/data/nodes/core_ingenuity_1.tres"),
	preload("res://resources/data/nodes/core_ingenuity_2.tres"),
	preload("res://resources/data/nodes/training_keep_1.tres"),
	preload("res://resources/data/nodes/training_keep_2.tres"),
	preload("res://resources/data/nodes/ability_minor_studies.tres"),
	preload("res://resources/data/nodes/ability_spellcasting.tres"),
	preload("res://resources/data/nodes/ability_sure_footed.tres"),
	preload("res://resources/data/nodes/fire_magic_1.tres"),
	preload("res://resources/data/nodes/fire_magic_2.tres"),
	preload("res://resources/data/nodes/fire_magic_3.tres"),
	preload("res://resources/data/nodes/fire_magic_4.tres"),
	preload("res://resources/data/nodes/arcane_1.tres"),
	preload("res://resources/data/nodes/arcane_2.tres"),
	preload("res://resources/data/nodes/arcane_3.tres"),
	preload("res://resources/data/nodes/flavor_warrior_oath.tres"),
]

var unlocked_nodes: Array[NodeData] = []
## Starting budget; reward integration (Group 5) will add points after each duel.
var available_points: int = 99

## Slot-budget counters for the current tier (reset on tier advance).
## Core nodes cost 2 combat slots; Training / Ability cost 1; Flavor costs 1 from the Flavor budget.
var tier_combat_spent: int = 0
var tier_flavor_spent: int = 0

var _tier: int = 1


func _slot_cost(node: NodeData) -> int:
	return 2 if node.category == "Core" else 1


func can_unlock(node: NodeData) -> bool:
	if is_unlocked(node):
		return false
	if available_points < node.unlock_cost:
		return false
	if _tier < node.required_tier:
		return false
	for prereq in node.prerequisites:
		if not is_unlocked(prereq):
			return false
	if node.category == "Flavor":
		return tier_flavor_spent < 2
	return tier_combat_spent + _slot_cost(node) <= 5


func unlock(node: NodeData) -> void:
	if not can_unlock(node):
		return
	unlocked_nodes.append(node)
	available_points -= node.unlock_cost
	if node.category == "Flavor":
		tier_flavor_spent += 1
	else:
		tier_combat_spent += _slot_cost(node)
	if tier_combat_spent >= 5 and tier_flavor_spent >= 2 and _tier < 4:
		_tier += 1
		tier_combat_spent = 0
		tier_flavor_spent = 0


## Resets progression to the initial state (debug use).
func reset() -> void:
	unlocked_nodes.clear()
	_tier = 1
	tier_combat_spent = 0
	tier_flavor_spent = 0
	available_points = 5


func is_unlocked(node: NodeData) -> bool:
	return node in unlocked_nodes


func get_category_count(category: String) -> int:
	var count := 0
	for node in unlocked_nodes:
		if node.category == category:
			count += 1
	return count


## Returns all non-cantrip SpellData known by the player (scans spells array on all unlocked nodes).
func get_known_spells() -> Array:
	var result := []
	for node in unlocked_nodes:
		for spell in node.spells:
			if not spell.is_cantrip:
				result.append(spell)
	return result


## Returns all cantrip SpellData known by the player (scans spells array on all unlocked nodes).
func get_known_cantrips() -> Array:
	var result := []
	for node in unlocked_nodes:
		for spell in node.spells:
			if spell.is_cantrip:
				result.append(spell)
	return result


## Returns current Tier (slot-budget model: 5 combat + 2 Flavor per tier; Core costs 2 slots).
func get_tier() -> int:
	return _tier
