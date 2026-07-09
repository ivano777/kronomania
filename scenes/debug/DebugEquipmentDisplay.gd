extends VBoxContainer


func _ready() -> void:
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func setup(player_data: CombatantData, enemy_data: CombatantData) -> void:
	_show_player($PlayerEquip, player_data)
	_show($EnemyEquip, enemy_data)


func _show_player(label: Label, data: CombatantData) -> void:
	var mh: EquipmentData = PlayerProgression.main_hand if PlayerProgression.main_hand else data.equipped_weapon
	var oh: EquipmentData = PlayerProgression.off_hand
	label.text = "%s  MH: %s  |  OH: %s" % [
		data.combatant_name,
		_weapon_line(mh),
		_weapon_line(oh) if oh != null else "(empty)",
	]


func _show(label: Label, data: CombatantData) -> void:
	if data.equipped_weapon != null:
		label.text = "%s: %s" % [data.combatant_name, _weapon_line(data.equipped_weapon)]
	else:
		# Weaponless enemy (enemy = tier + action list): summarize its actions.
		var parts: Array[String] = []
		for m: ActionModifier in data.bare_hands_actions:
			var flat_str := " %+d" % m.flat_bonus if m.flat_bonus != 0 else ""
			parts.append("%s (%s%s)" % [m.action_name, m.action_key, flat_str])
		label.text = "%s: %s" % [data.combatant_name, " | ".join(parts) if not parts.is_empty() else "(no actions)"]


func _weapon_line(w: EquipmentData) -> String:
	if w == null:
		return "(no weapon)"
	var tag_str := ", ".join(w.tags) if not w.tags.is_empty() else "none"
	var atk_flat := 0
	var def_flat := 0
	var pool_b   := 0
	for mod in w.action_modifiers:
		if mod.action_key == "strike":
			atk_flat = mod.flat_bonus
			pool_b   = mod.pool_bonus
		elif mod.action_key == "defend":
			def_flat = mod.flat_bonus
	return "%s  Atk+%d Def+%d Pool%+d Wounds+%d | [%s]" % [
		w.item_name, atk_flat, def_flat,
		pool_b, w.max_wounds_bonus, tag_str,
	]
