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
var _show_technical: bool = false
var _spell_gem_controls: Dictionary = {}
var _spell_popup: PanelContainer
var _popup_vbox: VBoxContainer
var _current_spell_popup: SpellData = null
var _spell_popup_gem: Control = null


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

	_build_spell_popup()

	hide()


# ── Public API ───────────────────────────────────────────────────────────────

func open(node: NodeData, branch: String, accent: Color) -> void:
	_node = node
	_branch = branch
	_accent = accent
	_populate()
	show()


func close() -> void:
	_hide_spell_popup()
	_node = null
	hide()


func is_open() -> bool:
	return visible and _node != null


# ── Rendering ────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible or _node == null:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_SHIFT or ke.keycode == KEY_SHIFT:
			var was_technical := _show_technical
			_show_technical = ke.pressed
			if was_technical != _show_technical:
				# _populate() hides the popup and frees the gems; keep the hovered
				# spell so the tooltip swaps content in place instead of vanishing.
				var hovered := _current_spell_popup
				_populate()
				if hovered != null:
					_current_spell_popup = hovered
					_update_spell_popup.call_deferred()


func _populate() -> void:
	_hide_spell_popup()
	_spell_gem_controls.clear()
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

		var divider_text: String
		var divider_color: Color
		if owned:
			divider_text = "✓ L%d (Owned)" % n
			divider_color = _GOLD
		elif is_next:
			divider_text = "▼ L%d (Next)" % n
			divider_color = Color(0.85, 0.70, 0.20, 0.7)  # Gold but dimmer
		else:
			divider_text = "◆ L%d (Future)" % n
			divider_color = Color(0.60, 0.50, 0.30, 0.5)  # Muted bronze

		_add_divider(divider_text, divider_color)

		if _show_technical:
			_add_technical_level(ld, owned)
		else:
			_add_normal_level(ld, owned)

	_refresh_buy_button(current_level)


func _add_normal_level(ld: NodeLevelData, owned: bool) -> void:
	var cost_bits: Array[String] = ["Cost %d" % ld.cost]
	for b in ld.branch_spend:
		cost_bits.append("%s %d+" % [str(b).capitalize(), int(ld.branch_spend[b])])
	if ld.uses_per_combat > 0:
		cost_bits.append("%d/combat" % ld.uses_per_combat)
	_add_row("Cost", "  ·  ".join(cost_bits), not owned)

	if not ld.prerequisites.is_empty():
		var parts: Array[String] = []
		for prereq in ld.prerequisites:
			var pid: String = str(prereq.get("node_id", ""))
			var rl: int = int(prereq.get("required_level", 1))
			parts.append("%s L%d" % [_display_name(pid), rl])
		_add_row("Requires", ",  ".join(parts), not owned)

	if not ld.level_effect_description.is_empty():
		_add_note(ld.level_effect_description, not owned)

	if not ld.spells.is_empty():
		_add_spell_row("Grants", ld.spells, not owned)

	for raw_be in ld.bonus_effects:
		_add_note("• " + _format_bonus(raw_be as SpellBonusEffect), not owned)
	for raw_oe in ld.outcome_effects:
		_add_note("• " + _format_outcome(raw_oe as SpellOutcomeEffect), not owned)


func _add_technical_level(ld: NodeLevelData, owned: bool) -> void:
	var tech_bits: Array[String] = []

	if not ld.level_effect_description.is_empty():
		tech_bits.append(ld.level_effect_description)

	for raw_be in ld.bonus_effects:
		tech_bits.append("• " + _format_bonus(raw_be as SpellBonusEffect))

	for raw_oe in ld.outcome_effects:
		tech_bits.append("• " + _format_outcome(raw_oe as SpellOutcomeEffect))

	if tech_bits.is_empty():
		_add_note("[No effect]", not owned)
	else:
		for bit in tech_bits:
			_add_note(bit, not owned)

	if not ld.spells.is_empty():
		_add_spell_row("Grants", ld.spells, not owned)


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


func _add_divider(text: String, color: Color = _GOLD) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(lbl)


