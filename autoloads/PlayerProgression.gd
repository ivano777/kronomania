# PlayerProgression — owns the player's Constellation state across scenes.
# Tracks node levels and available points. CombatManager reads from this
# at start_combat() to wire tier and training effects into the roll engine.
extends Node

const ALL_NODES: Array = [
	preload("res://resources/data/nodes/dominion/dom_core.tres"),
	preload("res://resources/data/nodes/dominion/dom_wounds.tres"),
	preload("res://resources/data/nodes/dominion/dom_martial_arts.tres"),
	preload("res://resources/data/nodes/dominion/dom_melee.tres"),
	preload("res://resources/data/nodes/dominion/dom_ranged.tres"),
	preload("res://resources/data/nodes/dominion/dom_dual_wield.tres"),
	preload("res://resources/data/nodes/dominion/dom_titans_grip.tres"),
	preload("res://resources/data/nodes/dominion/dom_disarm.tres"),
	preload("res://resources/data/nodes/dominion/dom_brutal.tres"),
	preload("res://resources/data/nodes/dominion/dom_meat_grinder.tres"),
	preload("res://resources/data/nodes/dominion/dom_earthshatter.tres"),
	preload("res://resources/data/nodes/negation/neg_core.tres"),
	preload("res://resources/data/nodes/ingenuity/ing_core.tres"),
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
	preload("res://resources/data/nodes/flavors/flavor_exile_brand.tres"),
	preload("res://resources/data/nodes/flavors/flavor_blood_debt.tres"),
	preload("res://resources/data/nodes/flavors/flavor_arena_champion.tres"),
	preload("res://resources/data/nodes/flavors/flavor_hedge_knight.tres"),
	preload("res://resources/data/nodes/flavors/flavor_wanderer.tres"),
	preload("res://resources/data/nodes/flavors/flavor_iron_vow.tres"),
	preload("res://resources/data/nodes/flavors/flavor_haunted.tres"),
	preload("res://resources/data/nodes/flavors/flavor_scavenger.tres"),
	preload("res://resources/data/nodes/flavors/flavor_street_rat.tres"),
	preload("res://resources/data/nodes/flavors/flavor_noble_fallen.tres"),
	preload("res://resources/data/nodes/flavors/flavor_cursed_blood.tres"),
	preload("res://resources/data/nodes/flavors/flavor_pilgrim.tres"),
	preload("res://resources/data/nodes/flavors/flavor_mercenary.tres"),
	preload("res://resources/data/nodes/flavors/flavor_deserter.tres"),
	preload("res://resources/data/nodes/flavors/flavor_touched_by_fire.tres"),
	preload("res://resources/data/nodes/flavors/flavor_last_of_your_name.tres"),
	preload("res://resources/data/nodes/flavors/flavor_oathbreaker.tres"),
	preload("res://resources/data/nodes/flavors/flavor_relic_seeker.tres"),
	preload("res://resources/data/nodes/flavors/flavor_duel_veteran.tres"),
]

const AVAILABLE_WEAPONS: Array = [
	preload("res://resources/data/weapons/iron_sword.tres"),
	preload("res://resources/data/weapons/greatsword.tres"),
]

## Currently equipped weapon. null = fall back to player_default.tres equipped_weapon.
var equipped_weapon: EquipmentData = null

## node_levels: NodeData → int (0 = not yet purchased, 1..max_levels = current level).
var node_levels: Dictionary = {}
## Starting budget; +1 granted per combat victory (Group 5 reward loop).
var available_points: int = 3

## Slot-budget counters for the current tier (reset on tier advance).
## Core nodes cost 2 combat slots; Training / Ability cost 1; Flavor costs 1 from the Flavor budget.
var tier_combat_spent: int = 0
var tier_flavor_spent: int = 0

const MAX_TIER: int = 4
var _tier: int = 1

## Fervor state persisted across combats (Group 5). Long Rest resets to 4; Recovery clears burnout only.
var saved_fervor_size: int = 4
var saved_is_burned_out: bool = false


## Returns the current level of a node (0 = not purchased).
func get_level(node: NodeData) -> int:
	return node_levels.get(node, 0)


## Returns the level of a node looked up by its node_id string (0 if not found or not purchased).
func get_node_level_by_id(id: String) -> int:
	var n := _node_by_id(id)
	return get_level(n) if n != null else 0


func can_upgrade(node: NodeData) -> bool:
	var current := get_level(node)
	if current >= node.max_levels:
		return false
	if node.levels_data.size() <= current:
		return false
	var ld: NodeLevelData = node.levels_data[current]
	if available_points < ld.cost:
		return false
	if _tier < ld.required_tier:
		return false
	for prereq in ld.prerequisites:
		var prereq_node := _node_by_id(prereq["node_id"])
		if prereq_node == null or get_level(prereq_node) < int(prereq["required_level"]):
			return false
	if node.category == "Flavor":
		return tier_flavor_spent < 2
	return tier_combat_spent + ld.cost <= 5


func upgrade(node: NodeData) -> void:
	if not can_upgrade(node):
		return
	var current := get_level(node)
	var ld: NodeLevelData = node.levels_data[current]
	node_levels[node] = current + 1
	available_points -= ld.cost
	if node.category == "Flavor":
		tier_flavor_spent += 1
	else:
		tier_combat_spent += ld.cost
	if tier_combat_spent >= 5 and tier_flavor_spent >= 2 and _tier < MAX_TIER:
		_tier += 1
		tier_combat_spent = 0
		tier_flavor_spent = 0


## Resets progression to the initial state (debug use).
func reset() -> void:
	node_levels.clear()
	_tier = 1
	tier_combat_spent = 0
	tier_flavor_spent = 0
	available_points = 3
	saved_fervor_size = 4
	saved_is_burned_out = false
	equipped_weapon = null


func apply_long_rest() -> void:
	saved_fervor_size = 4
	saved_is_burned_out = false


func apply_recovery() -> void:
	saved_is_burned_out = false


func set_weapon(w: EquipmentData) -> void:
	equipped_weapon = w


func grant_points(amount: int) -> void:
	available_points += amount


func debug_set_points(n: int) -> void:
	available_points = maxi(0, n)


func debug_set_tier(t: int) -> void:
	_tier = clampi(t, 1, MAX_TIER)


func get_category_count(category: String) -> int:
	var count := 0
	for node in node_levels.keys():
		if (node as NodeData).category == category and node_levels[node] > 0:
			count += 1
	return count


## Returns all non-cantrip SpellData known by the player (scans spells on all purchased node levels).
func get_known_spells() -> Array:
	var result := []
	for node in node_levels.keys():
		var lvl: int = node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			for spell in nd.levels_data[i].spells:
				if not spell.is_cantrip:
					result.append(spell)
	return result


## Returns all cantrip SpellData known by the player (scans spells on all purchased node levels).
func get_known_cantrips() -> Array:
	var result := []
	for node in node_levels.keys():
		var lvl: int = node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			for spell in nd.levels_data[i].spells:
				if spell.is_cantrip:
					result.append(spell)
	return result


## Returns current Tier (slot-budget model: 5 combat + 2 Flavor per tier; Core costs 2 slots).
func get_tier() -> int:
	return _tier


func _node_by_id(id: String) -> NodeData:
	for node in ALL_NODES:
		if (node as NodeData).node_id == id:
			return node as NodeData
	push_warning("PlayerProgression: node_id '%s' not found in ALL_NODES." % id)
	return null
