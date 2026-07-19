# MainMenuScene — game entry point.
# Title screen, load slots, quit. Saves happen only at Campfire.
# All UI built in code; no sub-nodes required in the .tscn.
extends Control

var _slot_labels: Array[Label] = []
var _load_btns: Array[Button] = []
var _delete_btns: Array[Button] = []
var _pending_delete_slot: int = 0
var _delete_confirm: ConfirmationDialog

# New Game slot picker
var _new_game_popup: Control = null
var _ng_name_edit: LineEdit = null
var _ng_pending_slot: int = 0
var _ng_overwrite_confirm: ConfirmationDialog


func _ready() -> void:
	# CC0 town backdrop (import_env.py output), darkened so menu text stays readable.
	var bg_tex := SpriteRegistry.get_background("menu")
	if bg_tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.texture = bg_tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.modulate = Color(0.5, 0.5, 0.6)
		add_child(bg_rect)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "♦  KRONOMANIA  ♦"
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
		row.add_theme_constant_override("separation", 4)
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

	_ng_overwrite_confirm = ConfirmationDialog.new()
	_ng_overwrite_confirm.ok_button_text = "Overwrite"
	_ng_overwrite_confirm.cancel_button_text = "Cancel"
	_ng_overwrite_confirm.confirmed.connect(_on_ng_overwrite_confirmed)
	add_child(_ng_overwrite_confirm)

	_refresh_slots()


func _refresh_slots() -> void:
	for i in range(_slot_labels.size()):
		var slot := i + 1
		var meta := SaveManager.get_slot_meta(slot)
		if meta.get("exists", false):
			var ts: String = str(meta.get("timestamp", ""))
			var run_name: String = str(meta.get("run_name", ""))
			var name_part := ("[%s]  " % run_name) if run_name != "" else ""
			var defeated: bool = str(meta.get("last_result", "")) == "defeat"
			if defeated:
				_slot_labels[i].text = "SLOT %d — %sGAME OVER · Tier %d · %s" \
					% [slot, name_part, int(meta.get("tier", 1)), ts]
			else:
				_slot_labels[i].text = "SLOT %d — %sTier %d · Pts %d · %s" \
					% [slot, name_part, int(meta.get("tier", 1)), int(meta.get("points", 0)), ts]
			_load_btns[i].disabled = defeated
			_delete_btns[i].disabled = false
		else:
			_slot_labels[i].text = "SLOT %d — EMPTY" % slot
			_load_btns[i].disabled = true
			_delete_btns[i].disabled = true


func _on_new_game() -> void:
	_show_new_game_popup()


func _show_new_game_popup() -> void:
	_new_game_popup = ColorRect.new()
	_new_game_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_new_game_popup.color = Color(0.0, 0.0, 0.0, 0.65)
	_new_game_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_new_game_popup)

	var popup := PanelContainer.new()
	popup.anchor_left   = 0.15
	popup.anchor_right  = 0.85
	popup.anchor_top    = 0.08
	popup.anchor_bottom = 0.92
	_new_game_popup.add_child(popup)

	var popup_margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		popup_margin.add_theme_constant_override(side, 12)
	popup.add_child(popup_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	popup_margin.add_child(vbox)

	var title := Label.new()
	title.text = "♦  NEW GAME  ♦"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Run name"
	vbox.add_child(name_lbl)

	_ng_name_edit = LineEdit.new()
	_ng_name_edit.placeholder_text = "Enter a name…"
	_ng_name_edit.max_length = 32
	vbox.add_child(_ng_name_edit)

	vbox.add_child(HSeparator.new())

	for i in range(1, 4):
		var meta := SaveManager.get_slot_meta(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if meta.get("exists", false):
			var ts: String = str(meta.get("timestamp", ""))
			var run_name: String = str(meta.get("run_name", ""))
			var name_part := ("[%s]  " % run_name) if run_name != "" else ""
			slot_lbl.text = "Slot %d  %sTier %d · Pts %d · %s" \
				% [i, name_part, int(meta.get("tier", 1)), int(meta.get("points", 0)), ts]
		else:
			slot_lbl.text = "Slot %d — EMPTY" % i
		row.add_child(slot_lbl)

		var slot_btn := Button.new()
		slot_btn.text = "Overwrite" if meta.get("exists", false) else "Start Here"
		slot_btn.pressed.connect(_on_ng_slot_chosen.bind(i))
		row.add_child(slot_btn)

	vbox.add_child(HSeparator.new())

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void: _new_game_popup.queue_free())
	vbox.add_child(cancel_btn)


func _on_ng_slot_chosen(slot: int) -> void:
	var name := _ng_name_edit.text.strip_edges()
	if name.is_empty():
		_ng_name_edit.grab_focus()
		return
	var meta := SaveManager.get_slot_meta(slot)
	if meta.get("exists", false):
		_ng_pending_slot = slot
		var existing_name: String = str(meta.get("run_name", ""))
		var existing_str := (" '%s'" % existing_name) if existing_name != "" else ""
		_ng_overwrite_confirm.title = "Overwrite Slot %d?" % slot
		_ng_overwrite_confirm.dialog_text = \
			"Slot %d already has a save%s.\nThis cannot be undone. Overwrite?" % [slot, existing_str]
		_ng_overwrite_confirm.popup_centered()
	else:
		_commit_new_game(slot)


func _on_ng_overwrite_confirmed() -> void:
	_commit_new_game(_ng_pending_slot)


func _commit_new_game(slot: int) -> void:
	var run_name := _ng_name_edit.text.strip_edges()
	_new_game_popup.queue_free()
	DebugManager.sandbox_active = false   # real play — leave the dev sandbox
	SaveManager.active_slot = slot
	SaveManager.active_run_name = run_name
	PlayerProgression.reset()
	DungeonManager.start_run()
	# Hero variant is chosen on the dedicated screen next; the save is written
	# on the run's first Campfire (hero_sprite defaults to "player" until then).
	get_tree().change_scene_to_file("res://scenes/hero_select/HeroSelectScene.tscn")


func _on_load_slot(slot: int) -> void:
	var meta := SaveManager.get_slot_meta(slot)
	if not meta.get("exists", false):
		return
	DebugManager.sandbox_active = false   # real play — leave the dev sandbox
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
