# CampfireScene — between-encounter rest hub.
# Short Rest (once per run), Long Rest (ambush risk), weapon selection, save popup, constellation, continue.
# All UI built in code; no sub-nodes required in the .tscn.
extends Control

const _PLAYER_DATA := preload("res://resources/data/player_default.tres")

var _status_label: Label
var _run_label: Label
var _fervor_label: Label
var _rest_feedback: Label
var _short_rest_btn: Button
var _long_rest_btn: Button
var _continue_btn: Button
var _weapon_btns: Array[Button] = []

# Save popup
var _save_overlay: ColorRect
var _save_popup: PanelContainer
var _popup_slot_labels: Array[Label] = []
var _popup_delete_btns: Array[Button] = []
var _pending_save_slot: int = 0
var _pending_delete_slot: int = 0
var _overwrite_confirm: ConfirmationDialog
var _delete_confirm: ConfirmationDialog

# Exit confirmation
var _exit_confirm: ConfirmationDialog


func _ready() -> void:
	if not DungeonManager.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
		return

	if SaveManager.active_slot > 0:
		SaveManager.save(SaveManager.active_slot)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	var header := Label.new()
	header.text = "◆  CAMPFIRE  ◆"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	_status_label = Label.new()
	vbox.add_child(_status_label)

	_fervor_label = Label.new()
	vbox.add_child(_fervor_label)

	_run_label = Label.new()
	vbox.add_child(_run_label)

	vbox.add_child(HSeparator.new())

	var equip_header := Label.new()
	equip_header.text = "Equipment"
	vbox.add_child(equip_header)

	var weapon_row := HBoxContainer.new()
	vbox.add_child(weapon_row)
	for w in PlayerProgression.AVAILABLE_WEAPONS:
		var btn := Button.new()
		btn.text = (w as EquipmentData).item_name
		btn.pressed.connect(_on_equip_weapon.bind(w))
		weapon_row.add_child(btn)
		_weapon_btns.append(btn)

	vbox.add_child(HSeparator.new())

	# --- CONSUMABLES (deferred) ---
	var consumables_label := Label.new()
	consumables_label.text = "No consumables."
	vbox.add_child(consumables_label)

	vbox.add_child(HSeparator.new())

	_short_rest_btn = Button.new()
	_short_rest_btn.pressed.connect(_on_short_rest)
	vbox.add_child(_short_rest_btn)

	var long_rest_btn := Button.new()
	long_rest_btn.pressed.connect(_on_long_rest)
	vbox.add_child(long_rest_btn)
	_long_rest_btn = long_rest_btn

	_rest_feedback = Label.new()
	_rest_feedback.hide()
	vbox.add_child(_rest_feedback)

	vbox.add_child(HSeparator.new())

	var const_btn := Button.new()
	const_btn.text = "Constellation"
	const_btn.pressed.connect(_on_constellation)
	vbox.add_child(const_btn)

	var save_game_btn := Button.new()
	save_game_btn.text = "Save Game"
	save_game_btn.pressed.connect(_on_open_save_popup)
	vbox.add_child(save_game_btn)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)

	var give_up_btn := Button.new()
	give_up_btn.text = "Give Up"
	give_up_btn.pressed.connect(_on_give_up)
	vbox.add_child(give_up_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit to Menu"
	exit_btn.pressed.connect(_on_exit_pressed)
	vbox.add_child(exit_btn)

	# Overlays must be added last so they render on top.
	_build_save_popup()
	_build_exit_confirm()

	_refresh()


func _build_save_popup() -> void:
	_save_overlay = ColorRect.new()
	_save_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_save_overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	_save_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_overlay.hide()
	add_child(_save_overlay)

	_save_popup = PanelContainer.new()
	_save_popup.anchor_left   = 0.2
	_save_popup.anchor_right  = 0.8
	_save_popup.anchor_top    = 0.2
	_save_popup.anchor_bottom = 0.8
	_save_popup.offset_left   = 0.0
	_save_popup.offset_right  = 0.0
	_save_popup.offset_top    = 0.0
	_save_popup.offset_bottom = 0.0
	_save_popup.hide()
	add_child(_save_popup)

	var popup_margin := MarginContainer.new()
	popup_margin.add_theme_constant_override("margin_top", 24)
	popup_margin.add_theme_constant_override("margin_left", 24)
	popup_margin.add_theme_constant_override("margin_right", 24)
	popup_margin.add_theme_constant_override("margin_bottom", 24)
	_save_popup.add_child(popup_margin)

	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 14)
	popup_margin.add_child(popup_vbox)

	var popup_header := Label.new()
	popup_header.text = "◆  SAVE GAME  ◆"
	popup_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_vbox.add_child(popup_header)

	popup_vbox.add_child(HSeparator.new())

	for i in range(1, 4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		popup_vbox.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot_lbl)
		_popup_slot_labels.append(slot_lbl)

		var slot_btn := Button.new()
		slot_btn.text = "Save"
		slot_btn.pressed.connect(_on_popup_save_slot.bind(i))
		row.add_child(slot_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(_on_popup_delete_slot.bind(i))
		row.add_child(del_btn)
		_popup_delete_btns.append(del_btn)

	popup_vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_save_popup)
	popup_vbox.add_child(close_btn)

	_overwrite_confirm = ConfirmationDialog.new()
	_overwrite_confirm.ok_button_text = "Overwrite"
	_overwrite_confirm.cancel_button_text = "Cancel"
	_overwrite_confirm.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_confirm)

	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.ok_button_text = "Delete"
	_delete_confirm.cancel_button_text = "Cancel"
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)


