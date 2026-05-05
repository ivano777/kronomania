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
	label.text = "%s: %s" % [data.combatant_name, _weapon_line(data.equipped_weapon)]


func _weapon_line(w: EquipmentData) -> String:
	if w == null:
		return "(no weapon)"
	var tag_str := ", ".join(w.tags) if not w.tags.is_empty() else "none"
	return "%s  Pot %d | Atk+%d Def+%d Pool%+d Wounds+%d | [%s]" % [
		w.item_name, w.potency, w.flat_attack_bonus, w.flat_guard_bonus,
		w.pool_bonus, w.max_wounds_bonus, tag_str,
	]
