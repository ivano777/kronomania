# DungeonManager — tracks a dungeon run: encounter sequence, victory/defeat, point rewards.
# ENCOUNTERS[i]       = one encounter (campfire allowed between encounters)
# ENCOUNTERS[i][j]    = one wave     (chained directly from prior wave, '->' notation)
# ENCOUNTERS[i][j][k] = one enemy    (all present simultaneously, '+' notation)
extends Node

const POINTS_PER_VICTORY: int = 1

const _GRUNT   := preload("res://resources/data/enemy_grunt.tres")
const _SOLDIER := preload("res://resources/data/enemies/enemy_soldier.tres")
const _KNIGHT  := preload("res://resources/data/enemies/enemy_knight.tres")
const _DUMMY   := preload("res://resources/data/enemies/training_dummy.tres")

# Starter Dungeon — 8 encounters with mixed chain/parallel structure.
const ENCOUNTERS: Array = [
	[ [_GRUNT] ],                                           # 1: Grunt
	[ [_GRUNT], [_GRUNT] ],                                 # 2: Grunt -> Grunt
	[ [_GRUNT, _GRUNT] ],                                   # 3: Grunt + Grunt
	[ [_SOLDIER] ],                                         # 4: Soldier
	[ [_GRUNT], [_GRUNT, _SOLDIER] ],                       # 5: Grunt -> Grunt + Soldier
	[ [_GRUNT, _GRUNT, _GRUNT] ],                           # 6: Grunt + Grunt + Grunt
	[ [_GRUNT, _SOLDIER], [_SOLDIER, _SOLDIER] ],           # 7: Grunt+Soldier -> Soldier+Soldier
	[ [_KNIGHT] ],                                          # 8: Knight
]

var _encounter_index: int = 0
var _wave_index: int = 0
var run_active: bool = false
var last_result: String = ""
var _last_chain: bool = false
var short_rest_used: bool = false
var long_rest_used: bool = false

var is_ambush_active: bool = false
var ambush_disadvantage: int = 0
var _ambush_enemies: Array = []

## Training room: BattleScene vs the Training Dummy, entered from the
## Campfire, fully outside the run flow. While true, current_enemies() serves
## the dummy and BattleScene must NOT call on_victory/on_defeat (no points, no
## save deletion, no run advance). Player wounds/Fervor/Burnout are snapshotted
## at entry and restored on exit — training is a free sandbox for the run.
var training_mode: bool = false
## Dummy swings back only when enabled from the battle toggle (off = its whole
## turn is skipped: no roll, no windup, no pacing pause).
var training_dummy_attacks: bool = false
var _pre_training_wounds: int = 0
var _pre_training_fervor: int = 4
var _pre_training_burnout: bool = false


func start_training() -> void:
	training_mode = true
	training_dummy_attacks = false
	_pre_training_wounds = PlayerProgression.saved_wounds
	_pre_training_fervor = PlayerProgression.saved_fervor_size
	_pre_training_burnout = PlayerProgression.saved_is_burned_out


func end_training() -> void:
	if not training_mode:
		return  # idempotent — a stale snapshot must never overwrite live state
	training_mode = false
	training_dummy_attacks = false
	PlayerProgression.saved_wounds = _pre_training_wounds
	PlayerProgression.saved_fervor_size = _pre_training_fervor
	PlayerProgression.saved_is_burned_out = _pre_training_burnout


func start_run() -> void:
	_encounter_index = 0
	_wave_index = 0
	run_active = true
	last_result = ""
	_last_chain = false
	short_rest_used = false
	long_rest_used = false
	is_ambush_active = false
	_ambush_enemies = []
	ambush_disadvantage = 0


func current_enemies() -> Array:
	if training_mode:
		return [_DUMMY]
	if is_ambush_active:
		return _ambush_enemies
	if run_active and _encounter_index < ENCOUNTERS.size():
		return ENCOUNTERS[_encounter_index][_wave_index]
	return []


