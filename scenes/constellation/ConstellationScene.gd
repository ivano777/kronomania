extends Control

const _PLAYER_DATA: CombatantData = preload("res://resources/data/player_default.tres")
const _DBG_PROGRESSION := "res://scenes/debug/DebugProgressionControl.tscn"

@onready var _points_label: Label = $Main/Header/PointsLabel
@onready var _budget_label: Label = $Main/BudgetLabel
@onready var _back_btn: Button = $Main/Footer/BackButton
@onready var _tab_container: TabContainer = $Main/TabContainer
@onready var _skills_panel: Control = $Main/TabContainer/Skills
@onready var _canvas: Control     = $Main/TabContainer/Skills/Canvas
@onready var _line_layer: Control = $Main/TabContainer/Skills/Canvas/LineLayer
@onready var _card_layer: Control = $Main/TabContainer/Skills/Canvas/CardLayer

var _node_cards: Dictionary = {}
var _node_pips: Dictionary = {}
var _node_styles: Dictionary = {}
var _node_by_id_map: Dictionary = {}
var _core_medallion: CoreMedallion
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
	"dom_martial_arts": true, "dom_melee": true,
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
	# Child of the scene ROOT, not the Skills tab: flavor cards live in the
	# Traits tab, and a panel inside Skills is hidden by the TabContainer there
	# (= "can't buy backgrounds"). Root is a plain Control, so the panel's
	# right-column anchors still apply and it overlays both tabs.
	add_child(_detail_panel)
	_detail_panel.bought.connect(_on_detail_bought)
	_populate_canvas()
	_refresh()
	if ResourceLoader.exists(_DBG_PROGRESSION):
		# Left-column overlay mirroring NodeDetailPanel's right one (z=60 in its
		# .tscn, above CardLayer z=1 and the detail panel z=50). Must be added
		# LAST at the scene root: input picking ignores z_index and follows tree
		# order, so tree-last + highest z keeps what's drawn on top and what
		# gets clicked consistent. Collapsed, only the bottom-left toggle is
		# solid (root mouse_filter IGNORE) so canvas clicks pass through.
		add_child((load(_DBG_PROGRESSION) as PackedScene).instantiate())
	# Initial framing: zoom-to-fit the always-visible triangle so all three
	# branch entry points are on screen. Container layout hasn't run during
	# _ready (panel size is still 0), so wait one frame first.
	await get_tree().process_frame
	_center_after_toggle()


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

	# Core gem medallion at the triangle centroid — Tier / HP / points readout.
	# CENTROID averages the vertex top-left corners; the graph draws from card
	# centres, so shift by half a card to sit at the true visual centroid.
	_core_medallion = CoreMedallion.new()
	_core_medallion.custom_minimum_size = Vector2(84, 92)
	_core_medallion.size = Vector2(84, 92)
	var medallion_center := CENTROID + CARD_SIZE * 0.5
	_core_medallion.position = medallion_center - _core_medallion.size * 0.5
	_card_layer.add_child(_core_medallion)


func _make_card(node: NodeData) -> PanelContainer:
	var branch_color: Color = _branch_color(node)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	# Branch-tinted frame: flat dark fill + coloured border (the baked 9-slice can't recolour).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.15, 0.9)
	sb.border_color = branch_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", sb)
	_node_styles[node] = sb

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
		var gate_locked := false
		if not at_max and nd.levels_data.size() > lvl:
			gate_locked = not PlayerProgression.spend_gate_met(nd.levels_data[lvl] as NodeLevelData)

		var branch_color: Color = _branch_color(nd)
		for i in pips.size():
			(pips[i] as ColorRect).color = branch_color if i < lvl else PIP_EMPTY

		# Frame state: gold glow = affordable now, branch glow = owned, plain = neither.
		var sb: StyleBoxFlat = _node_styles[node]
		var buyable := PlayerProgression.can_upgrade(nd)
		if buyable:
			var gold: Color = BRANCH_COLORS["core"]
			sb.border_color = gold
			sb.set_border_width_all(2)
			sb.shadow_color = Color(gold.r, gold.g, gold.b, 0.55)
			sb.shadow_size = 4
		elif lvl > 0:
			sb.border_color = branch_color
			sb.set_border_width_all(2)
			sb.shadow_color = Color(branch_color.r, branch_color.g, branch_color.b, 0.45)
			sb.shadow_size = 3
		else:
			sb.border_color = branch_color
			sb.set_border_width_all(1)
			sb.shadow_size = 0

		# Dim only out-of-reach (gate-locked) nodes; cost/affordability lives in the
		# panel. A buyable card is never dimmed (debug Free Buy ignores spend gates).
		card.modulate = Color(1, 1, 1, 0.4) if (gate_locked and not buyable) else Color.WHITE

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
	_core_medallion.set_state(tier, _max_wounds(tier), PlayerProgression.available_points)


