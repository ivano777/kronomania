# DungeonManager — tracks a dungeon run: enemy sequence, victory/defeat, point rewards.
# A run is a linear sequence of enemies. Call start_run() to begin; the Hub scene
# reads has_next_enemy() to decide whether to show Continue vs. Start New Run.
extends Node

const ENEMY_ROSTER: Array = [
	preload("res://resources/data/enemy_grunt.tres"),
	preload("res://resources/data/enemies/enemy_soldier.tres"),
	preload("res://resources/data/enemy_grunt.tres"),       # wave — entry 1
	preload("res://resources/data/enemy_grunt.tres"),       # wave — entry 2
	preload("res://resources/data/enemies/enemy_knight.tres"),
]

# Parallel to ENEMY_ROSTER. true = after winning THIS fight, chain to next immediately.
const ENEMY_CHAIN: Array = [
	false,  # Grunt    → Hub
	false,  # Soldier  → Hub
	true,   # Grunt #1 → chain to Grunt #2
	false,  # Grunt #2 → Hub
	false,  # Knight   → Hub (run over)
]

const POINTS_PER_VICTORY: int = 1

var _current_index: int = 0
var run_active: bool = false
var last_result: String = ""  # "victory" | "defeat" | ""
var _last_chain: bool = false


func start_run() -> void:
	assert(ENEMY_CHAIN.size() == ENEMY_ROSTER.size(),
		"DungeonManager: ENEMY_CHAIN and ENEMY_ROSTER must be the same length.")
	_current_index = 0
	run_active = true
	last_result = ""
	_last_chain = false


func current_enemy() -> CombatantData:
	if run_active and _current_index < ENEMY_ROSTER.size():
		return ENEMY_ROSTER[_current_index]
	return null


func on_victory() -> void:
	PlayerProgression.grant_points(POINTS_PER_VICTORY)
	last_result = "victory"
	_last_chain = ENEMY_CHAIN[_current_index]
	_current_index += 1
	if _current_index >= ENEMY_ROSTER.size():
		run_active = false


func was_last_fight_chained() -> bool:
	return _last_chain


func on_defeat() -> void:
	last_result = "defeat"
	run_active = false


func has_next_enemy() -> bool:
	return run_active and _current_index < ENEMY_ROSTER.size()


func is_run_complete() -> bool:
	return not run_active and last_result == "victory"


func enemies_cleared() -> int:
	return _current_index


func enemies_total() -> int:
	return ENEMY_ROSTER.size()


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
