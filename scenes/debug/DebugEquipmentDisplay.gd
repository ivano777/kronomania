extends VBoxContainer


func setup(player_data: CombatantData, enemy_data: CombatantData) -> void:
	_show($PlayerEquip, player_data)
	_show($EnemyEquip, enemy_data)


func _show(label: Label, data: CombatantData) -> void:
	if data.equipped_weapon:
		var w := data.equipped_weapon
		var tag_str := ", ".join(w.tags) if not w.tags.is_empty() else "none"
		label.text = "%s: %s  Pot %d | Atk+%d Def+%d Pool%+d Wounds+%d | [%s]" % [
			data.combatant_name, w.item_name,
			w.potency, w.flat_attack_bonus, w.flat_guard_bonus,
			w.pool_bonus, w.max_wounds_bonus, tag_str,
		]
	else:
		label.text = "%s: (no weapon)" % data.combatant_name
