extends GutTest

# Characterization matrix for the four Ingenuity disciplines and — the point of this file —
# their PAIRWISE interactions, which are live via _resolve_attack reentrancy but were previously
# untested. Complements test_discipline_interactions.gd (single-discipline) and test_resolve_attack.gd.
#
# CONTRACT: pins CURRENT behavior. Must stay green UNEDITED through the effect-handler refactor
# (Phases 1–4). If a phase changes an assertion here, that phase changed behavior — stop and review.
#
# Determinism: discipline casts/echoes/explosions roll internally. We pre-arm the defender guard to
# 0 (+ set_pool_rolled) so every internal attack GUARANTEED-breaches, and set max_wounds high so no
# combatant dies mid-test. Assertions target STATUS/PHASE state, wound presence (> 0), or the hex
# amplification LOG line — never exact roll totals — so they are robust to RNG.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")
const _MIND_LASH   = "res://resources/data/spells/mind_lash.tres"

var _enemy   # CombatantState (grunt)
var _player  # CombatantState
var _log_lines: Array = []


func before_each() -> void:
	seed(1)
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	_player = CombatManager._player
	_enemy  = CombatManager._enemies[0]
	CombatManager._current_round_player_breaches = {"stance": false, "resolve": false, "stamina": false}
	_enemy.max_wounds = 10   # no defeat noise; we assert on statuses/amplification, not lethality


func after_each() -> void:
	_stop_capture()


# ── Setup helpers ────────────────────────────────────────────────────────────

func _arm(pool: String, value: int) -> void:
	_enemy.set_guard_val(pool, value)
	_enemy.set_pool_rolled(pool, true)


func _prime_bomb(fervor: int = 4, level: int = 1) -> CombatStatus:
	var b := CombatStatus.new()
	b.status_id = "mind_detonation_primed"
	b.duration_rounds = 3
	b.source_node_id = "mind_detonation"
	b.stat_overrides = {
		"fervor_at_prime": fervor, "md_level": level,
		"cast_tier": 1, "cast_pool_bonus": 0, "cast_keep_bonus": 0, "cast_flat_bonus": 0,
	}
	CombatManager._add_status(_enemy, b)
	return b


func _apply_hex() -> void:
	var h := CombatStatus.new()
	h.status_id = "hex_marked"
	h.duration_rounds = 3
	h.source_node_id = "hex_mastery"
	CombatManager._add_status(_enemy, h)


func _arm_time_lock() -> CombatStatus:
	var tl := CombatStatus.new()
	tl.status_id = "time_locked"
	tl.duration_rounds = 20
	tl.source_node_id = "chrono_tinkering"
	tl.stat_overrides = {"phase": "armed", "locked_pool": "", "skip_resets": 0, "frozen_value": 0}
	CombatManager._add_status(_enemy, tl)
	return tl


func _make_echo(kept: int) -> CombatStatus:
	var s := CombatStatus.new()
	s.status_id = "echoing_spell"
	s.duration_rounds = 20
	s.stat_overrides = {
		"spell_path": _MIND_LASH, "target_index": 0, "frozen_fervor": 4,
		"current_kept_dice": kept, "em_level": 1, "cast_tier": 1,
	}
	CombatManager._add_status(_player, s)
	return s


func _set_stance_breached() -> void:
	CombatManager._current_round_player_breaches["stance"] = true


# ── Log capture (for roll-independent amplification checks) ───────────────────

func _capture_log(text: String) -> void:
	_log_lines.append(text)

func _start_capture() -> void:
	_log_lines = []
	CombatManager.log_message.connect(_capture_log)

func _stop_capture() -> void:
	if CombatManager.log_message.is_connected(_capture_log):
		CombatManager.log_message.disconnect(_capture_log)

func _log_has(substr: String) -> bool:
	for l in _log_lines:
		if substr in l:
			return true
	return false

func _log_count(substr: String) -> int:
	var n := 0
	for l in _log_lines:
		if substr in l:
			n += 1
	return n


# ── Mind Detonation — standalone (previously ZERO coverage) ──────────────────

func test_mind_detonation_detonates_on_stance_breach() -> void:
	_arm("resolve", 0)
	_prime_bomb()
	_set_stance_breached()
	await CombatManager._check_mind_detonation(_enemy, 0)
	assert_false(CombatManager._has_status(_enemy, "mind_detonation_primed"), "bomb consumed on detonation")
	assert_gt(_enemy.current_wounds, 0, "explosion vs Resolve deals at least one wound")


func test_mind_detonation_holds_without_stance_breach() -> void:
	_arm("resolve", 0)
	_prime_bomb()
	# no stance breach flag set this round
	await CombatManager._check_mind_detonation(_enemy, 0)
	assert_true(CombatManager._has_status(_enemy, "mind_detonation_primed"), "bomb stays primed with no Stance breach")
	assert_eq(_enemy.current_wounds, 0, "no detonation → no wound")


func test_mind_detonation_fizzles_on_expiry() -> void:
	var b := _prime_bomb()
	b.duration_rounds = 1
	CombatManager._tick_statuses(_enemy)
	assert_false(CombatManager._has_status(_enemy, "mind_detonation_primed"), "bomb expires via duration tick")
	assert_eq(_enemy.current_wounds, 0, "a fizzle deals no wound")


func test_mind_detonation_l2_still_detonates() -> void:
	_arm("resolve", 0)
	_prime_bomb(4, 2)   # md_level 2 (+1 explosion keep; observable = detonation still fires)
	_set_stance_breached()
	await CombatManager._check_mind_detonation(_enemy, 0)
	assert_false(CombatManager._has_status(_enemy, "mind_detonation_primed"), "L2 bomb consumed on detonation")
	assert_gt(_enemy.current_wounds, 0, "L2 explosion deals a wound")


