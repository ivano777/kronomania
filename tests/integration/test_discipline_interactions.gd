extends GutTest

# Characterization tests for the magic-discipline interactions and interrupt/escalation
# mechanics that Phase 3/4 of the CombatManager refactor will touch.
# CONTRACT: pin CURRENT behavior — must stay green UNEDITED through every extraction phase.
#
# Determinism note: discipline casts roll the defender guard internally when the pool is
# fresh (RNG). Pre-set the guard and mark the pool rolled to make breach/hold deterministic.
# Assertions target status/wound STATE, not roll totals, so the internal roll of an echo
# (which only pressures a pre-armed high guard) does not affect the checks.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")
const _MIND_LASH   = "res://resources/data/spells/mind_lash.tres"

var _enemy   # CombatantState (grunt)
var _player  # CombatantState


func before_each() -> void:
	seed(1)
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	_player = CombatManager._player
	_enemy  = CombatManager._enemies[0]


func _arm_resolve(value: int) -> void:
	_enemy.set_guard_val("resolve", value)
	_enemy.set_pool_rolled("resolve", true)


# ── Hex Mastery / Mind Rend: breach brands, suppresses the wound ─────────────

func test_mind_rend_breach_marks_no_wound() -> void:
	_arm_resolve(5)
	CombatManager._cast_mind_rend(_enemy, 0, {"total": 5})
	assert_true(CombatManager._has_status(_enemy, "hex_marked"), "Resolve breach brands the enemy")
	assert_eq(_enemy.current_wounds, 0, "Mind Rend suppresses the breach wound")


func test_mind_rend_hold_no_mark() -> void:
	_arm_resolve(9)
	CombatManager._cast_mind_rend(_enemy, 0, {"total": 4})
	assert_false(CombatManager._has_status(_enemy, "hex_marked"), "Resolve hold does not brand")
	assert_eq(_enemy.current_wounds, 0, "no wound on a hold")


# ── Chrono-Tinkering / Time Lock: armed → frozen transition ──────────────────

func test_time_lock_breach_arms() -> void:
	_arm_resolve(5)
	CombatManager._cast_time_lock(_enemy, 0, {"total": 5})
	var tl = CombatManager._get_status(_enemy, "time_locked")
	assert_not_null(tl, "Resolve breach applies time_locked")
	assert_eq(tl.stat_overrides.get("phase", ""), "armed", "starts in armed phase")


func test_time_lock_armed_to_frozen_transition() -> void:
	_arm_resolve(5)
	CombatManager._cast_time_lock(_enemy, 0, {"total": 5})
	# Next player attack on this enemy (any pool) transitions armed → frozen.
	_enemy.set_guard_val("stance", 1)
	_enemy.set_pool_rolled("stance", true)
	_enemy.max_wounds = 10
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	var tl = CombatManager._get_status(_enemy, "time_locked")
	assert_not_null(tl, "status persists through the transition")
	assert_eq(tl.stat_overrides.get("phase", ""), "frozen", "transitions to frozen")
	assert_eq(tl.stat_overrides.get("locked_pool", ""), "stance", "locks the attacked pool")
	assert_eq(tl.stat_overrides.get("frozen_value", -1), 0, "breached pool freezes at 0")


# ── Time Lock: frozen pool survives reset across _end_of_round ───────────────

func test_time_lock_frozen_restore_across_end_of_round() -> void:
	var tl = CombatStatus.new()
	tl.status_id = "time_locked"
	tl.duration_rounds = 20
	tl.source_node_id = "chrono_tinkering"
	tl.stat_overrides = {"phase": "frozen", "locked_pool": "stamina", "skip_resets": 1, "frozen_value": 7}
	CombatManager._add_status(_enemy, tl)
	_enemy.set_guard_val("stamina", 7); _enemy.set_pool_rolled("stamina", true)
	_enemy.set_guard_val("stance", 5);  _enemy.set_pool_rolled("stance", true)

	await CombatManager._end_of_round()

	assert_eq(_enemy.get_guard("stamina"), 7, "frozen pool keeps its value across reset")
	assert_eq(_enemy.get_guard("stance"), 0, "non-frozen pools reset to 0")
	assert_false(CombatManager._has_status(_enemy, "time_locked"),
		"skip_resets 1 → 0 removes the freeze after one round")


