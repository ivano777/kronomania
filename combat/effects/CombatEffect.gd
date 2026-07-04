class_name CombatEffect
extends RefCounted

# Base handler for one discipline status_id (Phase 2 of the effect-handler refactor). All hooks are
# optional (default no-op / 0 / ""). Stateless — a hook reads/writes the CombatStatus payload (typed
# views) + AttackContext, and reaches the combat singletons via the CombatManager / PlayerProgression
# globals, exactly as StatusOps and Disciplines do. The spine fires these generically via an
# EffectRegistry lookup by status_id, so _resolve_attack / _end_of_round name no discipline.


## Wound delta added when a player attack breaches the carrier (the defender). Hex → +1.
func on_wound_calc(_status: CombatStatus, _ctx: AttackContext) -> int:
	return 0


## Fires after a player attack fully resolves on the carrier. Time Lock armed→frozen transition.
func on_player_attack_resolved(_status: CombatStatus, _ctx: AttackContext) -> void:
	pass


## Fires at end_of_round for the carrier (may await). Echo resolution.
func on_end_of_round(_status: CombatStatus, _state: CombatantState) -> void:
	pass


## Fires per combatant during the end_of_round guard reset, AFTER reset. Time Lock frozen restore.
func on_guard_reset(_status: CombatStatus, _state: CombatantState, _enemy_index: int) -> void:
	pass


## Log line emitted when the status expires via duration tick, or "" for none.
func on_expire(_status: CombatStatus, _state: CombatantState) -> String:
	return ""
