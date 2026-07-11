extends GutTest

# Integration tests for the attack_resolved presentation signal: emitted exactly
# once per _resolve_attack pass (breach AND blocked), payload consistent with the
# wounds actually applied. Determinism: guards pre-armed so no RNG on the
# player-attacker path (same technique as test_resolve_attack.gd).

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")

var _enemy  # CombatantState (grunt): stance defensive_size = 4, max_wounds = 2


func before_each() -> void:
	seed(1)
	get_node("/root/PlayerProgression").reset()
	CombatManager.attack_pacing_s = 0.0  # presentation pacing must never slow tests
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	_enemy = CombatManager._enemies[0]
	watch_signals(CombatManager)


func _arm_guard(pool: String, value: int) -> void:
	_enemy.set_guard_val(pool, value)
	_enemy.set_pool_rolled(pool, true)


func test_pacing_defaults_to_zero_semantics() -> void:
	# 0.0 = no pacing await — the guarded branch must be skippable.
	assert_eq(CombatManager.attack_pacing_s, 0.0)


func test_breach_emits_attack_resolved_with_wound() -> void:
	_arm_guard("stance", 5)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_signal_emit_count(CombatManager, "attack_resolved", 1)
	assert_signal_emitted_with_parameters(CombatManager, "attack_resolved",
		[true, 0, "stance", true, false, 1, false])


func test_blocked_emits_attack_resolved_without_wound() -> void:
	_arm_guard("stance", 8)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_signal_emit_count(CombatManager, "attack_resolved", 1)
	assert_signal_emitted_with_parameters(CombatManager, "attack_resolved",
		[true, 0, "stance", false, false, 0, false])
	assert_eq(_enemy.current_wounds, 0, "blocked attack deals no wound")


func test_massive_payload() -> void:
	_enemy.max_wounds = 10  # isolate wound count from defeat
	_arm_guard("stance", 1)
	# overflow 10-1 = 9 > 4 (grunt stance d4) → Massive, 2 wounds
	await CombatManager._resolve_attack(true, 0, {"total": 10}, "stance")
	assert_signal_emitted_with_parameters(CombatManager, "attack_resolved",
		[true, 0, "stance", true, true, 2, false])


func test_defeat_payload() -> void:
	_enemy.current_wounds = 1  # one short of max (2)
	_arm_guard("stance", 5)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_signal_emitted_with_parameters(CombatManager, "attack_resolved",
		[true, 0, "stance", true, false, 1, true])


func test_wounds_dealt_matches_wounds_changed_delta() -> void:
	_enemy.max_wounds = 10
	_arm_guard("stance", 1)
	var before: int = _enemy.current_wounds
	await CombatManager._resolve_attack(true, 0, {"total": 10}, "stance")
	var params = get_signal_parameters(CombatManager, "attack_resolved")
	assert_eq(params[5] as int, _enemy.current_wounds - before,
		"wounds_dealt equals the actual wound delta")
