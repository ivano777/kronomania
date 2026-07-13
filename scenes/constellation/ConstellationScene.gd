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

var _node_cards: Dictionary = {}
var _node_pips: Dictionary = {}
var _node_by_id_map: Dictionary = {}
var _heart_label: Label
var _expanded_vertex: String = ""
var _detail_panel: NodeDetailPanel

var _zoom: float = 1.0
var _pan_offset: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO

const DOM_VERTEX := Vector2(210, 35)
const ING_VERTEX := Vector2(23, 295)
const NEG_VERTEX := Vector2(373, 295)
const CENTROID   := Vector2(202, 208)
const CARD_SIZE  := Vector2(44, 48)
const ICON_PX    := 32
const PIP_PX     := 5
const PIP_EMPTY  := Color(0.25, 0.25, 0.25)

# Per-branch accent colours (dark-fantasy palette, read on the dark backdrop).
const BRANCH_COLORS := {
	"dominion":  Color(0.80, 0.25, 0.22),  # crimson
	"negation":  Color(0.35, 0.55, 0.80),  # steel-blue
	"ingenuity": Color(0.60, 0.40, 0.85),  # arcane-purple
	"core":      Color(0.85, 0.70, 0.20),  # gold
	"flavor":    Color(0.85, 0.80, 0.70),  # parchment
}
# Ability/discipline nodes that sit under the Ingenuity vertex but carry no `ing_` prefix.
const _DISCIPLINE_IDS := {
	"minor_studies": true, "spellcasting": true, "lucidity": true,
	"mind_detonation": true, "hex_mastery": true, "echoing_mind": true,
	"chrono_tinkering": true,
}

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
	"minor_studies": true, "spellcasting": true, "lucidity": true,
	"mind_detonation": true, "hex_mastery": true,
	"echoing_mind": true, "chrono_tinkering": true
}
const _NODE_POSITIONS: Dictionary = {
	# Uniform grid: STEP_X = 90 (card 70 + 20 gap), STEP_Y = 60 (card 32 + 28 gap)
	# Always-visible triangle vertices + centre
	"dom_core":         Vector2(210,  35),
	"ing_core":         Vector2( 23, 295),
	"neg_core":         Vector2(373, 295),
	# Default guard training — always visible, adjacent to their core vertices
	"dom_stamina":      Vector2(120,  35),
	"neg_stance":       Vector2(463, 295),
	"ing_resolve":      Vector2(-67, 295),
	# DOM subtree — expands UPWARD (negative Y) from dom_core
	"dom_wounds":       Vector2(120,  -25),
	"dom_martial_arts": Vector2(300,  -25),
	"dom_meat_grinder": Vector2( 30,  -85),
	"dom_melee":        Vector2(210,  -85),
	"dom_ranged":       Vector2(390,  -85),
	"dom_dual_wield":   Vector2(120, -145),
	"dom_disarm":       Vector2(210, -145),
	"dom_titans_grip":  Vector2(300, -145),
	"dom_brutal":       Vector2(300, -205),
	"dom_earthshatter": Vector2(300, -265),
	# ING subtree — expands LEFTWARD (negative X) from ing_core
	"minor_studies":    Vector2(-157, 295),
	"spellcasting":     Vector2(-247, 295),
	"lucidity":         Vector2(-157, 235),
	# Disciplines — column left of spellcasting, spread vertically
	"mind_detonation":  Vector2(-337, 175),
	"hex_mastery":      Vector2(-337, 235),
	"echoing_mind":     Vector2(-337, 295),
	"chrono_tinkering": Vector2(-337, 355),
}

const _VERTEX_NAMES: Dictionary = {
	"dom_core": "dominion", "ing_core": "ingenuity", "neg_core": "negation"
}


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_tab_container.set_tab_title(1, "Background / Traits")
	_detail_panel = NodeDetailPanel.new()
	_skills_panel.add_child(_detail_panel)
	_detail_panel.bought.connect(_on_detail_bought)
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
	_heart_label.position = CENTROID - Vector2(27, 5)
	_heart_label.add_theme_font_size_override("font_size", 16)
	_card_layer.add_child(_heart_label)