func _build_exit_confirm() -> void:
	_exit_confirm = ConfirmationDialog.new()
	_exit_confirm.title = "Exit to Main Menu"
	_exit_confirm.dialog_text = "Any unsaved progress will be lost.\nReturn to the main menu?"
	_exit_confirm.ok_button_text = "Exit"
	_exit_confirm.cancel_button_text = "Stay"
	_exit_confirm.confirmed.connect(_on_exit_confirmed)
	add_child(_exit_confirm)


func _refresh() -> void:
	var tier    := PlayerProgression.get_tier()
	var wounds  := PlayerProgression.saved_wounds
	var max_w   := _max_wounds()
	var pts     := PlayerProgression.available_points
	_status_label.text = "Tier: %d  |  Wounds: %d / %d  |  Points: %d" % [tier, wounds, max_w, pts]

	var fervor  := PlayerProgression.saved_fervor_size
	var burned  := PlayerProgression.saved_is_burned_out
	var has_mag := PlayerProgression.get_known_spells().size() > 0 \
				or PlayerProgression.get_known_cantrips().size() > 0
	if has_mag:
		var burnout_str := "  [BURNOUT]" if burned else ""
		_fervor_label.text = "Fervor: d%d%s" % [fervor, burnout_str]
		_fervor_label.show()
	else:
		_fervor_label.hide()

	var cleared := DungeonManager.enemies_cleared()
	if cleared == 0:
		_run_label.text = "Ready to enter the dungeon  (0 / %d cleared)" % DungeonManager.enemies_total()
	else:
		_run_label.text = "%d / %d encounters cleared" % [cleared, DungeonManager.enemies_total()]

	var eff_weapon: EquipmentData = PlayerProgression.equipped_weapon \
		if PlayerProgression.equipped_weapon != null \
		else _PLAYER_DATA.equipped_weapon
	for i in _weapon_btns.size():
		_weapon_btns[i].disabled = (PlayerProgression.AVAILABLE_WEAPONS[i] == eff_weapon)

	if DungeonManager.short_rest_used:
		_short_rest_btn.text = "Short Rest  (used)"
		_short_rest_btn.disabled = true
	else:
		_short_rest_btn.text = "Short Rest  (−1 wound, step down Fervor, clear Burnout)"
		_short_rest_btn.disabled = false

	if DungeonManager.long_rest_used:
		_long_rest_btn.text = "Long Rest  (used)"
		_long_rest_btn.disabled = true
	else:
		_long_rest_btn.text = "Long Rest  (full heal + reset Fervor; 50% ambush risk)"
		_long_rest_btn.disabled = false


