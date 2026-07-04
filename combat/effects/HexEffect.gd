class_name HexEffect
extends CombatEffect

# Hex Mastery / Mind Rend brand. While active on an enemy, every player breach on it (any pool)
# deals +1 wound. Applied by Disciplines.cast_mind_rend on a Resolve breach; expires by duration.
# The caller only invokes on_wound_calc for player-on-enemy breaches, so the +1 is unconditional here.

func on_wound_calc(_status: CombatStatus, _ctx: AttackContext) -> int:
	CombatManager.log_message.emit("  [color=purple]The hex flares — the wound cuts deeper (+1)![/color]")
	return 1


func on_expire(_status: CombatStatus, state: CombatantState) -> String:
	return "[color=purple]The hex fades from %s — the brand has run its course.[/color]" % state.data.combatant_name
