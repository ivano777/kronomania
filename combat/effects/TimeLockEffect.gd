class_name TimeLockEffect
extends CombatEffect

# Chrono-Tinkering / Time Lock. Two-phase on an enemy: ARMED (waiting for the next player attack,
# any pool — echoes and MD explosions count) → FROZEN (locks the attacked guard pool for skip_resets
# rounds at frozen_value). The transition fires from on_player_attack_resolved; the frozen restore
# fires from on_guard_reset each end_of_round. Applied ARMED by Disciplines.cast_time_lock.

func on_player_attack_resolved(status: CombatStatus, ctx: AttackContext) -> void:
	var tlp := TimeLockPayload.from_status(status)
	var post_val: int = 0 if ctx.did_breach else ctx.defender_state.get_guard(ctx.target_pool)
	if tlp.phase == TimeLockPayload.PHASE_ARMED:
		var chrono_level: int = PlayerProgression.get_node_level_by_id("chrono_tinkering")
		tlp.phase = TimeLockPayload.PHASE_FROZEN
		tlp.locked_pool = ctx.target_pool
		tlp.skip_resets = chrono_level
		tlp.frozen_value = post_val
		tlp.to_status(status)
		CombatManager.log_message.emit("[color=cyan]Time frozen! %s's %s guard is locked at %d — it will not renew for %d round(s).[/color]" % [
			ctx.defender_state.data.combatant_name, ctx.target_pool, post_val, chrono_level
		])
	elif tlp.phase == TimeLockPayload.PHASE_FROZEN and tlp.locked_pool == ctx.target_pool:
		tlp.frozen_value = post_val
		tlp.to_status(status)


func on_guard_reset(status: CombatStatus, state: CombatantState, enemy_index: int) -> void:
	var tlp := TimeLockPayload.from_status(status)
	if tlp.phase != TimeLockPayload.PHASE_FROZEN or tlp.skip_resets <= 0:
		return
	# Guard already reset by the caller; restore the frozen pool and mark it rolled so it won't re-roll.
	# frozen_value lives in the payload (not the guard), so reading it after reset is correct.
	state.set_guard_val(tlp.locked_pool, tlp.frozen_value)
	state.set_pool_rolled(tlp.locked_pool, true)
	CombatManager.guard_changed.emit(false, enemy_index, tlp.locked_pool, tlp.frozen_value)
	tlp.skip_resets -= 1
	tlp.to_status(status)
	CombatManager.log_message.emit("[color=cyan]%s's %s remains frozen at %d (%d round(s) left).[/color]" % [
		state.data.combatant_name, tlp.locked_pool, tlp.frozen_value, tlp.skip_resets
	])
	if tlp.skip_resets <= 0:
		StatusOps.remove(state, "time_locked")
		CombatManager.log_message.emit("[color=cyan]The time-freeze on %s's %s expires.[/color]" % [
			state.data.combatant_name, tlp.locked_pool
		])


func on_expire(status: CombatStatus, _state: CombatantState) -> String:
	if TimeLockPayload.from_status(status).phase == TimeLockPayload.PHASE_ARMED:
		return "[color=cyan]The armed Time Lock dissipates — the moment slips away, unfrozen.[/color]"
	return ""