func _refresh_popup_slots() -> void:
	for i in range(_popup_slot_labels.size()):
		var slot := i + 1
		var meta := SaveManager.get_slot_meta(slot)
		var has_data: bool = meta.get("exists", false)
		if has_data:
			var ts: String = str(meta.get("timestamp", ""))
			var date_part := ts.substr(0, 10) if ts.length() >= 10 else ts
			_popup_slot_labels[i].text = "SLOT %d — Tier %d · Pts %d · %s" \
				% [slot, int(meta.get("tier", 1)), int(meta.get("points", 0)), date_part]
		else:
			_popup_slot_labels[i].text = "SLOT %d — EMPTY" % slot
		_popup_delete_btns[i].disabled = not has_data


# --- Save popup ---

func _on_open_save_popup() -> void:
	_refresh_popup_slots()
	_save_overlay.show()
	_save_popup.show()


func _on_close_save_popup() -> void:
	_save_popup.hide()
	_save_overlay.hide()


func _on_popup_save_slot(slot: int) -> void:
	var meta := SaveManager.get_slot_meta(slot)
	if meta.get("exists", false):
		_pending_save_slot = slot
		_overwrite_confirm.title = "Overwrite Slot %d?" % slot
		_overwrite_confirm.dialog_text = "Slot %d already contains data.\nThis cannot be undone. Overwrite?" % slot
		_overwrite_confirm.popup_centered()
	else:
		SaveManager.save(slot)
		_refresh_popup_slots()


func _on_overwrite_confirmed() -> void:
	SaveManager.save(_pending_save_slot)
	_refresh_popup_slots()


func _on_popup_delete_slot(slot: int) -> void:
	_pending_delete_slot = slot
	_delete_confirm.title = "Delete Slot %d?" % slot
	_delete_confirm.dialog_text = "Slot %d will be permanently erased.\nThis cannot be undone." % slot
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	SaveManager.delete_slot(_pending_delete_slot)
	_refresh_popup_slots()


# --- Exit ---

func _on_exit_pressed() -> void:
	_exit_confirm.popup_centered()


func _on_exit_confirmed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")


# --- Rest / actions ---

func _on_equip_weapon(w: EquipmentData) -> void:
	PlayerProgression.set_weapon(w)
	_refresh()


func _on_short_rest() -> void:
	DungeonManager.attempt_short_rest()
	_rest_feedback.text = "Rested briefly. Wounds eased."
	_rest_feedback.show()
	_refresh()


func _on_long_rest() -> void:
	var result := DungeonManager.attempt_long_rest()
	if result.get("ambushed", false):
		_rest_feedback.text = "⚠ Ambushed during rest! Fight incoming..."
		_rest_feedback.show()
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	else:
		_rest_feedback.text = "Rested safely. Wounds healed, Fervor reset."
		_rest_feedback.show()
		_refresh()


func _on_constellation() -> void:
	get_tree().change_scene_to_file("res://scenes/constellation/ConstellationScene.tscn")


func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")


func _on_give_up() -> void:
	var result := DungeonManager.surrender()
	var msg := "Surrendered. HP fully restored."
	if result.get("lost_points", 0) > 0:
		msg += "  Lost %d points." % result.get("lost_points")
	if result.get("lost_weapon", false):
		msg += "  Dropped your weapon."
	_rest_feedback.text = msg
	_rest_feedback.show()
	_refresh()


# --- Helpers ---

func _effective_stat_size(stat: String) -> int:
	var base: int
	match stat:
		"dominion":  base = _PLAYER_DATA.dominion_size
		"negation":  base = _PLAYER_DATA.negation_size
		"ingenuity": base = _PLAYER_DATA.ingenuity_size
		_: base = 4
	var best := base
	for node in PlayerProgression.node_levels.keys():
		var lvl: int = PlayerProgression.node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == "stat_size_" + stat:
				best = maxi(best, ld.effect_value)
	return best


func _max_wounds() -> int:
	var tier  := PlayerProgression.get_tier()
	var base  := _PLAYER_DATA.max_wounds
	var eff_w: EquipmentData = PlayerProgression.equipped_weapon \
		if PlayerProgression.equipped_weapon != null else _PLAYER_DATA.equipped_weapon
	var equip := eff_w.max_wounds_bonus if eff_w else 0
	var bonus := 0
	for node in PlayerProgression.node_levels.keys():
		var lvl: int = PlayerProgression.node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			if (nd.levels_data[i] as NodeLevelData).effect_type == "training_wounds":
				bonus += (nd.levels_data[i] as NodeLevelData).effect_value
	return base + equip + (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0) + bonus