func _draw_triangle_lines() -> void:
	var dc := CARD_SIZE * 0.5
	var d := DOM_VERTEX + dc
	var i := ING_VERTEX + dc
	var n := NEG_VERTEX + dc
	var color := Color(0.5, 0.45, 0.7, 0.55)
	_add_line(d, i, color, 2.0, true)
	_add_line(i, n, color, 2.0, true)
	_add_line(n, d, color, 2.0, true)

	# Sparkles at the edge midpoints decorate the otherwise-plain guide lines.
	var glint := Color(0.85, 0.70, 0.20, 0.85)
	_add_star_glint((d + i) * 0.5, glint, 5.0)
	_add_star_glint((i + n) * 0.5, glint, 5.0)
	_add_star_glint((n + d) * 0.5, glint, 5.0)

	# Clear of the 48px-tall core tokens: DOMINION above, INGENUITY/NEGATION below.
	_add_vertex_label("♦ DOMINION ♦",  DOM_VERTEX + Vector2(-30, -18))
	_add_vertex_label("♦ INGENUITY ♦", ING_VERTEX + Vector2(-30, 52))
	_add_vertex_label("♦ NEGATION ♦",  NEG_VERTEX + Vector2(-30, 52))


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
			if met:
				_add_line(from, to, _branch_color(nd), 2.0, true)
			else:
				_add_line(from, to, Color(0.30, 0.30, 0.30), 1.0, false)


func _add_line(from: Vector2, to: Vector2, color: Color, width: float = 1.0, glow: bool = false) -> void:
	if glow:
		var halo := Line2D.new()
		halo.add_point(from)
		halo.add_point(to)
		halo.default_color = Color(color.r, color.g, color.b, 0.18)
		halo.width = width + 3.0
		halo.antialiased = true
		halo.begin_cap_mode = Line2D.LINE_CAP_ROUND
		halo.end_cap_mode = Line2D.LINE_CAP_ROUND
		_line_layer.add_child(halo)
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.default_color = color
	line.width = width
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line_layer.add_child(line)


## A small 4-point sparkle (bright cross + faint diagonal X), built from Line2Ds.
func _add_star_glint(pos: Vector2, color: Color, sz: float) -> void:
	_add_line(pos - Vector2(sz, 0), pos + Vector2(sz, 0), color, 1.0, false)
	_add_line(pos - Vector2(0, sz), pos + Vector2(0, sz), color, 1.0, false)
	var diag := sz * 0.6
	var faint := Color(color.r, color.g, color.b, 0.4)
	_add_line(pos - Vector2(diag, diag), pos + Vector2(diag, diag), faint, 1.0, false)
	_add_line(pos - Vector2(diag, -diag), pos + Vector2(diag, -diag), faint, 1.0, false)


func _add_vertex_label(text_str: String, pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text_str
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70))  # parchment
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
	# 30px margin keeps the ♦ BRANCH ♦ vertex labels (offset up to -18/+52 from
	# their vertex) inside the fitted view.
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
			# _input runs BEFORE gui_input, so this fires for every left click on
			# the canvas — cards included. Close the panel but do NOT consume the
			# event: a click on a node card must still reach that card's gui_input
			# so the panel reopens for the new node in the same click.
			if _detail_panel.is_open():
				_detail_panel.close()
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
		get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/campfire/CampfireScene.tscn"))
	else:
		get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/main_menu/MainMenuScene.tscn"))
