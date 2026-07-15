# EquipmentScene — RPG paper-doll equipment screen.
# Left: player doll with equip slot frames (hand slots functional; armor slots
# are locked placeholders until the armor system exists). Right: armoury grid
# of icon slots for every available item. All UI built in code; the .tscn is a
# bare Control + script (campfire pattern).
extends Control

const _PLAYER_DATA := preload("res://resources/data/player_default.tres")

const SLOT_PX := 28          # outer slot frame (Minecraft-style square)
const ICON_PX := 16          # pipeline icons are 16×16
const SELECTED_TINT := Color(1.3, 1.3, 0.6)
const LOCKED_TINT := Color(0.45, 0.45, 0.45)
const ELSEWHERE_TINT := Color(0.55, 0.55, 0.55)

## Ordered slot descriptors. Armor slots ship locked (functional=false):
## adding a real one later = new PlayerProgression field + serialize key +
## flipping functional here (get/set routing lives in _slot_item/_equip_into).
var _slot_defs: Array = [
	{"id": "head",      "label": "Head",  "functional": false, "pos": Vector2(96, 74)},
	{"id": "chest",     "label": "Chest", "functional": false, "pos": Vector2(96, 118)},
	{"id": "legs",      "label": "Legs",  "functional": false, "pos": Vector2(96, 162)},
	{"id": "feet",      "label": "Feet",  "functional": false, "pos": Vector2(96, 206)},
	{"id": "main_hand", "label": "Main",  "functional": true,  "pos": Vector2(248, 96)},
	{"id": "off_hand",  "label": "Off",   "functional": true,  "pos": Vector2(248, 162)},
]

var _slot_panels: Dictionary = {}    # id -> PanelContainer
var _slot_icons: Dictionary = {}     # id -> TextureRect
var _slot_fallback: Dictionary = {}  # id -> Label (initials fallback / × locked)
var _inv_panels: Array = []          # aligned with AVAILABLE_WEAPONS
var _inv_icons: Array = []
var _inv_fallback: Array = []
var _inv_marks: Array = []           # "✓" equipped markers
var _hands_label: Label
var _equip_hint: Label
var _selected_slot: String = "main_hand"


func _ready() -> void:
	# --- Title ---
	var title := Label.new()
	title.text = "♦  EQUIPMENT  ♦"
	title.add_theme_font_size_override("font_size", 32)
	title.position = Vector2(10, 4)
	add_child(title)

	# --- Paper doll: player idle sprite between the slot columns ---
	var hero_key := PlayerProgression.hero_sprite
	var frames := SpriteRegistry.get_combatant_frames(hero_key)
	if frames != null:
		var doll := AnimatedSprite2D.new()
		doll.sprite_frames = frames
		doll.position = Vector2(186, 168)
		doll.scale = Vector2(2, 2)
		# Pack frames are cropped to the union bbox across ALL anims, so the
		# default player idle figure sits off-center inside its frame (attack
		# poses pad the right side). Counter-offset centers it on position.
		# Measured on player idle_sheet.png: content center (99.5, 43) vs
		# frame center (64, 34.5) — re-measure if the pack is re-imported.
		# Heroine frames are horizontally centered with the same feet line, so
		# only the shared vertical counter-offset applies.
		doll.offset = Vector2(-35.5, -8.5) if hero_key == "player" else Vector2(0, -8)
		doll.play("idle")
		add_child(doll)
	else:
		var body := ColorRect.new()
		body.color = Color(0.20, 0.35, 0.80)
		body.position = Vector2(138, 104)
		body.size = Vector2(96, 128)
		add_child(body)

	# --- Doll slots (locked armor placeholders + functional hand slots) ---
	for def in _slot_defs:
		var id: String = def["id"]
		var made := _make_slot()
		var panel: PanelContainer = made["panel"]
		panel.position = def["pos"] as Vector2
		add_child(panel)
		_slot_panels[id] = panel
		_slot_icons[id] = made["icon"]
		_slot_fallback[id] = made["fallback"]

		var caption := Label.new()
		caption.text = def["label"]
		caption.custom_minimum_size = Vector2(48, 0)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = (def["pos"] as Vector2) + Vector2(-10, SLOT_PX + 1)
		caption.modulate = Color(1, 1, 1, 0.7)
		add_child(caption)

		if def["functional"]:
			panel.gui_input.connect(_on_slot_gui_input.bind(id))
		else:
			panel.tooltip_text = "%s — coming soon" % def["label"]
			caption.modulate = Color(1, 1, 1, 0.4)

	# --- Equipped-hands summary under the doll ---
	_hands_label = Label.new()
	_hands_label.position = Vector2(64, 252)
	_hands_label.custom_minimum_size = Vector2(248, 0)
	_hands_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hands_label)

	# --- Armoury panel (right) ---
	var inv_panel := PanelContainer.new()
	inv_panel.position = Vector2(330, 44)
	inv_panel.custom_minimum_size = Vector2(300, 0)
	add_child(inv_panel)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	inv_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var inv_title := Label.new()
	inv_title.text = "♦  ARMOURY  ♦"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(inv_title)

	_equip_hint = Label.new()
	_equip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_equip_hint)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for i in PlayerProgression.AVAILABLE_WEAPONS.size():
		var w: EquipmentData = PlayerProgression.AVAILABLE_WEAPONS[i] as EquipmentData
		var made := _make_slot()
		var panel: PanelContainer = made["panel"]
		grid.add_child(panel)
		panel.gui_input.connect(_on_inventory_gui_input.bind(i))
		TooltipManager.attach(panel, w)

		var mark := Label.new()
		mark.text = "✓"
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.visible = false
		panel.add_child(mark)

		_inv_panels.append(panel)
		_inv_icons.append(made["icon"])
		_inv_fallback.append(made["fallback"])
		_inv_marks.append(mark)

	var hint := Label.new()
	hint.text = "Left-click: equip · Right-click: details"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)

	# --- Back ---
	var back_btn := Button.new()
	back_btn.text = "▶  Back"
	back_btn.position = Vector2(10, 330)
	back_btn.custom_minimum_size = Vector2(96, 22)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)

	_refresh()