func on_victory() -> void:
	PlayerProgression.grant_points(POINTS_PER_VICTORY)
	if is_ambush_active:
		is_ambush_active = false
		_ambush_enemies = []
		ambush_disadvantage = 0
		return
	last_result = "victory"
	_wave_index += 1
	var encounter: Array = ENCOUNTERS[_encounter_index]
	if _wave_index < encounter.size():
		# More waves remain in this encounter — chain directly (no campfire stop).
		_last_chain = true
	else:
		# Encounter complete — advance to next and allow a campfire visit.
		_last_chain = false
		_encounter_index += 1
		_wave_index = 0
		short_rest_used = false
		if _encounter_index >= ENCOUNTERS.size():
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
	return run_active and _encounter_index < ENCOUNTERS.size()


func is_run_complete() -> bool:
	return not run_active and last_result == "victory"


func enemies_cleared() -> int:
	return _encounter_index


func enemies_total() -> int:
	return ENCOUNTERS.size()


func attempt_short_rest() -> void:
	if short_rest_used:
		return
	PlayerProgression.apply_short_rest()
	CombatManager.reset_item_charges("short")
	short_rest_used = true


func attempt_long_rest() -> Dictionary:
	if long_rest_used:
		return {"ambushed": false}
	long_rest_used = true
	PlayerProgression.apply_long_rest()
	CombatManager.reset_item_charges("long")
	CombatManager.reset_item_charges("combat")
	var ambushed := randi() % 100 < (50 - PlayerProgression.luck)
	if ambushed:
		_ambush_enemies = [_pick_ambush_enemy()]
		is_ambush_active = true
		var has_disadv := randi() % 100 < (50 - PlayerProgression.luck)
		ambush_disadvantage = -2 if has_disadv else 0
	# TODO: deduct money when money system is implemented
	return {"ambushed": ambushed}


func surrender() -> Dictionary:
	_encounter_index = 0
	_wave_index = 0
	short_rest_used = false
	long_rest_used = false
	is_ambush_active = false
	_ambush_enemies = []
	ambush_disadvantage = 0
	PlayerProgression.saved_wounds = 0
	var lost_points := 0
	var lost_weapon := false
	if randi() % 100 < (50 - PlayerProgression.luck):
		lost_points = PlayerProgression.available_points / 2
		PlayerProgression.available_points -= lost_points
	if PlayerProgression.main_hand != null \
			and randi() % 100 < (30 - PlayerProgression.luck):
		lost_weapon = true
		PlayerProgression.main_hand = null
		PlayerProgression.off_hand = null
	return {"lost_points": lost_points, "lost_weapon": lost_weapon}


func serialize() -> Dictionary:
	return {
		"run_active":          run_active,
		"encounter_index":     _encounter_index,
		"wave_index":          _wave_index,
		"last_result":         last_result,
		"short_rest_used":     short_rest_used,
		"long_rest_used":      long_rest_used,
		"is_ambush_active":    is_ambush_active,
		"ambush_disadvantage": ambush_disadvantage,
	}


func deserialize(data: Dictionary) -> void:
	run_active          = bool(data.get("run_active", false))
	# Support old save files that used "enemy_index" key.
	_encounter_index    = int(data.get("encounter_index", data.get("enemy_index", 0)))
	_wave_index         = int(data.get("wave_index", 0))
	last_result         = str(data.get("last_result", ""))
	short_rest_used     = bool(data.get("short_rest_used", false))
	long_rest_used      = bool(data.get("long_rest_used", false))
	is_ambush_active    = bool(data.get("is_ambush_active", false))
	ambush_disadvantage = int(data.get("ambush_disadvantage", 0))


func _pick_ambush_enemy() -> CombatantData:
	if _encounter_index <= 1:
		return _GRUNT
	elif _encounter_index <= 5:
		return [_GRUNT, _SOLDIER][randi() % 2]
	else:
		return [_SOLDIER, _KNIGHT][randi() % 2]
