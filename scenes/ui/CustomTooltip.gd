extends PanelContainer

var _title: Label
var _category: Label
var _stats: VBoxContainer
var _desc_sep: HSeparator
var _desc: RichTextLabel


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(140, 0)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 16)
	_title.mouse_filter = MOUSE_FILTER_IGNORE
	header_row.add_child(_title)

	_category = Label.new()
	_category.add_theme_font_size_override("font_size", 16)
	_category.modulate = Color(1, 1, 1, 0.6)
	_category.mouse_filter = MOUSE_FILTER_IGNORE
	header_row.add_child(_category)

	vbox.add_child(_make_separator())

	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 2)
	_stats.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(_stats)

	_desc_sep = _make_separator()
	vbox.add_child(_desc_sep)

	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.scroll_active = false
	_desc.add_theme_font_size_override("font_size", 16)
	_desc.mouse_filter = MOUSE_FILTER_IGNORE
	_desc.custom_minimum_size = Vector2(128, 0)
	vbox.add_child(_desc)


# ── Public populate API ────────────────────────────────────────────────────────

func populate(resource: Resource) -> void:
	_clear_stats()
	if resource is EquipmentData:
		_populate_equipment(resource as EquipmentData)
	elif resource is NodeData:
		_populate_node_full(resource as NodeData)
	elif resource is CombatantData:
		_populate_enemy(resource as CombatantData)


func populate_delta(node: NodeData) -> void:
	_clear_stats()
	_title.text = node.display_name + "  ›  Upgrade"
	_category.text = node.category

	var current_level: int = PlayerProgression.get_level(node)

	if current_level >= node.max_levels:
		_add_row("", "Already at maximum level", true)
		_desc.text = ""
		_desc_sep.hide()
		_desc.hide()
		return

	# Current block — de-emphasized
	if current_level == 0:
		_add_row("Current", "Not yet purchased", true)
	else:
		var cur_ld: NodeLevelData = node.levels_data[current_level - 1] as NodeLevelData
		_add_row("L%d" % current_level, cur_ld.level_effect_description, true)

	# Gold divider
	var divider := Label.new()
	divider.text = "▼  Next Level"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	divider.add_theme_font_size_override("font_size", 16)
	divider.mouse_filter = MOUSE_FILTER_IGNORE
	_stats.add_child(divider)

	# Next block — emphasized
	var next_ld: NodeLevelData = node.levels_data[current_level] as NodeLevelData
	_add_row("Cost", "%d slot(s)" % next_ld.cost)
	if next_ld.required_tier > 1:
		_add_row("Tier required", "Tier %d+" % next_ld.required_tier)
	if not next_ld.prerequisites.is_empty():
		var parts: Array[String] = []
		for prereq in next_ld.prerequisites:
			var pid: String = str(prereq.get("node_id", ""))
			var req_lvl: int = int(prereq.get("required_level", 1))
			parts.append("%s L%d" % [_node_display_name(pid), req_lvl])
		_add_row("Requires", ",  ".join(parts))
	if not next_ld.level_effect_description.is_empty():
		_add_row("Effect", next_ld.level_effect_description)
	if not next_ld.spells.is_empty():
		var names: Array[String] = []
		for s in next_ld.spells:
			names.append((s as SpellData).spell_name)
		_add_row("Spells", ",  ".join(names))

	_desc.text = ""
	_desc_sep.hide()
	_desc.hide()


# ── Private formatters ─────────────────────────────────────────────────────────

func _populate_equipment(eq: EquipmentData) -> void:
	_title.text = eq.item_name
	_category.text = "  ·  ".join(eq.tags) if not eq.tags.is_empty() else "Equipment"

	_add_row("Hands", str(eq.get_hands_required()))
	_add_row("Potency", str(eq.potency))

	for raw_mod in eq.action_modifiers:
		var mod := raw_mod as ActionModifier
		match mod.action_key:
			"strike":
				if mod.tier_cap > 0:
					_add_row("Strike  Tier cap", str(mod.tier_cap))
				if mod.flat_bonus != 0:
					_add_row("Strike  Flat", "%+d" % mod.flat_bonus)
				if mod.pool_bonus != 0:
					_add_row("Strike  Pool", "%+d" % mod.pool_bonus)
				if not mod.target_pool.is_empty():
					_add_row("Strike  Target", mod.target_pool.capitalize())
			"defend":
				if mod.flat_bonus != 0:
					_add_row("Defend  Flat", "%+d" % mod.flat_bonus)
			"cast":
				if mod.tier_cap > 0:
					_add_row("Cast  Tier cap", str(mod.tier_cap))
				if mod.pool_bonus != 0:
					_add_row("Cast  Pool", "%+d" % mod.pool_bonus)
				if mod.keep_bonus != 0:
					_add_row("Cast  Keep", "%+d" % mod.keep_bonus)
				if mod.flat_bonus != 0:
					_add_row("Cast  Flat", "%+d" % mod.flat_bonus)

	_desc.text = ""
	_desc_sep.hide()
	_desc.hide()


func _populate_node_full(nd: NodeData) -> void:
	_title.text = nd.display_name
	_category.text = nd.category

	var current_level: int = PlayerProgression.get_level(nd)
	_add_row("Level", "%d / %d" % [current_level, nd.max_levels])

	if current_level == 0:
		_add_row("", "Not yet purchased", true)
	else:
		var ld: NodeLevelData = nd.levels_data[current_level - 1] as NodeLevelData
		_add_row("Cost paid", "%d slot(s)" % ld.cost, true)
		if not ld.level_effect_description.is_empty():
			_add_row("Effect", ld.level_effect_description)
		if not ld.spells.is_empty():
			var names: Array[String] = []
			for s in ld.spells:
				names.append((s as SpellData).spell_name)
			_add_row("Spells", ",  ".join(names))

	if not nd.base_description.is_empty():
		_desc.text = nd.base_description
		_desc_sep.show()
		_desc.show()
	else:
		_desc.text = ""
		_desc_sep.hide()
		_desc.hide()


func _populate_enemy(cd: CombatantData) -> void:
	_title.text = cd.combatant_name
	_category.text = "Enemy"

	_add_row("Tier", str(cd.tier))
	_add_row("Dominion", "d%d" % cd.dominion_size)
	_add_row("Negation", "d%d" % cd.negation_size)
	_add_row("Ingenuity", "d%d" % cd.ingenuity_size)
	_add_row("Keep grade", str(cd.keep_grade))
	_add_row("VT", str(cd.velocity_threshold))
	_add_row("Max Wounds", str(cd.max_wounds))
	_add_row("Weapon", cd.equipped_weapon.item_name if cd.equipped_weapon else "None")

	_desc.text = ""
	_desc_sep.hide()
	_desc.hide()


# ── Helpers ────────────────────────────────────────────────────────────────────

func _add_row(label: String, value: String, dimmed: bool = false) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 16)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(val)

	if dimmed:
		row.modulate = Color(1, 1, 1, 0.5)

	_stats.add_child(row)


func _clear_stats() -> void:
	for child in _stats.get_children():
		child.free()
	_desc_sep.show()
	_desc.show()


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.mouse_filter = MOUSE_FILTER_IGNORE
	return sep


func _node_display_name(node_id: String) -> String:
	for node in PlayerProgression.ALL_NODES:
		var nd := node as NodeData
		if nd.node_id == node_id:
			return nd.display_name
	return node_id