# ── Pure helpers (unit-tested) ────────────────────────────────────────────────

## Two-character fallback shown when an item has no icon: initials of the
## first two words, or the first two letters of a single-word name.
static func fallback_initials(item_name: String) -> String:
	var words := item_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	if words.size() == 1:
		return words[0].substr(0, 2).to_upper()
	return "??"


# ── Slot plumbing ─────────────────────────────────────────────────────────────

func _slot_item(id: String) -> EquipmentData:
	match id:
		"main_hand":
			return PlayerProgression.main_hand
		"off_hand":
			return PlayerProgression.off_hand
	return null


func _equip_into(id: String, item: EquipmentData) -> void:
	match id:
		"main_hand":
			PlayerProgression.equip_main_hand(item)
		"off_hand":
			PlayerProgression.equip_off_hand(item)


## Builds one 28×28 slot frame: themed panel + centered icon + fallback label.
func _make_slot() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
	var center := CenterContainer.new()
	panel.add_child(center)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
	var fallback := Label.new()
	fallback.visible = false
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(fallback)
	return {"panel": panel, "icon": icon, "fallback": fallback}


func _set_slot_visual(icon: TextureRect, fallback: Label, item: EquipmentData) -> void:
	if item == null:
		icon.texture = null
		fallback.visible = false
		return
	var tex := SpriteRegistry.get_icon("weapons", SpriteRegistry.icon_key(item.item_name))
	icon.texture = tex
	fallback.text = fallback_initials(item.item_name)
	fallback.visible = tex == null


# ── Input ─────────────────────────────────────────────────────────────────────

func _on_slot_gui_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var item := _slot_item(id)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if _selected_slot == id and item != null:
			_equip_into(id, null)  # second click on the selected filled slot unequips
		else:
			_selected_slot = id
		_refresh()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and item != null:
		get_viewport().set_input_as_handled()
		var panel: PanelContainer = _slot_panels[id]
		TooltipManager.show_for(item, panel.get_screen_position() + mb.position, panel)


func _on_inventory_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var w: EquipmentData = PlayerProgression.AVAILABLE_WEAPONS[index] as EquipmentData
	var mh := PlayerProgression.main_hand
	var oh := PlayerProgression.off_hand
	var in_other := (w == oh and _selected_slot == "main_hand") \
			or (w == mh and _selected_slot == "off_hand")
	if in_other:
		return  # campfire rule: an item can't sit in both hands — click is inert
	var current := _slot_item(_selected_slot)
	_equip_into(_selected_slot, null if current == w else w)
	_refresh()


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	var mh := PlayerProgression.main_hand
	var oh := PlayerProgression.off_hand
	var mh_two_handed := mh != null and mh.get_hands_required() == 2

	# A two-handed main occupies both hands: force selection back to main.
	if mh_two_handed and _selected_slot == "off_hand":
		_selected_slot = "main_hand"

	for def in _slot_defs:
		var id: String = def["id"]
		var panel: PanelContainer = _slot_panels[id]
		if not def["functional"]:
			panel.modulate = LOCKED_TINT
			(_slot_fallback[id] as Label).text = "×"
			(_slot_fallback[id] as Label).visible = true
			continue
		var item := _slot_item(id)
		_set_slot_visual(_slot_icons[id], _slot_fallback[id], item)
		if id == "off_hand" and mh_two_handed:
			# Ghost of the two-hander: shown dimmed, not selectable.
			_set_slot_visual(_slot_icons[id], _slot_fallback[id], mh)
			panel.modulate = LOCKED_TINT
		else:
			panel.modulate = SELECTED_TINT if id == _selected_slot else Color.WHITE

	var mh_name := mh.item_name if mh else "(empty)"
	var oh_name := "— (2H)" if mh_two_handed else (oh.item_name if oh else "(empty)")
	_hands_label.text = "Main: %s  ·  Off: %s" % [mh_name, oh_name]

	var slot_label := "Main Hand" if _selected_slot == "main_hand" else "Off Hand"
	_equip_hint.text = "Equip to: %s" % slot_label

	for i in _inv_panels.size():
		var w: EquipmentData = PlayerProgression.AVAILABLE_WEAPONS[i] as EquipmentData
		_set_slot_visual(_inv_icons[i], _inv_fallback[i], w)
		var equipped := w == mh or w == oh
		var in_selected := (w == mh and _selected_slot == "main_hand") \
				or (w == oh and _selected_slot == "off_hand")
		_inv_marks[i].visible = equipped
		if in_selected:
			(_inv_panels[i] as PanelContainer).modulate = SELECTED_TINT
		elif equipped:
			(_inv_panels[i] as PanelContainer).modulate = ELSEWHERE_TINT
		else:
			(_inv_panels[i] as PanelContainer).modulate = Color.WHITE


# ── Navigation ────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	if DungeonManager.run_active:
		get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
