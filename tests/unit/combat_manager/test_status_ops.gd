extends GutTest

# Direct unit tests for StatusOps + InterruptOps (Phase 3 of the CombatManager refactor).
# Built against a hand-made CombatantState — no CombatManager, no signals. The outcome-effect
# predicates/dispatch lost their CombatManager wrappers in Phase 3, so this is their direct net.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")

var _s: CombatantState


func before_each() -> void:
	_s = CombatantState.new()
	_s.init(_PLAYER_DATA)


func _status(id: String, dur: int) -> CombatStatus:
	var st = CombatStatus.new()
	st.status_id = id
	st.duration_rounds = dur
	return st


# ── Status CRUD ──────────────────────────────────────────────────────────────

func test_add_has_get_remove() -> void:
	StatusOps.add(_s, _status("foo", 2))
	assert_true(StatusOps.has(_s, "foo"))
	assert_eq(StatusOps.get_status(_s, "foo").duration_rounds, 2)
	StatusOps.remove(_s, "foo")
	assert_false(StatusOps.has(_s, "foo"))
	assert_null(StatusOps.get_status(_s, "missing"))


func test_add_replaces_duplicate() -> void:
	StatusOps.add(_s, _status("foo", 3))
	StatusOps.add(_s, _status("foo", 99))
	assert_eq(_s.active_statuses.size(), 1, "re-apply replaces, no stack")
	assert_eq(StatusOps.get_status(_s, "foo").duration_rounds, 99)


func test_tick_decrements_and_expires() -> void:
	StatusOps.add(_s, _status("temp", 2))
	StatusOps.add(_s, _status("perm", -1))
	assert_eq(StatusOps.tick(_s).size(), 0, "no expiry after first tick")
	assert_true(StatusOps.has(_s, "temp"))
	StatusOps.tick(_s)
	assert_false(StatusOps.has(_s, "temp"), "expires after 2 ticks")
	assert_true(StatusOps.has(_s, "perm"), "permanent (-1) never expires")


func test_tick_returns_expiry_log_for_known_status() -> void:
	StatusOps.add(_s, _status("hex_marked", 1))
	var logs = StatusOps.tick(_s)
	assert_eq(logs.size(), 1, "known status expiry produces a log line")
	assert_true(logs[0].contains("hex"), "log mentions the hex")


# ── Pending guard debuffs ────────────────────────────────────────────────────

func test_pending_guard_debuff_accumulates() -> void:
	StatusOps.add_pending_guard_debuff(_s, "stance", "flat", -2)
	StatusOps.add_pending_guard_debuff(_s, "stance", "keep", -1)
	StatusOps.add_pending_guard_debuff(_s, "stance", "flat", -1)
	var entry = _s.pending_guard_debuffs["stance"] as Dictionary
	assert_eq(entry["flat"], -3, "flat debuffs sum")
	assert_eq(entry["keep"], -1, "keep debuff tracked separately")


# ── Outcome-effect predicates + dispatch ─────────────────────────────────────

func test_outcome_matches() -> void:
	var spell = SpellData.new()
	spell.spell_name = "Arcane Mark"
	var any = SpellOutcomeEffect.new()          # empty spell_id matches any
	var named = SpellOutcomeEffect.new()
	named.spell_id = "Arcane Mark"
	var other = SpellOutcomeEffect.new()
	other.spell_id = "Arcane Missile"
	assert_true(StatusOps.outcome_matches(any, spell), "empty spell_id matches any spell")
	assert_true(StatusOps.outcome_matches(named, spell), "matching name matches")
	assert_false(StatusOps.outcome_matches(other, spell), "non-matching name does not")


func test_outcome_trigger_fires() -> void:
	var on_cast = SpellOutcomeEffect.new(); on_cast.trigger = "on_cast"
	var on_breach = SpellOutcomeEffect.new(); on_breach.trigger = "on_breach"
	assert_true(StatusOps.outcome_trigger_fires(on_cast, {"breach": false}), "on_cast always fires")
	assert_true(StatusOps.outcome_trigger_fires(on_breach, {"breach": true}), "on_breach fires on breach")
	assert_false(StatusOps.outcome_trigger_fires(on_breach, {"breach": false}), "on_breach skips on hold")


func test_outcome_condition_round_breach() -> void:
	var eff = SpellOutcomeEffect.new()
	eff.condition = "if_stance_breached_this_round"
	var yes = {"round_breaches": {"stance": true}}
	var no = {"round_breaches": {"stance": false}}
	assert_true(StatusOps.outcome_condition_holds(eff, _s, _s, yes))
	assert_false(StatusOps.outcome_condition_holds(eff, _s, _s, no))


func test_dispatch_apply_status() -> void:
	var eff = SpellOutcomeEffect.new()
	eff.effect_type = "apply_status"
	eff.target = "enemy"
	eff.status_to_apply = _status("branded", 3)
	var target = CombatantState.new()
	target.init(_PLAYER_DATA)
	StatusOps.dispatch_outcome_effect(eff, _s, target, {})
	assert_true(StatusOps.has(target, "branded"), "apply_status adds to the target")
	assert_false(StatusOps.has(_s, "branded"), "caster unaffected when target=enemy")


func test_dispatch_debuff_flat_queues_pending() -> void:
	var eff = SpellOutcomeEffect.new()
	eff.effect_type = "debuff_flat"
	eff.target = "enemy"
	eff.target_pool = "stance"
	eff.value = -2
	var target = CombatantState.new()
	target.init(_PLAYER_DATA)
	StatusOps.dispatch_outcome_effect(eff, _s, target, {})
	assert_eq((target.pending_guard_debuffs["stance"] as Dictionary)["flat"], -2)


# ── InterruptOps ─────────────────────────────────────────────────────────────

func _handler(id: String, trig: String, charges: int, prio: int) -> InterruptHandler:
	var h = InterruptHandler.new()
	h.handler_id = id; h.trigger = trig; h.charges = charges; h.priority = prio
	return h


func test_interrupt_find_filters_sorts_and_consumes() -> void:
	InterruptOps.register(_s, _handler("late", "on_massive_wound", 1, 20))
	InterruptOps.register(_s, _handler("early", "on_massive_wound", 1, 10))
	InterruptOps.register(_s, _handler("other", "on_burnout", 1, 5))
	var found = InterruptOps.find(_s, "on_massive_wound")
	assert_eq(found.size(), 2, "trigger filter")
	assert_eq(found[0].handler_id, "early", "priority-ascending sort")
	InterruptOps.consume_charge(found[0])
	assert_eq(found[0].charges, 0, "charge consumed")
	assert_eq(InterruptOps.find(_s, "on_massive_wound").size(), 1, "spent handler dropped")
