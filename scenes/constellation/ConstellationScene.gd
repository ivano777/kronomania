extends Control

const _PLAYER_DATA: CombatantData = preload("res://resources/data/player_default.tres")
const _DBG_PROGRESSION := "res://scenes/debug/DebugProgressionControl.tscn"

@onready var _points_label: Label = $Main/Header/PointsLabel
@onready var _tier_hp_label: Label = $Main/Header/TierHPLabel
@onready var _budget_label: Label = $Main/BudgetLabel
@onready var _back_btn: Button = $Main/Footer/BackButton
@onready var _tab_container: TabContainer = $Main/TabContainer
@onready var _skills_panel: Control = $Main/TabContainer/Skills
@onready var _canvas: Control     = $Main/TabContainer/Skills/Canvas
@onready var _line_layer: Control = $Main/TabContainer/Skills/Canvas/LineLayer
@onready var _card_layer: Control = $Main/TabContainer/Skills/Canvas/CardLayer

var _node_buttons: Dictionary = {}
var _node_cards: Dictionary = {}
var _node_level_labels: Dictionary = {}
var _node_pip_labels: Dictionary = {}
var _node_by_id_map: Dictionary = {}
var _heart_label: Label
var _expanded_vertex: String = ""

var _zoom: float = 1.0
var _pan_offset: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO

const DOM_VERTEX := Vector2(450, 60)
const ING_VERTEX := Vector2(100, 620)
const NEG_VERTEX := Vector2(800, 620)
const CENTROID   := Vector2(450, 433)
const CARD_SIZE  := Vector2(108, 56)

const _ALWAYS_VISIBLE: Dictionary = {
	"dom_core": true, "ing_core": true, "neg_core": true,
	"dom_stamina": true, "neg_stance": true, "ing_resolve": true
}
const _DOMINION_SUBTREE: Dictionary = {
	"dom_wounds": true, "dom_martial_arts": true, "dom_melee": true,
	"dom_ranged": true, "dom_dual_wield": true, "dom_titans_grip": true,
	"dom_disarm": true, "dom_brutal": true, "dom_meat_grinder": true,
	"dom_earthshatter": true, "dom_stamina": true
}
const _INGENUITY_SUBTREE: Dictionary = {
	"minor_studies": true, "spellcasting": true,
	"fire_magic_1": true, "fire_magic_2": true,
	"fire_magic_3": true, "fire_magic_4": true,
	"arcane_1": true, "arcane_2": true, "arcane_3": true
}
const _NODE_POSITIONS: Dictionary = {
	# Always-visible triangle vertices + centre
	"dom_core":         Vector2(396,  70),
	"ing_core":         Vector2( 46, 590),
	"neg_core":         Vector2(746, 590),
	# Default guard training — always visible, adjacent to their core vertices
	"dom_stamina":      Vector2(280,  70),
	"neg_stance":       Vector2(860, 590),
	"ing_resolve":      Vector2(-70, 590),
	# DOM subtree — expands UPWARD (negative Y) from dom_core
	"dom_wounds":       Vector2(220,  -50),
	"dom_martial_arts": Vector2(580,  -50),
	"dom_meat_grinder": Vector2( 70, -170),
	"dom_melee":        Vector2(460, -170),
	"dom_ranged":       Vector2(710, -170),
	"dom_dual_wield":   Vector2(310, -300),
	"dom_disarm":       Vector2(460, -300),
	"dom_titans_grip":  Vector2(610, -300),
	"dom_brutal":       Vector2(610, -430),
	"dom_earthshatter": Vector2(610, -560),
	# ING subtree — expands LEFTWARD (negative X) from ing_core, two-row grid
	"minor_studies":    Vector2(-110, 620),
	"fire_magic_1":     Vector2(-260, 590),
	"spellcasting":     Vector2(-260, 670),
	"fire_magic_2":     Vector2(-420, 590),
	"arcane_1":         Vector2(-420, 670),
	"fire_magic_3":     Vector2(-580, 590),
	"arcane_2":         Vector2(-580, 670),
	"fire_magic_4":     Vector2(-740, 590),
	"arcane_3":         Vector2(-740, 670),
}

const _VERTEX_NAMES: Dictionary = {
	"dom_core": "dominion", "ing_core": "ingenuity", "neg_core": "negation"
}


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_tab_container.set_tab_title(1, "Background / Traits")
	_populate_canvas()
	_refresh()
	if ResourceLoader.exists(_DBG_PROGRESSION):
		add_child((load(_DBG_PROGRESSION) as PackedScene).instantiate())


