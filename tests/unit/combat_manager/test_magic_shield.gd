extends GutTest

# Magic Shield (ing_resolve L2+) — guard-shaped interrupt awaited inside _resolve_attack.
# Harness mirrors test_resolve_attack.gd: pre-arm the player's guard so the defense roll
# is skipped and the only await left is the shield decision gate. The prompt responder
# answers via call_deferred so the coroutine reaches `await _shield_decision_gate` first
# (same pattern as the Lucidity gate in test_discipline_interactions.gd).

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")
const _ING_RESOLVE = preload("res://resources/data/nodes/ingenuity/ing_resolve.tres")

var _prompt_seen := false
var _seen_incoming := 0
var _seen_guard := 0
var _seen_dice := 0


func before_each() -> void:
	seed(1)
	_prompt_seen = false
	_seen_incoming = 0
	_seen_guard = 0
	_seen_dice = 0
	get_node("/root/PlayerProgression").reset()


func _start_with_shield(level: int) -> void:
	var pp := get_node("/root/PlayerProgression")
	pp.node_levels[_ING_RESOLVE] = level
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])


func _arm_player_guard(pool: String, value: int) -> void:
	CombatManager._player.set_guard_val(pool, value)
	CombatManager._player.set_pool_rolled(pool, true)


func _respond(use_charge: bool, charges: int, incoming: int, guard: int, dice: int, _die: int) -> void:
	_prompt_seen = true
	_seen_incoming = incoming
	_seen_guard = guard
	_seen_dice = dice
	CombatManager.player_chose_magic_shield.call_deferred(use_charge)


func _shield_charges_left() -> int:
	var handlers = CombatManager._find_interrupts(CombatManager._player, "on_guard_break")
	return 0 if handlers.is_empty() else handlers[0].charges as int


func test_shield_saves_a_breaking_guard() -> void:
	_start_with_shield(2)
	_arm_player_guard("stance", 5)
	# Responder accepts; incoming 6 vs guard 5 — 2 shield dice add at least 2 → always holds.
	CombatManager.player_shield_opportunity.connect(
		func(c: int, i: int, g: int, d: int, s: int) -> void: _respond(true, c, i, g, d, s),
		CONNECT_ONE_SHOT)
	await CombatManager._resolve_attack(false, 0, {"total": 6}, "stance")
	assert_true(_prompt_seen, "shield prompt fires when the guard would break")
	assert_eq(_seen_incoming, 6, "prompt reports the incoming total")
	assert_eq(_seen_guard, 5, "prompt reports the current guard")
	assert_eq(_seen_dice, 2, "dice count = ing_resolve level (L2 → 2 dice)")
	assert_eq(CombatManager._player.current_wounds, 0, "reinforced guard holds — no wound")
	# Held guard absorbs the pressure: remainder = (5 + shield roll) - 6 ≥ 1.
	assert_gt(CombatManager._player.get_guard("stance"), 0, "guard survives with the remainder")
	assert_eq(_shield_charges_left(), 0, "the single L2 charge is consumed")


func test_shield_declined_breach_proceeds() -> void:
	_start_with_shield(2)
	_arm_player_guard("stance", 5)
	CombatManager.player_shield_opportunity.connect(
		func(c: int, i: int, g: int, d: int, s: int) -> void: _respond(false, c, i, g, d, s),
		CONNECT_ONE_SHOT)
	await CombatManager._resolve_attack(false, 0, {"total": 6}, "stance")
	assert_true(_prompt_seen, "prompt still offered")
	assert_eq(CombatManager._player.current_wounds, 1, "declined shield → normal breach")
	assert_eq(_shield_charges_left(), 1, "declining spends no charge")


func test_no_prompt_when_guard_holds() -> void:
	_start_with_shield(2)
	_arm_player_guard("stance", 9)
	CombatManager.player_shield_opportunity.connect(
		func(c: int, i: int, g: int, d: int, s: int) -> void: _respond(true, c, i, g, d, s),
		CONNECT_ONE_SHOT)
	await CombatManager._resolve_attack(false, 0, {"total": 6}, "stance")
	assert_false(_prompt_seen, "no prompt while the guard is holding")
	assert_eq(CombatManager._player.current_wounds, 0, "guard absorbs the pressure")
	assert_eq(_shield_charges_left(), 1, "charge untouched")


func test_no_shield_handler_means_no_prompt_no_deadlock() -> void:
	# Default reset grants ing_resolve L1 only — no magic_shield rider, no handler.
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	_arm_player_guard("stance", 5)
	CombatManager.player_shield_opportunity.connect(
		func(c: int, i: int, g: int, d: int, s: int) -> void: _respond(true, c, i, g, d, s),
		CONNECT_ONE_SHOT)
	await CombatManager._resolve_attack(false, 0, {"total": 6}, "stance")
	assert_false(_prompt_seen, "no handler → no prompt")
	assert_eq(CombatManager._player.current_wounds, 1, "breach resolves normally without a shield")


func test_shield_can_fail_against_overkill() -> void:
	_start_with_shield(2)
	_arm_player_guard("stance", 1)
	CombatManager.player_shield_opportunity.connect(
		func(c: int, i: int, g: int, d: int, s: int) -> void: _respond(true, c, i, g, d, s),
		CONNECT_ONE_SHOT)
	# 2 shield dice can never lift guard 1 above 60 — charge spent, breach anyway.
	await CombatManager._resolve_attack(false, 0, {"total": 60}, "stance")
	assert_true(_prompt_seen, "prompt offered even on hopeless breaks — player's call")
	assert_gt(CombatManager._player.current_wounds, 0, "shield failed — breach lands")
	assert_eq(_shield_charges_left(), 0, "failed shield still consumes the charge")