# ── Pair: Hex + Mind Detonation — explosion breach is hex-amplified ──────────

func test_hex_amplifies_mind_detonation_explosion() -> void:
	_arm("resolve", 0)
	_apply_hex()
	_prime_bomb()
	_set_stance_breached()
	_start_capture()
	await CombatManager._check_mind_detonation(_enemy, 0)
	_stop_capture()
	assert_true(_log_has("hex flares"), "the mind-bomb explosion's Resolve breach is amplified by the hex")


# ── Pair: Hex + Time Lock — one attack amplifies AND arms the freeze ─────────

func test_hex_and_time_lock_both_fire_on_one_attack() -> void:
	_apply_hex()
	var tl := _arm_time_lock()
	_arm("stance", 0)
	_start_capture()
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")
	_stop_capture()
	assert_true(_log_has("hex flares"), "hex amplifies the breach")
	assert_eq(tl.stat_overrides.get("phase", ""), "frozen", "the same attack transitions armed→frozen")
	assert_eq(tl.stat_overrides.get("locked_pool", ""), "stance", "freeze locks the attacked pool")


# ── Pair: Hex + Echo — echo breach on a hexed enemy is amplified ─────────────

func test_hex_amplifies_echo() -> void:
	_apply_hex()
	_arm("stance", 0)
	var echo := _make_echo(2)
	_start_capture()
	await CombatManager._resolve_spell_echo(echo, _player)
	_stop_capture()
	assert_true(_log_has("hex flares"), "the echo's breach on a hexed enemy is amplified")


# ── Pair: Mind Detonation + Time Lock — explosion arms the freeze ────────────

func test_mind_detonation_explosion_transitions_time_lock() -> void:
	_arm("resolve", 0)
	var tl := _arm_time_lock()
	_prime_bomb()
	_set_stance_breached()
	await CombatManager._check_mind_detonation(_enemy, 0)
	assert_eq(tl.stat_overrides.get("phase", ""), "frozen", "the explosion is a player attack → arms the freeze")
	assert_eq(tl.stat_overrides.get("locked_pool", ""), "resolve", "freezes the Resolve pool the explosion hit")


# ── Pair: Mind Detonation + Echo — echo Stance breach detonates a primed bomb ─

func test_echo_detonates_primed_bomb() -> void:
	_arm("stance", 0)
	_arm("resolve", 0)
	_prime_bomb()
	var echo := _make_echo(2)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_false(CombatManager._has_status(_enemy, "mind_detonation_primed"),
		"the echo's Stance breach sets the round flag and detonates the primed bomb")


# ── Pair: Time Lock + Echo — echo attack transitions armed→frozen ────────────

func test_echo_transitions_armed_time_lock() -> void:
	var tl := _arm_time_lock()
	_arm("stance", 0)
	var echo := _make_echo(2)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_eq(tl.stat_overrides.get("phase", ""), "frozen", "the echo counts as the next player attack → arms the freeze")
	assert_eq(tl.stat_overrides.get("locked_pool", ""), "stance", "freezes the Stance pool the echo hit")


# ── Pair: Time Lock + Echo (frozen phase) — an echo on an already-FROZEN pool is stable ──
# Reverse/other-phase variant of test_echo_transitions_armed_time_lock: that pins armed→frozen;
# this pins that a FROZEN lock is neither re-armed nor decremented by a subsequent echo attack
# (skip_resets only decays at end_of_round via on_guard_reset, not on the attack).
func test_echo_on_frozen_pool_does_not_re_arm() -> void:
	var tl := _arm_time_lock()
	tl.stat_overrides = {"phase": "frozen", "locked_pool": "stance", "skip_resets": 1, "frozen_value": 0}
	_arm("stance", 0)
	var echo := _make_echo(2)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_eq(tl.stat_overrides.get("phase", ""), "frozen", "an echo does not knock a frozen lock back to armed")
	assert_eq(tl.stat_overrides.get("skip_resets", -1), 1, "the attack does not decrement skip_resets — only end_of_round does")


# ── Pair: Mind Detonation + Echo (reverse) — echo that does NOT breach Stance leaves the bomb primed ──
# Reverse of test_echo_detonates_primed_bomb: a held echo must NOT set the round Stance-breach flag,
# so the primed bomb survives.
func test_echo_without_stance_breach_leaves_bomb_primed() -> void:
	_arm("stance", 999)   # echo (vs Stance) cannot breach → round flag stays false
	_arm("resolve", 0)
	_prime_bomb()
	var echo := _make_echo(2)
	await CombatManager._resolve_spell_echo(echo, _player)
	assert_true(CombatManager._has_status(_enemy, "mind_detonation_primed"),
		"no Stance breach → the primed bomb is not detonated")
	assert_eq(_enemy.current_wounds, 0, "the held echo and un-triggered bomb deal no wound")


# ── Pair: Hex + Mind Detonation (double-dip) — BOTH the Stance breach and the explosion amplify ──
# Depth variant of test_hex_amplifies_mind_detonation_explosion (which pins only the explosion):
# the SAME mark must amplify the real Stance breach AND the mind-bomb explosion — the designed combo.
func test_hex_amplifies_both_stance_breach_and_explosion() -> void:
	_apply_hex()
	_prime_bomb()
	_arm("stance", 0)
	_arm("resolve", 0)
	_start_capture()
	await CombatManager._resolve_attack(true, 0, {"total": 5}, "stance")   # hexed Stance breach → flare #1
	_set_stance_breached()
	await CombatManager._check_mind_detonation(_enemy, 0)                  # explosion vs Resolve → flare #2
	_stop_capture()
	assert_eq(_log_count("hex flares"), 2, "one mark amplifies both the Stance breach and the mind-bomb explosion")
