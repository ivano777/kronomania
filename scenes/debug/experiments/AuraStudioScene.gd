extends Control

# AURA LAB — first entry of the DevHub EXPERIMENTS section. Type or randomize
# a public key; the aura spec derives from hash(AuraGen.PRIVATE_KEY :: key) and
# rebuilds live at the preview center. Replay restarts emission so the birth
# (aura growing out of the center point) is visible again. Dev-only scene —
# deleted with scenes/debug/ at release; AuraGen/AuraFX stay production-side.

const _HUB_SCENE := "res://scenes/debug/DevHubScene.tscn"
const _KEY_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
const _MOTION_ABBR := {
	"rise": "ris", "orbit": "orb", "spiral": "spi", "burst": "bur",
	"implode": "imp", "spark": "spk", "ripple": "rip",
}
const _GEO_ABBR := {
	"circle": "c", "polygon": "p", "star": "s", "ellipse": "e",
	"dashed": "d", "jagged": "J",
}

var _key_edit: LineEdit
var _seed_lbl: Label
var _name_lbl: Label
var _rarity_lbl: Label
var _spec_lbl: Label
var _swatches: HBoxContainer
var _tier_pick: OptionButton
var _fx: AuraFX


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.08)   # near-black void — auras read on it
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# DevHub hazard maroon band — unmistakably a dev scene.
	var band := ColorRect.new()
	band.color = Color(0.32, 0.10, 0.12)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 44.0
	add_child(band)
	var title := Label.new()
	title.text = "×  AURA LAB  ×"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 4.0
	add_child(title)

	var col := VBoxContainer.new()
	col.position = Vector2(8, 52)
	col.custom_minimum_size = Vector2(190, 0)
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	col.add_child(_mk_label("Public key"))
	_key_edit = LineEdit.new()
	_key_edit.text_changed.connect(_regen)
	col.add_child(_key_edit)

	var row := HBoxContainer.new()
	var rnd := Button.new()
	rnd.text = "Randomize"
	rnd.pressed.connect(_randomize_key)
	row.add_child(rnd)
	var rep := Button.new()
	rep.text = "Replay"
	rep.pressed.connect(_replay)
	row.add_child(rep)
	_tier_pick = OptionButton.new()
	for t in 4:
		_tier_pick.add_item("T%d" % (t + 1))
	_tier_pick.selected = 3
	_tier_pick.item_selected.connect(_on_tier_picked)
	row.add_child(_tier_pick)
	col.add_child(row)

	_seed_lbl = _mk_label("")
	col.add_child(_seed_lbl)
	_name_lbl = _mk_label("")
	_name_lbl.modulate = Color(1.0, 0.85, 0.55)
	col.add_child(_name_lbl)
	_rarity_lbl = _mk_label("")
	col.add_child(_rarity_lbl)
	_swatches = HBoxContainer.new()
	col.add_child(_swatches)
	_spec_lbl = _mk_label("")
	col.add_child(_spec_lbl)

	col.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "▶ Back to Dev Hub"
	back.pressed.connect(_back)
	col.add_child(back)

	_fx = AuraFX.new()
	_fx.position = Vector2(419, 202)   # center of the free area right of the column
	add_child(_fx)

	_randomize_key()


func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


# ── key → aura ────────────────────────────────────────────────────────────────

func _randomize_key() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var key := ""
	for i in 8:
		key += _KEY_CHARS[rng.randi_range(0, _KEY_CHARS.length() - 1)]
	_key_edit.text = key   # setting .text emits no text_changed — regen manually
	_regen(key)


func _replay() -> void:
	_fx.restart()


func _on_tier_picked(_i: int) -> void:
	_regen(_key_edit.text)


func _regen(key: String) -> void:
	var spec := AuraGen.generate_spec(key, _tier_pick.selected + 1)
	_fx.build(spec)
	_fx.restart()
	_seed_lbl.text = "seed %08x" % (int(spec["seed"]) & 0xFFFFFFFF)
	_name_lbl.text = String(spec["name"])
	_rarity_lbl.text = "%s · L%d/%d" % [String(spec["rarity"]).to_upper(),
			(spec["layers"] as Array).size(), int(spec["layer_potential"])]
	_rarity_lbl.modulate = AttackPresenter.rarity_tint(String(spec["rarity"]))
	var pal: Dictionary = spec["palette"]
	for c in _swatches.get_children():
		c.queue_free()
	for pc in (pal["ramp"] as Array):
		var sw := ColorRect.new()
		sw.color = pc
		sw.custom_minimum_size = Vector2(14, 14)
		_swatches.add_child(sw)
	var abbr: Array[String] = []
	for layer in (spec["layers"] as Array):
		var l: Dictionary = layer
		var tag: String = _MOTION_ABBR.get(String(l["motion"]), "?")
		if l["motion"] == "ripple":
			abbr.append("%s-%s%d" % [tag, _GEO_ABBR.get(String(l["geometry"]), "?"),
					int(l["max_radius"])])
		else:
			abbr.append("%s%d" % [tag, int(l["count"])])
	var lines: Array[String] = [
		"%s·%s·%dtex·%.1fHz" % [pal["scheme"], pal["profile"],
				(spec["textures"] as Array).size(), float(spec["pulse_hz"])],
	]
	# Layer tags three per line — keeps the 190px column from overflowing.
	for i in range(0, abbr.size(), 3):
		lines.append(" ".join(abbr.slice(i, i + 3)))
	var muts: Array = spec["mutations"]
	if not muts.is_empty():
		lines.append("mut: " + "+".join(muts))
	_spec_lbl.text = "\n".join(lines)


# ── nav ───────────────────────────────────────────────────────────────────────

func _back() -> void:
	get_tree().change_scene_to_file(_HUB_SCENE)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_back()