# ── Echoing Mind: kept-dice decay and self-termination ───────────────────────

func _make_echo(kept: int) -> CombatStatus:
	var s = CombatStatus.new()
	s.status_id = "echoing_spell"
	s.duration_rounds = 20
	s.stat_overrides = {
		"spell_path": _MIND_LASH,
		"target_index": 0,
		"frozen_fervor": 4,
		"current_kept_dice": kept,
		"em_level": 1,
		"cast_tier": 1,
	}
	return s


func test_echo_decays_kept_dice() -> void:
	# Pre-arm a high Stance guard so the echo's internal attack just holds (no defeat noise).
	_enemy.set_guard_val("stance", 99); _enemy.set_pool_rolled("stance", true)
	var echo = _make_echo(2)
	CombatManager._add_status(_player, echo)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_true(CombatManager._has_status(_player, "echoing_spell"), "echo with 2 kept survives one pass")
	assert_eq(echo.stat_overrides.get("current_kept_dice", -1), 1, "kept dice decays 2 → 1")


func test_echo_self_terminates() -> void:
	_enemy.set_guard_val("stance", 99); _enemy.set_pool_rolled("stance", true)
	var echo = _make_echo(1)
	CombatManager._add_status(_player, echo)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_false(CombatManager._has_status(_player, "echoing_spell"),
		"echo with 1 kept removes itself after its last pass")


# ── Fervor escalation → Burnout at cap ───────────────────────────────────────

func test_escalate_beyond_cap_burns_out() -> void:
	_player.fervor_size = 4   # at cap (player ingenuity d4)
	_player.is_burned_out = false
	await CombatManager._escalate_fervor(_player, 1)
	assert_true(_player.is_burned_out, "escalating beyond cap with no Lucidity → Burnout")
	assert_eq(_player.fervor_size, 4, "Fervor clamps at the cap")


# ── Lucidity L2: burnout prevented via interrupt charge ──────────────────────

func _respond_burnout(_charges: int) -> void:
	# Deferred so the escalate coroutine reaches `await _burnout_decision_gate` first.
	await get_tree().process_frame
	CombatManager._burnout_decision_gate.emit(true)


func test_lucidity_prevents_burnout() -> void:
	var h = InterruptHandler.new()
	h.handler_id = "lucidity_prevent_burnout"
	h.trigger = "on_burnout"
	h.charges = 1
	h.priority = 10
	CombatManager._register_interrupt(_player, h)
	CombatManager.player_burnout_imminent.connect(_respond_burnout, CONNECT_ONE_SHOT)

	_player.fervor_size = 4
	_player.is_burned_out = false
	await CombatManager._escalate_fervor(_player, 1)

	assert_false(_player.is_burned_out, "spending the charge averts Burnout")
	assert_eq(_player.fervor_size, 4, "Fervor stays at the edge (cap)")
	assert_eq(h.charges, 0, "the anti-Burnout charge is consumed")


# ── Interrupt lookup: trigger filter + priority sort + charge consumption ─────

func test_find_interrupts_filters_and_sorts() -> void:
	var a = InterruptHandler.new()
	a.handler_id = "meat_for_the_grinder"; a.trigger = "on_massive_wound"; a.charges = 1; a.priority = 20
	var b = InterruptHandler.new()
	b.handler_id = "lucidity_prevent_burnout"; b.trigger = "on_burnout"; b.charges = 1; b.priority = 10
	CombatManager._register_interrupt(_player, a)
	CombatManager._register_interrupt(_player, b)

	var massive = CombatManager._find_interrupts(_player, "on_massive_wound")
	assert_eq(massive.size(), 1, "trigger filter returns only matching handlers")
	assert_eq(massive[0].handler_id, "meat_for_the_grinder", "correct handler by trigger")

	CombatManager._consume_interrupt_charge(a)
	assert_eq(a.charges, 0, "charge consumed")
	assert_eq(CombatManager._find_interrupts(_player, "on_massive_wound").size(), 0,
		"spent handler no longer returned")
