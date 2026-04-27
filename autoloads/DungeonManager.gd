# DungeonManager — tracks a dungeon run: enemy sequence, victory/defeat, point rewards.
# Each encounter is an Array[CombatantData]; parallel encounters have more than one entry.
extends Node

const ENCOUNTERS: Array = [
	[preload("res://resources/data/enemy_grunt.tres")],                         # 0 — solo Grunt
	[preload("res://resources/data/enemies/enemy_soldier.tres")],               # 1 — solo Soldier
	[preload("res://resources/data/enemy_grunt.tres"),                          # 2 — parallel Grunts
	 preload("res://resources/data/enemy_grunt.tres")],
	[preload("res://resources/data/enemies/enemy_knight.tres")],                # 3 — solo Knight
]

const ENCOUNTER_CHAIN: Array = [false, false, false, false]

const POINTS_PER_VICTORY: int = 1

var _current_index: int = 0
var run_active: bool = false
var last_result: String = ""  # "victory" | "defeat" | ""
var _last_chain: bool = false


func start_run() -> void:
	assert(ENCOUNTER_CHAIN.size() == ENCOUNTERS.size(),
		"DungeonManager: ENCOUNTER_CHAIN and ENCOUNTERS must be the same length.")
	_current_index = 0
	run_active = true
	last_result = ""
	_last_chain = false


func current_enemies() -> Array:
	if run_active and _current_index < ENCOUNTERS.size():
		return ENCOUNTERS[_current_index]
	return []


func on_victory() -> void:
	PlayerProgression.grant_points(POINTS_PER_VICTORY)
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


func has_next_enemy() -> bool:
	return run_active and _current_index < ENCOUNTERS.size()


func is_run_complete() -> bool:
	return not run_active and last_result == "victory"


func enemies_cleared() -> int:
	return _current_index


func enemies_total() -> int:
	return ENCOUNTERS.size()


func serialize() -> Dictionary:
	return {
		"run_active":  run_active,
		"enemy_index": _current_index,
		"last_result": last_result,
	}


func deserialize(data: Dictionary) -> void:
	run_active     = bool(data.get("run_active", false))
	_current_index = int(data.get("enemy_index", 0))
	last_result    = str(data.get("last_result", ""))
