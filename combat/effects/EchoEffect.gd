class_name EchoEffect
extends CombatEffect

# Echoing Mind / Mind Lash. Lives on the caster (player). Each end_of_round it re-resolves the
# frozen spell with decaying kept dice and self-terminates when the kept count hits 0 — all inside
# Disciplines.resolve_spell_echo. on_expire only fires if the duration safety bound trips first.

func on_end_of_round(status: CombatStatus, state: CombatantState) -> void:
	await Disciplines.resolve_spell_echo(status, state)


func on_expire(_status: CombatStatus, _state: CombatantState) -> String:
	return "[color=red][debug] echoing_spell expired via duration_rounds — should have self-terminated. Investigate.[/color]"
