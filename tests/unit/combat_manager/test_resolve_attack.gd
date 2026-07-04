extends GutTest

# Characterization tests for _resolve_attack — the core attack-resolution spine.
# CONTRACT: these pin CURRENT behavior for the CombatManager refactor. They must stay
# green UNEDITED through every extraction phase. A red one means behavior changed.
#
# Determinism: pre-set the defender's guard and mark the pool rolled so _resolve_attack
# reuses the stored guard instead of rolling (RollEngine is stochastic). On the
# player-attacker / enemy-defender path with the pool pre-rolled, _resolve_attack hits no
# await, so results are pure functions of (attack_total, guard, defensive_size).

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")

var _enemy  # CombatantState (grunt): all d4, stance defensive_size = 4, max_wounds = 2, VT 10


func before_each() -> void:
	seed(1)
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	_enemy = CombatManager._enemies[0]


func _arm_guard(pool: String, value: int) -> void:
	# Pre-roll the pool so _resolve_attack reuses this guard (no RNG).
	_enemy.set_guard_val(pool, value)
	_enemy.set_pool_rolled(pool, true)


func _make_hex() -> CombatStatus:
	var s = CombatStatus.new()
	s.status_id = "hex_marked"
	s.duration_rounds = 3
	return s


# ── Breach exactly at guard (attack_total == guard is a breach) ───────────────

func test_breach_exact_deals_one_wound() -> void:
	_arm_guard("stance", 5)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_eq(_enemy.current_wounds, 1, "attack_total == guard breaches for 1 wound")
	assert_false(_enemy.is_defeated, "one wound on a 2-wound grunt is not defeat")


# ── Guard holds when attack_total < guard ────────────────────────────────────

func test_guard_holds_no_wound() -> void:
	_arm_guard("stance", 8)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_eq(_enemy.current_wounds, 0, "attack below guard deals no wound")
	assert_eq(_enemy.get_guard("stance"), 3, "guard absorbs and retains remaining 8-5=3")


# ── Massive wound: (attack - guard) > defensive_size → 2 wounds ──────────────

func test_massive_deals_two_wounds() -> void:
	_enemy.max_wounds = 10  # isolate the wound count from defeat
	_arm_guard("stance", 1)
	# overflow 10-1 = 9 > 4 (grunt negation d4) → Massive
	await CombatManager._resolve_attack(true, 0, {"total": 10}, "stance")
	assert_eq(_enemy.current_wounds, 2, "Massive wound deals 2")


func test_non_massive_boundary() -> void:
	_enemy.max_wounds = 10
	_arm_guard("stance", 1)
	# overflow 5-1 = 4, NOT > 4 → not Massive → 1 wound
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_eq(_enemy.current_wounds, 1, "overflow == defensive_size is not Massive")


# ── Defeat when wounds reach max ─────────────────────────────────────────────

func test_breach_to_defeat() -> void:
	_enemy.current_wounds = 1  # one short of max (2)
	_arm_guard("stance", 5)
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	assert_eq(_enemy.current_wounds, 2, "reaches max wounds")
	assert_true(_enemy.is_defeated, "wounds >= max_wounds → defeated")


# ── VT (Fast/Slow) predicate used by the round loop ──────────────────────────

func test_vt_fast_slow_boundary() -> void:
	# Player total >= VT → Fast; below → Slow. Grunt VT = 10.
	assert_true(RollEngine.is_fast(10, 10), "total == VT is Fast")
	assert_true(RollEngine.is_fast(11, 10), "total > VT is Fast")
	assert_false(RollEngine.is_fast(9, 10), "total < VT is Slow")


# ── Hex Mastery amplification: +1 wound on a hexed enemy breach ──────────────

func test_hex_amplifies_normal_breach() -> void:
	_enemy.max_wounds = 10
	CombatManager._add_status(_enemy, _make_hex())
	_arm_guard("stance", 1)
	# overflow 3-1 = 2, not Massive → base 1 + hex 1 = 2
	await CombatManager._resolve_attack(true, 0, {"total": 3}, "stance")
	assert_eq(_enemy.current_wounds, 2, "hex adds +1 to a normal breach")


func test_hex_amplifies_massive_breach() -> void:
	_enemy.max_wounds = 10
	CombatManager._add_status(_enemy, _make_hex())
	_arm_guard("stance", 1)
	# Massive (9 > 4) → 2, + hex 1 = 3
	await CombatManager._resolve_attack(true, 0, {"total": 10}, "stance")
	assert_eq(_enemy.current_wounds, 3, "hex adds +1 on top of a Massive wound")
