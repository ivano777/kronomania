extends Control

# DEV SANDBOX hub — full-screen dev scene, deliberately ugly-honest so it can
# never be mistaken for the player-facing menu (maroon backdrop, × DEV title).
# Reached from the MainMenu F12 widget; Esc / Back returns to the menu.
#
# Owns the persistent per-session sandbox: first jump seeds 999pt progression,
# an active run (Campfire won't reset it) and active_slot 0 (autosave off, real
# slots untouched). Later jumps keep all state — pick nodes, gear up, then
# fight the Training Dummy with exactly that build. Reset Sandbox reseeds.

const _MENU_SCENE := "res://scenes/main_menu/MainMenuScene.tscn"
const _SELF_SCENE := "res://scenes/debug/DevHubScene.tscn"

var _hero_picker: OptionButton
var _info: Label
var _status: Label
var _heroes: Array[String] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Hazard header band
	var band := ColorRect.new()
	band.color = Color(0.32, 0.10, 0.12)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 44.0
	add_child(band)
	var title := Label.new()
	title.text = "×  DEV SANDBOX  ×"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 4.0
	add_child(title)

	# Left column — actions
	var col := VBoxContainer.new()
	col.position = Vector2(24, 64)
	col.custom_minimum_size = Vector2(200, 0)
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	col.add_child(_mk_label("Hero"))
	_hero_picker = OptionButton.new()
	_scan_heroes()
	_hero_picker.item_selected.connect(_on_hero_picked)
	col.add_child(_hero_picker)

	col.add_child(_mk_sep())
	col.add_child(_mk_btn("Sandbox Hub (Campfire)", _jump.bind("res://scenes/campfire/CampfireScene.tscn")))
	col.add_child(_mk_btn("Constellation", _jump.bind("res://scenes/constellation/ConstellationScene.tscn")))
	col.add_child(_mk_btn("Equipment", _jump.bind("res://scenes/equipment/EquipmentScene.tscn")))
	col.add_child(_mk_btn("Training Dummy", _open_training))
	col.add_child(_mk_btn("Held-Anchor Editor", _open_held_editor))
	col.add_child(_mk_sep())
	col.add_child(_mk_btn("Reset Sandbox", _reset_sandbox))
	col.add_child(_mk_btn("Wipe Saves", _wipe_saves))
	col.add_child(_mk_sep())
	col.add_child(_mk_btn("▶ Back to Menu", _back))

	# Right column — live sandbox state
	var right := VBoxContainer.new()
	right.position = Vector2(300, 64)
	right.custom_minimum_size = Vector2(316, 0)
	add_child(right)
	right.add_child(_mk_label("SANDBOX STATE"))
	_info = _mk_label("")
	right.add_child(_info)
	_status = _mk_label("")
	_status.modulate = Color(1.0, 0.8, 0.5)
	right.add_child(_status)

	# EXPERIMENTS — prototype toys, no sandbox needed. Lives in the right
	# column: the left action column is already at the 360px height budget.
	right.add_child(_mk_sep())
	right.add_child(_mk_label("EXPERIMENTS"))
	right.add_child(_mk_btn("Aura Lab", _open_aura_lab))

	if DebugManager.sandbox_active:
		_sync_picker_to_hero()
	_refresh_info()


# ── UI helpers ────────────────────────────────────────────────────────────────

func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _mk_btn(t: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(fn)
	return b


func _mk_sep() -> HSeparator:
	return HSeparator.new()


# ── Heroes ────────────────────────────────────────────────────────────────────

# Heroes = combatant folders with a held.json (the playable variants).
func _scan_heroes() -> void:
	var d := DirAccess.open("res://assets/sprites/combatants")
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if d.current_is_dir() and not f.begins_with("."):
				if FileAccess.file_exists("res://assets/sprites/combatants/%s/held.json" % f):
					_heroes.append(f)
			f = d.get_next()
	_heroes.sort()
	for h in _heroes:
		_hero_picker.add_item(h)


func _sync_picker_to_hero() -> void:
	var idx := _heroes.find(PlayerProgression.hero_sprite)
	if idx >= 0:
		_hero_picker.selected = idx


func _picked_hero() -> String:
	if _heroes.is_empty():
		return "player"
	return _heroes[clampi(_hero_picker.selected, 0, _heroes.size() - 1)]


func _on_hero_picked(_i: int) -> void:
	PlayerProgression.hero_sprite = _picked_hero()
	_status.text = "hero: %s" % PlayerProgression.hero_sprite
	_refresh_info()


# ── Sandbox ───────────────────────────────────────────────────────────────────

## Initialises the sandbox once per session; later calls keep all state.
func _ensure_sandbox() -> void:
	if DebugManager.sandbox_active:
		PlayerProgression.hero_sprite = _picked_hero()
		return
	PlayerProgression.reset()
	PlayerProgression.debug_set_points(999)
	PlayerProgression.hero_sprite = _picked_hero()
	DungeonManager.start_run()      # run_active: Campfire won't reset progression
	SaveManager.active_slot = 0     # Campfire autosave disabled — slots stay clean
	DebugManager.sandbox_active = true


func _refresh_info() -> void:
	var lines: Array[String] = []
	lines.append("sandbox: %s" % ("ACTIVE" if DebugManager.sandbox_active else "not seeded"))
	lines.append("hero: %s" % PlayerProgression.hero_sprite)
	if DebugManager.sandbox_active:
		lines.append("points: %d" % PlayerProgression.available_points)
		lines.append("run active: %s" % str(DungeonManager.run_active))
	lines.append("")
	lines.append("Jumps keep node/equip choices.")
	lines.append("Campfire links every screen;")
	lines.append("its screens return there.")
	_info.text = "\n".join(lines)


func _jump(scene: String) -> void:
	_ensure_sandbox()
	get_tree().change_scene_to_file(scene)


func _open_training() -> void:
	_ensure_sandbox()
	DungeonManager.start_training()
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")


func _open_held_editor() -> void:
	DebugManager.return_scene = _SELF_SCENE
	get_tree().change_scene_to_file("res://tools/held_editor/HeldEditor.tscn")


func _open_aura_lab() -> void:
	get_tree().change_scene_to_file("res://scenes/debug/experiments/AuraStudioScene.tscn")


func _reset_sandbox() -> void:
	DebugManager.sandbox_active = false
	_ensure_sandbox()
	_status.text = "sandbox reset · 999pt"
	_refresh_info()


func _wipe_saves() -> void:
	for slot in range(1, 4):
		SaveManager.delete_slot(slot)
	_status.text = "saves wiped"


func _back() -> void:
	get_tree().change_scene_to_file(_MENU_SCENE)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_back()
