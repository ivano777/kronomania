# DungeonManager — tracks a dungeon run: enemy sequence, victory/defeat, point rewards.
# A run is a linear sequence of enemies. Call start_run() to begin; the Hub scene
# reads has_next_enemy() to decide whether to show Continue vs. Start New Run.
extends Node

const ENEMY_ROSTER: Array = [
	preload("res://resources/data/enemy_grunt.tres"),
	preload("res://resources/data/enemies/enemy_soldier.tres"),
	preload("res://resources/data/enemies/enemy_knight.tres"),
]

const POINTS_PER_VICTORY: int = 1

var _current_index: int = 0
var run_active: bool = false
var last_result: String = ""  # "victory" | "defeat" | ""


func start_run() -> void:
	_current_index = 0
	run_active = true
	last_result = ""


func current_enemy() -> CombatantData:
	if run_active and _current_index < ENEMY_ROSTER.size():
		return ENEMY_ROSTER[_current_index]
	return null


func on_victory() -> void:
	PlayerProgression.grant_points(POINTS_PER_VICTORY)
	last_result = "victory"
	_current_index += 1
	if _current_index >= ENEMY_ROSTER.size():
		run_active = false


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
