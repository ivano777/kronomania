class_name MindBombEffect
extends CombatEffect

# Mind Detonation primed charge. Detonation is breach-driven: it fires from the round coroutines via
# _check_mind_detonation at Phase 2.1 (post player-attack), not from a spine lifecycle hook — so this
# handler only supplies the fizzle line when the charge expires unused.

func on_expire(_status: CombatStatus, _state: CombatantState) -> String:
	return "[color=purple]The mind-bomb goes inert. Stance was never broken.[/color]"
