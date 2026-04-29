# DungeonManager — tracks a dungeon run: enemy sequence, victory/defeat, point rewards.
# Each encounter is an Array[CombatantData]; parallel encounters have more than one entry.
extends Node

const ENCOUNTERS: Array = [
	[preload("res://resources/data/enemy_grunt.tres")],                         # 0 — chain: Grunt #1
	[preload("res://resources/data/enemy_grunt.tres")],                         # 1 — chain: Grunt #2
	[preload("res://resources/data/enemies/enemy_soldier.tres")],               # 2 — chain: Soldier → Hub
	[preload("res://resources/data/enemy_grunt.tres")],                         # 3 — chain: Grunt #1
	[preload("res://resources/data/enemy_grunt.tres")],                         # 4 — chain: Grunt #2
	[preload("res://resources/data/enemies/enemy_soldier.tres")],               # 5 — chain: Soldier → Hub
	[preload("res://resources/data/enemy_grunt.tres"),                          # 6 — parallel: Grunt + Grunt + Soldier
	 preload("res://resources/data/enemy_grunt.tres"),
	 preload("res://resources/data/enemies/enemy_soldier.tres")],
	[preload("res://resources/data/enemies/enemy_knight.tres")],                # 7 — solo Knight
]

const ENCOUNTER_CHAIN: Array = [true, true, false, true, true, false, false, false]

const POINTS_PER_VICTORY: int = 1

const _GRUNT   := preload("res://resources/data/enemy_grunt.tres")
const _SOLDIER := preload("res://resources/data/enemies/enemy_soldier.tres")
const _KNIGHT  := preload("res://resources/data/enemies/enemy_knight.tres")

var _current_index: int = 0
var run_active: bool = false
var last_result: String = ""  # "victory" | "defeat" | ""
var _last_chain: bool = false
var short_rest_used: bool = false

var is_ambush_active: bool = false
var ambush_disadvantage: int = 0  # 0 or -2 for the current ambush fight
var _ambush_enemies: Array = []


func start_run() -> void:
	assert(ENCOUNTER_CHAIN.size() == ENCOUNTERS.size(),
		"DungeonManager: ENCOUNTER_CHAIN and ENCOUNTERS must be the same length.")
	_current_index = 0
	run_active = true
	last_result = ""
	_last_chain = false
	short_rest_used = false
	is_ambush_active = false
	_ambush_enemies = []
	ambush_disadvantage = 0


func current_enemies() -> Array:
	if is_ambush_active:
		return _ambush_enemies
	if run_active and _current_index < ENCOUNTERS.size():
		return ENCOUNTERS[_current_index]
	return []


func on_victory() -> void:
	PlayerProgression.grant_points(POINTS_PER_VICTORY)
	if is_ambush_active:
		is_ambush_active = false
		_ambush_enemies = []
		ambush_disadvantage = 0
		return
	last_result = "victory"
	_last_chain = ENCOUNTER_CHAIN[_current_index]
	_current_index += 1
	if _current_index >= ENCOUNTERS.size():
		run_active = false


func was_last_fight_chained() -> bool:
	return _last_chain


func on_defeat() -> void:
	last_result = "defeat"
	run_active = false
	is_ambush_active = false
	_ambush_enemies = []
	ambush_disadvantage = 0


func has_next_enemy() -> bool:
	return run_active and _current_index < ENCOUNTERS.size()


func is_run_complete() -> bool:
	return not run_active and last_result == "victory"


func enemies_cleared() -> int:
	return _current_index


func enemies_total() -> int:
	return ENCOUNTERS.size()


func attempt_short_rest() -> void:
	if short_rest_used:
		return
	PlayerProgression.apply_short_rest()
	short_rest_used = true


func attempt_long_rest() -> Dictionary:
	PlayerProgression.apply_long_rest()
	var ambushed := randi() % 100 < (50 - PlayerProgression.luck)
	if ambushed:
		_ambush_enemies = [_pick_ambush_enemy()]
		is_ambush_active = true
		var has_disadv := randi() % 100 < (50 - PlayerProgression.luck)
		ambush_disadvantage = -2 if has_disadv else 0
	# TODO: deduct money when money system is implemented
	return {"ambushed": ambushed}


func surrender() -> Dictionary:
	_current_index = 0
	short_rest_used = false
	is_ambush_active = false
	_ambush_enemies = []
	ambush_disadvantage = 0
	PlayerProgression.saved_wounds = 0
	var lost_points := 0
	var lost_weapon := false
	if randi() % 100 < (50 - PlayerProgression.luck):
		lost_points = PlayerProgression.available_points / 2
		PlayerProgression.available_points -= lost_points
	if PlayerProgression.equipped_weapon != null \
			and randi() % 100 < (30 - PlayerProgression.luck):
		lost_weapon = true
		PlayerProgression.equipped_weapon = null
	return {"lost_points": lost_points, "lost_weapon": lost_weapon}


func serialize() -> Dictionary:
	return {
		"run_active":        run_active,
		"enemy_index":       _current_index,
		"last_result":       last_result,
		"short_rest_used":   short_rest_used,
		"is_ambush_active":  is_ambush_active,
		"ambush_disadvantage": ambush_disadvantage,
	}


func deserialize(data: Dictionary) -> void:
	run_active          = bool(data.get("run_active", false))
	_current_index      = int(data.get("enemy_index", 0))
	last_result         = str(data.get("last_result", ""))
	short_rest_used     = bool(data.get("short_rest_used", false))
	is_ambush_active    = bool(data.get("is_ambush_active", false))
	ambush_disadvantage = int(data.get("ambush_disadvantage", 0))


func _pick_ambush_enemy() -> CombatantData:
	var idx := maxi(0, _current_index - 1)
	if idx <= 1:
		return _GRUNT
	elif idx <= 5:
		return [_GRUNT, _SOLDIER][randi() % 2]
	else:
		return [_SOLDIER, _KNIGHT][randi() % 2]
