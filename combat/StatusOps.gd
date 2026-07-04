class_name StatusOps
extends RefCounted

# Status bookkeeping + spell-outcome-effect dispatch — Layer 2 of the CombatManager refactor
# (Phase 3).
#
# Stateless static helpers that mutate CombatantState.active_statuses / pending_guard_debuffs.
# No signals, no await. `tick()` RETURNS log lines instead of emitting — CombatManager's wrapper
# emits them. The hook dispatcher (_process_statuses_hook) and the node-collection orchestrator
# (_apply_spell_outcome_effects) stay in CombatManager: the former awaits the echo, the latter
# reads PlayerProgression.node_levels + round-scoped breach state.


# ── Status CRUD ──────────────────────────────────────────────────────────────

## Adds a status, replacing any existing one with the same status_id (re-apply refreshes, no stack).
static func add(state: CombatantState, status: CombatStatus) -> void:
	remove(state, status.status_id)
	state.active_statuses.append(status)


static func remove(state: CombatantState, status_id: String) -> void:
	state.active_statuses = state.active_statuses.filter(
		func(s): return s.status_id != status_id
	)


static func has(state: CombatantState, status_id: String) -> bool:
	return state.active_statuses.any(
		func(s): return s.status_id == status_id
	)


static func get_status(state: CombatantState, status_id: String) -> CombatStatus:
	for s in state.active_statuses:
		if s.status_id == status_id:
			return s
	return null


## Decrements duration on all non-permanent statuses and removes expired ones.
## Returns log lines for expiries that the caller should emit.
static func tick(state: CombatantState) -> Array[String]:
	var logs: Array[String] = []
	var expired: Array[CombatStatus] = []
	for s in state.active_statuses:
		if s.duration_rounds == -1:
			continue
		s.duration_rounds -= 1
		if s.duration_rounds <= 0:
			expired.append(s)
	for s in expired:
		state.active_statuses.erase(s)
		# Expiry log line comes from the status's effect handler (Phase 2); "" = no line.
		# (Time Lock frozen expiry returns "" — real removal is in _end_of_round, not here.)
		var handler: CombatEffect = EffectRegistry.get_handler(s.status_id)
		if handler != null:
			var line := handler.on_expire(s, state)
			if line != "":
				logs.append(line)
	return logs


# ── Spell outcome effects (Group A4) ─────────────────────────────────────────

static func outcome_matches(effect: SpellOutcomeEffect, spell: SpellData) -> bool:
	if effect.spell_id == "":
		return true
	return effect.spell_id == spell.spell_name


static func outcome_trigger_fires(effect: SpellOutcomeEffect, outcome: Dictionary) -> bool:
	match effect.trigger:
		"on_cast":
			return true
		"on_hit", "on_breach":
			return outcome.get("breach", false) as bool
		_:
			push_warning("Unknown SpellOutcomeEffect.trigger: " + effect.trigger)
			return false


static func outcome_condition_holds(
		effect: SpellOutcomeEffect,
		caster_state: CombatantState,
		_target_state: CombatantState,
		outcome: Dictionary
) -> bool:
	if effect.condition == "":
		return true
	var round_breaches: Dictionary = outcome.get("round_breaches", {})
	match effect.condition:
		"if_stance_breached_this_round":
			return round_breaches.get("stance", false) as bool
		"if_resolve_breached_this_round":
			return round_breaches.get("resolve", false) as bool
		"if_stamina_breached_this_round":
			return round_breaches.get("stamina", false) as bool
		"if_fervor_at_cap":
			return caster_state.fervor_size >= CombatMath.stat_size(caster_state, "ingenuity_size")
		_:
			push_warning("Unknown SpellOutcomeEffect.condition: " + effect.condition)
			return false


static func dispatch_outcome_effect(
		effect: SpellOutcomeEffect,
		caster_state: CombatantState,
		target_state: CombatantState,
		_outcome: Dictionary
) -> void:
	var receiver: CombatantState = caster_state if effect.target == "self" else target_state
	match effect.effect_type:
		"debuff_flat":
			add_pending_guard_debuff(receiver, effect.target_pool, "flat", effect.value)
		"debuff_keep":
			add_pending_guard_debuff(receiver, effect.target_pool, "keep", effect.value)
		"apply_status":
			if effect.status_to_apply != null:
				# Duplicate so each application is an independent instance.
				var st: CombatStatus = effect.status_to_apply.duplicate()
				add(receiver, st)
		"bonus_keep", "bonus_flat":
			# Reserved for outcome-conditional bonuses (e.g. Group D Mind Detonation).
			# These effect_types are NOT for flat roll upgrades — use SpellBonusEffect instead.
			push_warning("bonus_keep/bonus_flat in outcome_effects not dispatched at A4; use SpellBonusEffect instead")
		_:
			push_warning("Unknown SpellOutcomeEffect.effect_type: " + effect.effect_type)


static func add_pending_guard_debuff(state: CombatantState, pool: String, kind: String, value: int) -> void:
	if not state.pending_guard_debuffs.has(pool):
		state.pending_guard_debuffs[pool] = {"flat": 0, "keep": 0}
	var entry := state.pending_guard_debuffs[pool] as Dictionary
	entry[kind] = (entry.get(kind, 0) as int) + value
	state.pending_guard_debuffs[pool] = entry