func _add_spell_row(label: String, spells: Array[SpellData], dimmed: bool = false) -> void:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = label
	header.add_theme_font_size_override("font_size", 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(header)

	var spell_box := VBoxContainer.new()
	spell_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spell_box.add_theme_constant_override("separation", 4)

	for spell in spells:
		var spell_row := HBoxContainer.new()
		spell_row.add_theme_constant_override("separation", 6)
		spell_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var gem := Control.new()
		gem.custom_minimum_size = Vector2(12, 12)
		gem.mouse_filter = Control.MOUSE_FILTER_STOP
		var spell_ref := spell  # Capture for closure
		gem.mouse_entered.connect(func(): _show_spell_popup(spell_ref, gem))
		gem.mouse_exited.connect(func(): _hide_spell_popup())
		# Store spell ref and draw callback
		var draw_gem = func(): _draw_spell_gem(gem, spell_ref)
		gem.draw.connect(draw_gem)
		spell_row.add_child(gem)
		_spell_gem_controls[gem] = spell

		var spell_name := Label.new()
		spell_name.text = spell.spell_name
		spell_name.add_theme_font_size_override("font_size", 16)
		spell_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spell_row.add_child(spell_name)

		spell_box.add_child(spell_row)

	row.add_child(spell_box)
	if dimmed:
		row.modulate = _DIM
	_body.add_child(row)


# One reusable floating tooltip; content swapped per hovered gem. top_level so
# the PanelContainer parent's layout can't stretch it over the panel, and
# MOUSE_FILTER_IGNORE throughout so it never steals hover from the gem — both
# caused the appear/disappear flicker.
func _build_spell_popup() -> void:
	_spell_popup = PanelContainer.new()
	_spell_popup.top_level = true
	_spell_popup.z_index = 100
	_spell_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.15, 0.97)
	sb.border_color = _GOLD
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_spell_popup.add_theme_stylebox_override("panel", sb)
	_popup_vbox = VBoxContainer.new()
	_popup_vbox.add_theme_constant_override("separation", 2)
	_popup_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_popup.add_child(_popup_vbox)
	_spell_popup.hide()
	add_child(_spell_popup)


func _show_spell_popup(spell: SpellData, gem: Control) -> void:
	_current_spell_popup = spell
	_spell_popup_gem = gem
	_update_spell_popup()


func _update_spell_popup() -> void:
	if _current_spell_popup == null:
		return
	var spell := _current_spell_popup
	var accent := _accent if _accent != Color.WHITE else _GOLD

	for child in _popup_vbox.get_children():
		_popup_vbox.remove_child(child)
		child.queue_free()

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_vbox.add_child(header)

	var icon_tex := SpriteRegistry.get_icon("spells", SpriteRegistry.icon_key(spell.spell_name))
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(icon_rect)

	var title := Label.new()
	title.text = spell.spell_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", accent)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	if not spell.description.is_empty():
		_popup_vbox.add_child(_popup_line(spell.description))
	if _show_technical:
		for line in _spell_technical_lines(spell):
			_popup_vbox.add_child(_popup_line("• " + line))
	else:
		_popup_vbox.add_child(_popup_line("[Shift: technical details]", true))

	# Anchor below the gem, clamped inside the viewport. top_level position is
	# global/canvas space — same space as get_global_rect().
	var pos := _spell_popup.position
	if is_instance_valid(_spell_popup_gem):
		var gr := _spell_popup_gem.get_global_rect()
		pos = gr.position + Vector2(0.0, gr.size.y + 4.0)
	_spell_popup.reset_size()
	var psize := _spell_popup.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - psize.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - psize.y))
	_spell_popup.position = pos
	_spell_popup.show()


func _popup_line(text: String, dimmed: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dimmed:
		lbl.modulate = _DIM
	return lbl


## Mechanical facts straight off SpellData, one bullet per line.
func _spell_technical_lines(spell: SpellData) -> Array[String]:
	var lines: Array[String] = []
	if spell.is_cantrip:
		lines.append("Cantrip — Ingenuity pool, no Fervor die, usable in Burnout")
	else:
		lines.append("True Spell — Ingenuity pool + Fervor die, escalates Fervor")
	if spell.aspect_dice > 0 and not spell.aspect_stat.is_empty():
		lines.append("%d pool dice use %s" % [spell.aspect_dice, spell.aspect_stat.capitalize()])
	lines.append("Targets %s guard" % spell.target_pool.capitalize())
	if spell.flat_bonus != 0:
		lines.append("+%d flat after Keep" % spell.flat_bonus)
	if not spell.tags.is_empty():
		lines.append("Tags: %s" % ", ".join(spell.tags))
	if not spell.primes_status.is_empty():
		lines.append("Primes: %s" % spell.primes_status.replace("_", " "))
	return lines


func _hide_spell_popup() -> void:
	if _spell_popup != null:
		_spell_popup.hide()
	_current_spell_popup = null
	_spell_popup_gem = null


func _draw_spell_gem(gem: Control, spell: SpellData) -> void:
	var sz := gem.size
	var c := sz * 0.5
	var gem_color := _accent if _accent != Color.WHITE else _GOLD
	var dark_fill := Color(0.12, 0.10, 0.05, 0.9)

	var pts := PackedVector2Array()
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * (sz.x * 0.4))

	gem.draw_colored_polygon(pts, dark_fill)
	var rim := pts.duplicate()
	rim.append(pts[0])
	gem.draw_polyline(rim, gem_color, 1.0, true)


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
