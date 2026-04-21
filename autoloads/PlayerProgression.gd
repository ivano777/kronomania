# PlayerProgression — owns the player's Constellation state across scenes.
# Tracks unlocked nodes and available points. CombatManager reads from this
# at start_combat() to wire tier and training effects into the roll engine.
extends Node

const ALL_NODES: Array = [
	preload("res://resources/data/nodes/core_dominion_1.tres"),
	preload("res://resources/data/nodes/training_keep_1.tres"),
	preload("res://resources/data/nodes/training_keep_2.tres"),
	preload("res://resources/data/nodes/ability_minor_studies.tres"),
	preload("res://resources/data/nodes/ability_spellcasting.tres"),
	preload("res://resources/data/nodes/ability_cantrip_spark.tres"),
	preload("res://resources/data/nodes/ability_arcane_bolt.tres"),
	preload("res://resources/data/nodes/ability_fireball.tres"),
	preload("res://resources/data/nodes/ability_charm.tres"),
	preload("res://resources/data/nodes/ability_sure_footed.tres"),
	preload("res://resources/data/nodes/flavor_warrior_oath.tres"),
]

var unlocked_nodes: Array[NodeData] = []
## Starting budget; reward integration (Group 5) will add points after each duel.
var available_points: int = 5


func can_unlock(node: NodeData) -> bool:
	if is_unlocked(node):
		return false
	if available_points < node.unlock_cost:
		return false
	if node.prerequisite != null and not is_unlocked(node.prerequisite):
		return false
	return true


func unlock(node: NodeData) -> void:
	if not can_unlock(node):
		return
	unlocked_nodes.append(node)
	available_points -= node.unlock_cost


## Resets progression to the initial state (debug use).
func reset() -> void:
	unlocked_nodes.clear()
	available_points = 5


func is_unlocked(node: NodeData) -> bool:
	return node in unlocked_nodes


func get_category_count(category: String) -> int:
	var count := 0
	for node in unlocked_nodes:
		if node.category == category:
			count += 1
	return count


## Returns all non-cantrip SpellData known by the player (effect_type="spell", is_cantrip=false).
func get_known_spells() -> Array:
	var result := []
	for node in unlocked_nodes:
		if node.effect_type == "spell" and node.spell != null and not node.spell.is_cantrip:
			result.append(node.spell)
	return result


## Returns all cantrip SpellData known by the player (effect_type="spell", is_cantrip=true).
func get_known_cantrips() -> Array:
	var result := []
	for node in unlocked_nodes:
		if node.effect_type == "spell" and node.spell != null and node.spell.is_cantrip:
			result.append(node.spell)
	return result


## Returns current Tier based on breadth: min nodes per category + 1, capped at 4.
## T2 = 1 per cat, T3 = 2 per cat, T4 = 3 per cat (rules: progression/tiers.md).
func get_tier() -> int:
	var min_count := 999
	for cat in ["Core", "Training", "Ability", "Flavor"]:
		min_count = mini(min_count, get_category_count(cat))
	if min_count == 999:
		return 1
	return mini(min_count + 1, 4)