func _populate_canvas() -> void:
	var traits_box: VBoxContainer = $Main/TabContainer/Traits/TraitsBox
	for node in PlayerProgression.ALL_NODES:
		var nd := node as NodeData
		_node_by_id_map[nd.node_id] = node
		if nd.category == "Flavor":
			traits_box.add_child(_make_card(nd))
		elif nd.node_id in _NODE_POSITIONS:
			var card := _make_card(nd)
			card.position = _NODE_POSITIONS[nd.node_id]
			_card_layer.add_child(card)

	_heart_label = Label.new()
	_heart_label.position = CENTROID - Vector2(54, 10)
	_heart_label.add_theme_font_size_override("font_size", 14)
	_card_layer.add_child(_heart_label)


func _make_card(node: NodeData) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	# tooltip_text removed — CustomTooltip handles this via right-click

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.text = node.display_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	header_row.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "L0/%d" % node.max_levels
	level_lbl.add_theme_font_size_override("font_size", 10)
	header_row.add_child(level_lbl)

	var pip_lbl := Label.new()
	pip_lbl.text = "○".repeat(node.max_levels)
	pip_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(pip_lbl)

	var btn := Button.new()
	btn.pressed.connect(_on_unlock.bind(node))
	vbox.add_child(btn)

	_node_buttons[node] = btn
	_node_cards[node] = card
	_node_level_labels[node] = level_lbl
	_node_pip_labels[node] = pip_lbl

	if node.node_id in _VERTEX_NAMES:
		card.gui_input.connect(_on_vertex_gui_input.bind(_VERTEX_NAMES[node.node_id]))

	TooltipManager.attach(card, node)
	TooltipManager.attach_delta(btn, node)

	return card


func _refresh() -> void:
	var pts := PlayerProgression.available_points
	var tier := PlayerProgression.get_tier()
	var combat_spent := PlayerProgression.tier_combat_spent
	var flavor_spent := PlayerProgression.tier_flavor_spent

	_points_label.text = "Points: %d" % pts
	_tier_hp_label.text = "Tier %d · HP %d" % [tier, _max_wounds(tier)]

	if tier >= 4:
		_budget_label.text = "Max Tier — Combat: %d/5 · Flavor: %d/2" % [combat_spent, flavor_spent]
	else:
		_budget_label.text = "Combat: %d/5 · Flavor: %d/2  (fill both to reach Tier %d)" % [
			combat_spent, flavor_spent, tier + 1
		]

	for node in _node_buttons:
		var nd := node as NodeData
		var btn: Button = _node_buttons[node]
		var card: PanelContainer = _node_cards[node]
		var level_lbl: Label = _node_level_labels[node]
		var pip_lbl: Label = _node_pip_labels[node]
		var lvl := PlayerProgression.get_level(nd)
		var max_lvl := nd.max_levels
		var at_max := lvl >= max_lvl
		var tier_locked := false
		if not at_max and nd.levels_data.size() > lvl:
			tier_locked = tier < (nd.levels_data[lvl] as NodeLevelData).required_tier

		level_lbl.text = "L%d/%d" % [lvl, max_lvl]
		pip_lbl.text = "●".repeat(lvl) + "○".repeat(max_lvl - lvl)

		if at_max:
			btn.text = "Max"
			btn.disabled = true
			card.modulate = Color.WHITE
		elif tier_locked:
			var req_tier: int = (nd.levels_data[lvl] as NodeLevelData).required_tier
			btn.text = "T%d" % req_tier
			btn.disabled = true
			card.modulate = Color(1, 1, 1, 0.4)
		elif PlayerProgression.can_upgrade(nd):
			var ld: NodeLevelData = nd.levels_data[lvl]
			btn.text = "+%d" % ld.cost
			btn.disabled = false
			card.modulate = Color.WHITE
		else:
			btn.text = "—"
			btn.disabled = true
			card.modulate = Color.WHITE

	_refresh_canvas()


func _refresh_canvas() -> void:
	for node in _node_cards:
		var nd := node as NodeData
		var nid := nd.node_id
		if nid not in _NODE_POSITIONS:
			continue
		_node_cards[node].visible = (
			nid in _ALWAYS_VISIBLE or
			(nid in _DOMINION_SUBTREE and _expanded_vertex == "dominion") or
			(nid in _INGENUITY_SUBTREE and _expanded_vertex == "ingenuity")
		)

	for child in _line_layer.get_children():
		child.queue_free()
	_draw_triangle_lines()
	_draw_connection_lines()

	var tier := PlayerProgression.get_tier()
	_heart_label.text = "T%d · HP%d" % [tier, _max_wounds(tier)]


func _draw_triangle_lines() -> void:
	var dc := CARD_SIZE * 0.5
	var color := Color(0.4, 0.35, 0.6, 0.4)
	_add_line(DOM_VERTEX + dc, ING_VERTEX + dc, color)
	_add_line(ING_VERTEX + dc, NEG_VERTEX + dc, color)
	_add_line(NEG_VERTEX + dc, DOM_VERTEX + dc, color)

	_add_vertex_label("DOMINION",  DOM_VERTEX + Vector2(-10, -20))
	_add_vertex_label("INGENUITY", ING_VERTEX + Vector2(-20, 60))
	_add_vertex_label("NEGATION",  NEG_VERTEX + Vector2(-20, 60))