func _make_card(node: NodeData) -> PanelContainer:
	var branch_color: Color = _branch_color(node)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	# Branch-tinted frame: flat dark fill + coloured border (the baked 9-slice can't recolour).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.15, 0.9)
	sb.border_color = branch_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Icon (or 2-letter initials fallback when no art exists for this node).
	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)
	var tex: Texture2D = SpriteRegistry.get_icon("nodes", node.node_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(tr)
	else:
		var init_lbl := Label.new()
		init_lbl.text = _node_initials(node.display_name)
		init_lbl.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		init_lbl.add_theme_font_size_override("font_size", 16)
		init_lbl.add_theme_color_override("font_color", branch_color)
		init_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		init_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		init_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(init_lbl)

	# Level pips — a strip of small squares, filled up to the current level in _refresh().
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 1)
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(pip_row)
	var pips: Array = []
	for _i in node.max_levels:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(PIP_PX, PIP_PX)
		pip.color = PIP_EMPTY
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
		pips.append(pip)

	_node_cards[node] = card
	_node_pips[node] = pips

	# Left-click opens the detail panel; core vertices ALSO toggle their branch.
	card.gui_input.connect(_on_card_clicked.bind(node))

	return card


## Resolve a node to its constellation branch. node_id is authoritative — the
## `category` field is inconsistent in data (lowercase "ingenuity", default "Training").
func _branch_of(node: NodeData) -> String:
	var id := node.node_id
	if id == "dom_core" or id == "neg_core" or id == "ing_core":
		return "core"
	if id.begins_with("dom_"):
		return "dominion"
	if id.begins_with("neg_"):
		return "negation"
	if id.begins_with("ing_"):
		return "ingenuity"
	if id in _DISCIPLINE_IDS:
		return "ingenuity"
	if node.category == "Flavor":
		return "flavor"
	return "ingenuity"


func _branch_color(node: NodeData) -> Color:
	return BRANCH_COLORS[_branch_of(node)]


## Two-letter fallback shown when a node has no icon (initials of the first two words).
func _node_initials(display_name: String) -> String:
	var words := display_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return display_name.substr(0, 2).to_upper()


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

	for node in _node_cards:
		var nd := node as NodeData
		var card: PanelContainer = _node_cards[node]
		var pips: Array = _node_pips[node]
		var lvl := PlayerProgression.get_level(nd)
		var max_lvl := nd.max_levels
		var at_max := lvl >= max_lvl
		var tier_locked := false
		if not at_max and nd.levels_data.size() > lvl:
			tier_locked = tier < (nd.levels_data[lvl] as NodeLevelData).required_tier

		var branch_color: Color = _branch_color(nd)
		for i in pips.size():
			(pips[i] as ColorRect).color = branch_color if i < lvl else PIP_EMPTY

		# Dim only out-of-reach (tier-locked) nodes; cost/affordability lives in the panel.
		card.modulate = Color(1, 1, 1, 0.4) if tier_locked else Color.WHITE

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

	# Clear of the 48px-tall core tokens: DOMINION above, INGENUITY/NEGATION below.
	_add_vertex_label("DOMINION",  DOM_VERTEX + Vector2(-14, -18))
	_add_vertex_label("INGENUITY", ING_VERTEX + Vector2(-14, 52))
	_add_vertex_label("NEGATION",  NEG_VERTEX + Vector2(-14, 52))


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
			_add_line(from, to, _branch_color(nd) if met else Color(0.30, 0.30, 0.30))


func _add_line(from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.default_color = color
	line.width = 1.0
	_line_layer.add_child(line)


func _add_vertex_label(text_str: String, pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text_str
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.z_index = 5  # above cards (z 1) so branch names are never hidden by tokens
	_line_layer.add_child(lbl)


func _on_card_clicked(event: InputEvent, node: NodeData) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_detail_panel.open(node, _branch_of(node), _branch_color(node))
			if node.node_id in _VERTEX_NAMES:
				_on_vertex_toggle(_VERTEX_NAMES[node.node_id])


func _on_detail_bought(_node: NodeData) -> void:
	_refresh()


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
	min_p -= Vector2(15, 15)
	max_p += Vector2(15, 15)
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
	# Esc closes the detail panel from anywhere on the screen.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE and _detail_panel.is_open():
		_detail_panel.close()
		get_viewport().set_input_as_handled()
		return
	# Cursor over the open panel → let its GUI own the event (wheel scrolls the
	# ladder, clicks hit its buttons) instead of canvas zoom/pan/close below.
	if _detail_panel.is_open() \
			and _detail_panel.get_global_rect().has_point(get_global_mouse_position()):
		return
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
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Reached _input only if no token/panel consumed it → a click on empty space.
			if _detail_panel.is_open():
				_detail_panel.close()
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


func _on_back_pressed() -> void:
	if DungeonManager.run_active:
		get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
