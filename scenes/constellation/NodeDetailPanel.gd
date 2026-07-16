# Dismissable overlay panel for the constellation. Shows the FULL detail of one
# node — every level's cost, tier gate, prerequisites, effect, granted spells,
# charges, and roll/outcome bonuses — with a Buy button. Closed via its own ×,
# Esc, or a click on empty canvas space (both handled by ConstellationScene).
class_name NodeDetailPanel
extends PanelContainer

signal bought(node: NodeData)

const _DIM := Color(1, 1, 1, 0.5)
const _GOLD := Color(1.0, 0.85, 0.3)

var _node: NodeData
var _branch: String = ""
var _accent: Color = Color.WHITE

var _title: Label
var _category: Label
var _body: VBoxContainer
var _buy_btn: Button


func _ready() -> void:
	# Draw above the node cards (CardLayer has z_index 1, which otherwise wins
	# over tree order and paints the tokens on top of this overlay).
	z_index = 50
	# Pin a ~190px column to the right edge of the parent. Parent must NOT be
	# inside one TabContainer tab — flavor cards open this panel from the
	# Traits tab, so ConstellationScene parents it to the scene root.
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	anchor_left = 1.0
	offset_left = -190.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Header: title + branch category + close button.
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	_category = Label.new()
	_category.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_category)

	vbox.add_child(HSeparator.new())

	# Scrollable level ladder.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Transparent to the mouse so wheel events fall through to the ScrollContainer.
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_body)

	vbox.add_child(HSeparator.new())

	_buy_btn = Button.new()
	_buy_btn.pressed.connect(_on_buy)
	vbox.add_child(_buy_btn)

	hide()


# ── Public API ───────────────────────────────────────────────────────────────

func open(node: NodeData, branch: String, accent: Color) -> void:
	_node = node
	_branch = branch
	_accent = accent
	_populate()
	show()


func close() -> void:
	_node = null
	hide()


func is_open() -> bool:
	return visible and _node != null


# ── Rendering ────────────────────────────────────────────────────────────────

func _populate() -> void:
	var current_level: int = PlayerProgression.get_level(_node)
	_title.text = _node.display_name
	_category.text = _branch.capitalize()
	_category.add_theme_color_override("font_color", _accent)

	for child in _body.get_children():
		child.queue_free()

	_add_row("Level", "%d / %d" % [current_level, _node.max_levels])
	if not _node.base_description.is_empty():
		_add_note(_node.base_description)

	for i in _node.levels_data.size():
		var ld := _node.levels_data[i] as NodeLevelData
		var n := i + 1
		var owned := n <= current_level
		var is_next := n == current_level + 1

		if is_next:
			_add_divider("▼  Next Level")
		else:
			_add_divider("— L%d —" % n)

		var cost_bits: Array[String] = ["Cost %d" % ld.cost]
		for b in ld.branch_spend:
			cost_bits.append("%s %d+" % [str(b).capitalize(), int(ld.branch_spend[b])])
		if ld.uses_per_combat > 0:
			cost_bits.append("%d/combat" % ld.uses_per_combat)
		_add_row("L%d" % n, "  ·  ".join(cost_bits), owned)

		if not ld.prerequisites.is_empty():
			var parts: Array[String] = []
			for prereq in ld.prerequisites:
				var pid: String = str(prereq.get("node_id", ""))
				var rl: int = int(prereq.get("required_level", 1))
				parts.append("%s L%d" % [_display_name(pid), rl])
			_add_row("Requires", ",  ".join(parts), owned)

		if not ld.level_effect_description.is_empty():
			_add_note(ld.level_effect_description, owned)

		if not ld.spells.is_empty():
			var names: Array[String] = []
			for s in ld.spells:
				names.append((s as SpellData).spell_name)
			_add_row("Grants", ",  ".join(names), owned)

		for raw_be in ld.bonus_effects:
			_add_note("• " + _format_bonus(raw_be as SpellBonusEffect), owned)
		for raw_oe in ld.outcome_effects:
			_add_note("• " + _format_outcome(raw_oe as SpellOutcomeEffect), owned)

	_refresh_buy_button(current_level)


func _refresh_buy_button(current_level: int) -> void:
	if current_level >= _node.max_levels:
		_buy_btn.text = "Max"
		_buy_btn.disabled = true
		return
	var ld := _node.levels_data[current_level] as NodeLevelData
	# can_upgrade first: it is the single source of truth (incl. debug Free Buy,
	# which ignores branch-spend gates and point cost); gate text is just the
	# failure label.
	if PlayerProgression.can_upgrade(_node):
		var free := PlayerProgression.debug_free_buy and DebugManager.enabled
		_buy_btn.text = "Buy (free)" if free else "Buy  +%d" % ld.cost
		_buy_btn.disabled = false
	elif not PlayerProgression.spend_gate_met(ld):
		_buy_btn.text = _unmet_gate_label(ld)
		_buy_btn.disabled = true
	else:
		_buy_btn.text = "Locked"
		_buy_btn.disabled = true


## First unmet branch-spend requirement as button text, e.g. "Spend 3 in Dominion".
func _unmet_gate_label(ld: NodeLevelData) -> String:
	for b in ld.branch_spend:
		var need := int(ld.branch_spend[b])
		if PlayerProgression.get_branch_spent(str(b)) < need:
			return "Spend %d in %s" % [need, str(b).capitalize()]
	return "Locked"


func _on_buy() -> void:
	if _node == null:
		return
	PlayerProgression.upgrade(_node)
	_populate()
	bought.emit(_node)


# ── Row/note helpers (mirror CustomTooltip idiom) ────────────────────────────

func _add_row(label: String, value: String, dimmed: bool = false) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 16)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val)
	if dimmed:
		row.modulate = _DIM
	_body.add_child(row)


func _add_note(text: String, dimmed: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dimmed:
		lbl.modulate = _DIM
	_body.add_child(lbl)


func _add_divider(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", _GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(lbl)


func _display_name(node_id: String) -> String:
	for node in PlayerProgression.ALL_NODES:
		var nd := node as NodeData
		if nd.node_id == node_id:
			return nd.display_name
	return node_id


func _format_bonus(be: SpellBonusEffect) -> String:
	var who := "\"%s\"" % be.spell_id if not be.spell_id.is_empty() else "%s casts" % be.tag
	return "%s: %s +%d" % [who, be.bonus_type.capitalize(), be.value]


func _format_outcome(oe: SpellOutcomeEffect) -> String:
	var verb := oe.effect_type.replace("_", " ")
	var txt := "%s: %s %d (%s %s)" % [
		oe.trigger.replace("_", " "), verb, oe.value, oe.target, oe.target_pool
	]
	if not oe.condition.is_empty():
		txt += " [%s]" % oe.condition.replace("_", " ")
	return txt
