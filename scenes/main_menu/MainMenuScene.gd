# MainMenuScene — game entry point.
# Title screen, load slots, quit. Saves happen only at Campfire.
# All UI built in code; no sub-nodes required in the .tscn.
extends Control

var _slot_labels: Array[Label] = []
var _load_btns: Array[Button] = []
var _delete_btns: Array[Button] = []
var _pending_delete_slot: int = 0
var _delete_confirm: ConfirmationDialog


func _ready() -> void:
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

	var title := Label.new()
	title.text = "◆  KRONOMANIA  ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var new_game_btn := Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.pressed.connect(_on_new_game)
	vbox.add_child(new_game_btn)

	vbox.add_child(HSeparator.new())

	var saves_header := Label.new()
	saves_header.text = "Load Game"
	vbox.add_child(saves_header)

	for i in range(1, 4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot_lbl)
		_slot_labels.append(slot_lbl)

		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.pressed.connect(_on_load_slot.bind(i))
		row.add_child(load_btn)
		_load_btns.append(load_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(_on_delete_slot.bind(i))
		row.add_child(del_btn)
		_delete_btns.append(del_btn)

	vbox.add_child(HSeparator.new())

	var settings_btn := Button.new()
	settings_btn.text = "Settings  (coming soon)"
	settings_btn.disabled = true
	vbox.add_child(settings_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.ok_button_text = "Delete"
	_delete_confirm.cancel_button_text = "Cancel"
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)

	_refresh_slots()


func _refresh_slots() -> void:
	for i in range(_slot_labels.size()):
		var slot := i + 1
		var meta := SaveManager.get_slot_meta(slot)
		if meta.get("exists", false):
			var ts: String = str(meta.get("timestamp", ""))
			var date_part := ts.substr(0, 10) if ts.length() >= 10 else ts
			var defeated: bool = str(meta.get("last_result", "")) == "defeat"
			if defeated:
				_slot_labels[i].text = "SLOT %d — GAME OVER · Tier %d · %s" \
					% [slot, int(meta.get("tier", 1)), date_part]
			else:
				_slot_labels[i].text = "SLOT %d — Tier %d · Pts %d · %s" \
					% [slot, int(meta.get("tier", 1)), int(meta.get("points", 0)), date_part]
			_load_btns[i].disabled = defeated
			_delete_btns[i].disabled = false
		else:
			_slot_labels[i].text = "SLOT %d — EMPTY" % slot
			_load_btns[i].disabled = true
			_delete_btns[i].disabled = true


func _on_new_game() -> void:
	PlayerProgression.reset()
	DungeonManager.start_run()
	get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")


func _on_load_slot(slot: int) -> void:
	var meta := SaveManager.get_slot_meta(slot)
	if not meta.get("exists", false):
		return
	SaveManager.load(slot)
	if DungeonManager.run_active:
		get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")
	else:
		_refresh_slots()


func _on_delete_slot(slot: int) -> void:
	_pending_delete_slot = slot
	_delete_confirm.title = "Delete Slot %d?" % slot
	_delete_confirm.dialog_text = "Slot %d will be permanently erased.\nThis cannot be undone." % slot
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	SaveManager.delete_slot(_pending_delete_slot)
	_refresh_slots()


func _on_quit() -> void:
	get_tree().quit()