func _draw_connection_lines() -> void:
	for node in _node_cards:
		var nd := node as NodeData
		if nd.category == "Flavor":
			continue
		if nd.node_id not in _NODE_POSITIONS:
			continue
		if not _node_cards[node].visible:
			continue
		if nd.levels_data.is_empty():
			continue
		var _prereq_list: Array = []
		for _ld in nd.levels_data:
			_prereq_list = (_ld as NodeLevelData).prerequisites
			if not _prereq_list.is_empty():
				break
		for prereq in _prereq_list:
			var pid: String = str(prereq.get("node_id", ""))
			if pid not in _NODE_POSITIONS:
				continue
			var parent_nd: NodeData = _node_by_id_map.get(pid)
			if parent_nd == null:
				continue
			var p_card: PanelContainer = _node_cards.get(parent_nd)
			if p_card == null or not p_card.visible:
				continue
			var from: Vector2 = _NODE_POSITIONS[pid] + CARD_SIZE * 0.5
			var to: Vector2   = _NODE_POSITIONS[nd.node_id] + CARD_SIZE * 0.5
			var req_lvl: int = int(prereq.get("required_level", 1))
			var met := PlayerProgression.get_node_level_by_id(pid) >= req_lvl
			_add_line(from, to, Color(0.85, 0.70, 0.20) if met else Color(0.30, 0.30, 0.30))


func _add_line(from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.default_color = color
	line.width = 2.0
	_line_layer.add_child(line)


func _add_vertex_label(text_str: String, pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text_str
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 12)
	_line_layer.add_child(lbl)


func _on_vertex_gui_input(event: InputEvent, vertex: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_vertex_toggle(vertex)


func _on_vertex_toggle(vertex: String) -> void:
	_expanded_vertex = "" if _expanded_vertex == vertex else vertex
	_refresh()
	_center_after_toggle()


func _center_after_toggle() -> void:
	var ids: Array = []
	match _expanded_vertex:
		"dominion":
			ids = ["dom_core"] + _DOMINION_SUBTREE.keys()
		"ingenuity":
			ids = ["ing_core"] + _INGENUITY_SUBTREE.keys()
		_:
			ids = _ALWAYS_VISIBLE.keys()
	_center_on_nodes(ids)


func _center_on_nodes(node_ids: Array) -> void:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for nid in node_ids:
		if nid not in _NODE_POSITIONS:
			continue
		var p: Vector2 = _NODE_POSITIONS[nid]
		min_p = min_p.min(p)
		max_p = max_p.max(p + CARD_SIZE)
	if min_p.x == INF:
		return
	min_p -= Vector2(30, 30)
	max_p += Vector2(30, 30)
	var panel_size := _skills_panel.size
	var content_size := max_p - min_p
	_zoom = clamp(minf(panel_size.x / content_size.x, panel_size.y / content_size.y), 0.25, 1.5)
	_canvas.scale = Vector2(_zoom, _zoom)
	var content_center := (min_p + max_p) * 0.5 * _zoom
	_pan_offset = panel_size * 0.5 - content_center
	_canvas.position = _pan_offset


func _max_wounds(tier: int) -> int:
	var base := _PLAYER_DATA.max_wounds
	var equip := _PLAYER_DATA.equipped_weapon.max_wounds_bonus if _PLAYER_DATA.equipped_weapon else 0
	return base + equip + (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)


func _input(event: InputEvent) -> void:
	if _tab_container.current_tab != 0:
		return
	if not _skills_panel.get_global_rect().has_point(get_global_mouse_position()):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_do_zoom(1.15)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_do_zoom(1.0 / 1.15)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mb.pressed
			_pan_last_mouse = get_global_mouse_position()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_panning:
		var delta := get_global_mouse_position() - _pan_last_mouse
		_pan_last_mouse = get_global_mouse_position()
		_pan_offset += delta
		_canvas.position = _pan_offset
		get_viewport().set_input_as_handled()


func _do_zoom(factor: float) -> void:
	var old_zoom := _zoom
	_zoom = clamp(_zoom * factor, 0.25, 3.0)
	var mouse_in_panel := get_global_mouse_position() - _skills_panel.global_position
	_pan_offset = mouse_in_panel - (mouse_in_panel - _pan_offset) * (_zoom / old_zoom)
	_canvas.position = _pan_offset
	_canvas.scale = Vector2(_zoom, _zoom)


func _on_unlock(node: NodeData) -> void:
	PlayerProgression.upgrade(node)
	_refresh()


func _on_back_pressed() -> void:
	if DungeonManager.run_active:
		get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
