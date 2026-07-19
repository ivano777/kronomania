extends Control

# Held-anchor editor — visual authoring tool for the held-equipment overlays.
# Run:  godot --path . tools/held_editor/HeldEditor.tscn
# Dev tool only: never imported by production scenes; delete folder at release.
#
# Two modes (top-left toggle):
#   PLAYER — pick hero (only ones with a held.json manifest) + animation;
#     drag MAIN (orange) / OFF (cyan) hand crosshairs per frame, set the
#     weapon angle with the rotation gumball. Live item preview uses the
#     exact runtime math (grip pinned to anchor, rotation pivots at grip).
#     Saves assets/sprites/combatants/<hero>/held.json.
#   ITEMS — pick a held art piece; click/drag the GRIP (yellow) crosshair
#     onto its handle pixel. Saves assets/sprites/held/<key>.json
#     (preserves "planted"). Grip changes feed the PLAYER preview live.
#
# Keys: arrows nudge 1px · Q/E rotate 5° (Shift 1°) · ,/. frame · P play
#       F flip · +/- zoom · Ctrl+S save · LMB drag · RMB drag pan

const ANIMS: Array[String] = ["idle", "attack_melee", "cast_spell", "hurt"]
const COL_MAIN := Color("ff8830")
const COL_OFF := Color("30c8ff")
const COL_GRIP := Color("ffe040")
const COL_BG := Color("232028")
const STUB_KEY := "STUB sword"

var _mode: String = "hero"              # "hero" | "item"

var _heroes: Array[String] = []
var _items: Array[String] = []          # held art keys (STUB first)
var _item_tex: Dictionary = {}          # key -> Texture2D
var _item_grip: Dictionary = {}         # key -> Vector2i (live-edited)
var _item_planted: Dictionary = {}      # key -> bool

var _hero: String = ""
var _frames: SpriteFrames = null
var _manifest: Dictionary = {}
var _tables: Dictionary = {}            # anim -> {"main"|"off": [[x,y,rot],..]}
var _anim: String = "idle"
var _frame: int = 0
var _hand: String = "main"
var _item_sel: String = ""              # ITEMS mode selection
var _dirty: bool = false

var _zoom: float = 5.0
var _pan := Vector2.ZERO
var _flip: bool = false
var _playing: bool = false
var _play_t: float = 0.0
var _item_alpha: float = 0.9            # preview aid only — never saved
var _behind: bool = false               # draw items behind the hero sprite

var _drag_mode: String = ""             # "" | "main" | "off" | "rot" | "grip" | "pan"
var _pan_start := Vector2.ZERO
var _pan_mouse := Vector2.ZERO

var _mode_hero_btn: Button
var _mode_item_btn: Button
var _hero_list: ItemList
var _item_list: ItemList
var _anim_list: ItemList
var _anims_lbl: Label
var _canvas: Control
var _main_item_btn: OptionButton
var _off_item_btn: OptionButton
var _pickers: Array[Control] = []
var _hero_only_btns: Array[Control] = []
var _readout: Label
var _status: Label
var _frame_lbl: Label


func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	_scan_items()
	_build_ui()
	_scan_heroes()
	if not _heroes.is_empty():
		_hero_list.select(0)
		_load_hero(_heroes[0])
	_apply_mode()
	set_process(true)
	if OS.get_environment("HELD_EDITOR_SMOKE") != "":
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://held_editor_smoke.png")
		print("SMOKE_SHOT=", ProjectSettings.globalize_path("user://held_editor_smoke.png"))
		get_tree().quit()


# ── Discovery ─────────────────────────────────────────────────────────────────

# Only heroes that already ship a held.json — the runtime consumes just these.
func _scan_heroes() -> void:
	_heroes.clear()
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
	_hero_list.clear()
	for h in _heroes:
		_hero_list.add_item(h)


func _scan_items() -> void:
	_items = [STUB_KEY]
	_item_tex[STUB_KEY] = _make_stub_texture()
	_item_grip[STUB_KEY] = Vector2i(3, 20)
	_item_planted[STUB_KEY] = false
	var d := DirAccess.open("res://assets/sprites/held")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png") and not f.ends_with(".import"):
			var key := f.trim_suffix(".png")
			var tex := load("res://assets/sprites/held/" + f) as Texture2D
			if tex != null:
				_items.append(key)
				_item_tex[key] = tex
				var meta: Dictionary = SpriteRegistry.get_held_meta(key)
				var g: Variant = meta.get("grip")
				_item_grip[key] = Vector2i(int(g[0]), int(g[1])) if g is Array and (g as Array).size() == 2 \
						else Vector2i(tex.get_width() / 2, tex.get_height() / 2)
				_item_planted[key] = bool(meta.get("planted", false))
		f = d.get_next()


# Stub sword: blade steel, guard+handle gold — distinct zones.
func _make_stub_texture() -> ImageTexture:
	var img := Image.create(7, 24, false, Image.FORMAT_RGBA8)
	for y in range(0, 16):
		for x in range(2, 5):
			img.set_pixel(x, y, Color("7fa5ad"))
	for y in range(16, 18):
		for x in range(0, 7):
			img.set_pixel(x, y, Color("c89040"))
	for y in range(18, 23):
		for x in range(2, 5):
			img.set_pixel(x, y, Color("f0c060"))
	return ImageTexture.create_from_image(img)


# ── Loading / state ───────────────────────────────────────────────────────────

func _load_hero(hero: String) -> void:
	_hero = hero
	_frames = SpriteRegistry.get_combatant_frames(hero)
	_manifest = SpriteRegistry.get_hero_held_meta(hero)
	_tables.clear()
	_anim_list.clear()
	for anim in ANIMS:
		if _frames == null or not _frames.has_animation(anim) or _frames.get_frame_count(anim) == 0:
			continue
		var n := _frames.get_frame_count(anim)
		var t := {"main": [], "off": []}
		for hand in ["main", "off"]:
			for f in n:
				var e: Variant = Combatant.anchor_entry(_manifest, anim, hand, f)
				var row: Array = [0, 0, 0]
				if e is Array and (e as Array).size() >= 2:
					var a := e as Array
					row = [int(a[0]), int(a[1]), int(a[2]) if a.size() > 2 else 0]
				else:
					var fs := _frame_size(anim)
					row = [int(fs.x / 2), int(fs.y * 0.6), 0]
				(t[hand] as Array).append(row)
		_tables[anim] = t
		_anim_list.add_item(anim)
	_anim = ""
	if _anim_list.item_count > 0:
		_anim_list.select(0)
		_anim = _anim_list.get_item_text(0)
	_frame = 0
	_dirty = false
	_playing = false
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


func _frame_size(anim: String) -> Vector2:
	if _frames == null:
		return Vector2(64, 64)
	var tex := _frames.get_frame_texture(anim, 0)
	return tex.get_size() if tex != null else Vector2(64, 64)


func _row(hand: String) -> Array:
	if _anim == "" or not _tables.has(_anim):
		return [0, 0, 0]
	return (_tables[_anim][hand] as Array)[_frame] as Array


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Left column
	var left := VBoxContainer.new()
	left.position = Vector2(4, 4)
	left.custom_minimum_size = Vector2(104, 352)
	add_child(left)
	var mode_box := HBoxContainer.new()
	_mode_hero_btn = _mk_btn("PLAYER", func() -> void: _switch_mode("hero"))
	_mode_item_btn = _mk_btn("ITEMS", func() -> void: _switch_mode("item"))
	mode_box.add_child(_mode_hero_btn)
	mode_box.add_child(_mode_item_btn)
	left.add_child(mode_box)

	_hero_list = ItemList.new()
	_hero_list.custom_minimum_size = Vector2(104, 72)
	_hero_list.item_selected.connect(func(i: int) -> void: _load_hero(_heroes[i]))
	left.add_child(_hero_list)

	_item_list = ItemList.new()
	_item_list.custom_minimum_size = Vector2(104, 150)
	_item_list.item_selected.connect(_on_item_selected)
	for k in _items:
		if k != STUB_KEY:
			_item_list.add_item(k)
	left.add_child(_item_list)

	_anims_lbl = _mk_label("ANIMS")
	left.add_child(_anims_lbl)
	_anim_list = ItemList.new()
	_anim_list.custom_minimum_size = Vector2(104, 92)
	_anim_list.item_selected.connect(_on_anim_selected)
	left.add_child(_anim_list)

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.pressed.connect(_save)
	save_btn.focus_mode = Control.FOCUS_NONE
	left.add_child(save_btn)
	var all_btn := _mk_btn("ALL FRMS", _apply_all_frames)
	left.add_child(all_btn)
	_status = _mk_label("")
	left.add_child(_status)

	# Canvas
	_canvas = Control.new()
	_canvas.position = Vector2(112, 4)
	_canvas.custom_minimum_size = Vector2(414, 332)
	_canvas.size = Vector2(414, 332)
	_canvas.clip_contents = true
	_canvas.focus_mode = Control.FOCUS_ALL
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	add_child(_canvas)
	var frame_border := ReferenceRect.new()
	frame_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_border.editor_only = false
	frame_border.border_color = Color(1, 1, 1, 0.15)
	frame_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(frame_border)

	# Right column
	var right := VBoxContainer.new()
	right.position = Vector2(530, 4)
	right.custom_minimum_size = Vector2(106, 332)
	add_child(right)
	right.add_child(_mk_legend("MAIN hand", COL_MAIN))
	right.add_child(_mk_legend("OFF hand", COL_OFF))
	right.add_child(_mk_legend("item GRIP", COL_GRIP))
	right.add_child(_mk_label(" "))
	var main_lbl := _mk_label("MAIN item")
	right.add_child(main_lbl)
	_main_item_btn = OptionButton.new()
	for k in _items:
		_main_item_btn.add_item(k)
	_main_item_btn.selected = 0
	_main_item_btn.item_selected.connect(func(_i: int) -> void: _canvas.queue_redraw())
	_main_item_btn.focus_mode = Control.FOCUS_NONE
	right.add_child(_main_item_btn)
	var off_lbl := _mk_label("OFF item")
	right.add_child(off_lbl)
	_off_item_btn = OptionButton.new()
	_off_item_btn.add_item("(none)")
	for k in _items:
		_off_item_btn.add_item(k)
	_off_item_btn.selected = 0
	_off_item_btn.item_selected.connect(func(_i: int) -> void: _canvas.queue_redraw())
	_off_item_btn.focus_mode = Control.FOCUS_NONE
	right.add_child(_off_item_btn)
	var alpha_lbl := _mk_label("item alpha")
	right.add_child(alpha_lbl)
	var alpha_slider := HSlider.new()
	alpha_slider.min_value = 0.1
	alpha_slider.max_value = 1.0
	alpha_slider.step = 0.05
	alpha_slider.value = _item_alpha
	alpha_slider.custom_minimum_size = Vector2(96, 16)
	alpha_slider.focus_mode = Control.FOCUS_NONE
	alpha_slider.value_changed.connect(func(v: float) -> void:
		_item_alpha = v
		_canvas.queue_redraw())
	right.add_child(alpha_slider)
	var behind_box := CheckBox.new()
	behind_box.text = "behind"
	behind_box.focus_mode = Control.FOCUS_NONE
	behind_box.toggled.connect(func(on: bool) -> void:
		_behind = on
		_canvas.queue_redraw())
	right.add_child(behind_box)
	_pickers = [main_lbl, _main_item_btn, off_lbl, _off_item_btn,
			alpha_lbl, alpha_slider, behind_box, all_btn]
	right.add_child(_mk_label(" "))
	_readout = _mk_label("")
	right.add_child(_readout)

	# Bottom bar
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(112, 338)
	bottom.custom_minimum_size = Vector2(414, 20)
	add_child(bottom)
	var prev_btn := _mk_btn("<", func() -> void: _step_frame(-1))
	bottom.add_child(prev_btn)
	_frame_lbl = _mk_label("frm 0/0")
	bottom.add_child(_frame_lbl)
	var next_btn := _mk_btn(">", func() -> void: _step_frame(1))
	bottom.add_child(next_btn)
	var play_btn := _mk_btn("PLAY", _toggle_play)
	bottom.add_child(play_btn)
	var flip_btn := _mk_btn("FLIP", func() -> void:
		_flip = not _flip
		_center_view()
		_canvas.queue_redraw())
	bottom.add_child(flip_btn)
	_hero_only_btns = [prev_btn, next_btn, play_btn, flip_btn]
	bottom.add_child(_mk_btn("Z+", func() -> void: _set_zoom(_zoom + 1)))
	bottom.add_child(_mk_btn("Z-", func() -> void: _set_zoom(_zoom - 1)))
	bottom.add_child(_mk_btn("CENTER", _center_and_redraw))
	bottom.add_child(_mk_btn("EXIT", _exit_editor))


func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _mk_btn(t: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(fn)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _mk_legend(text: String, col: Color) -> HBoxContainer:
	var box := HBoxContainer.new()
	var sq := ColorRect.new()
	sq.color = col
	sq.custom_minimum_size = Vector2(10, 10)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(sq)
	box.add_child(_mk_label(text))
	return box


# ── Mode switching ────────────────────────────────────────────────────────────

func _switch_mode(m: String) -> void:
	if _mode == m:
		return
	_mode = m
	_playing = false
	_drag_mode = ""
	_apply_mode()


func _apply_mode() -> void:
	var hero_mode := _mode == "hero"
	_hero_list.visible = hero_mode
	_anim_list.visible = hero_mode
	_anims_lbl.visible = hero_mode
	_item_list.visible = not hero_mode
	for c in _pickers:
		c.visible = hero_mode
	for c in _hero_only_btns:
		c.visible = hero_mode
	_mode_hero_btn.modulate = Color(1, 1, 1) if hero_mode else Color(0.55, 0.55, 0.55)
	_mode_item_btn.modulate = Color(0.55, 0.55, 0.55) if hero_mode else Color(1, 1, 1)
	if not hero_mode:
		_flip = false
		if _item_sel == "" and _item_list.item_count > 0:
			_item_list.select(0)
			_item_sel = _item_list.get_item_text(0)
		_zoom = 10.0
	else:
		_zoom = 5.0
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


func _on_item_selected(i: int) -> void:
	_item_sel = _item_list.get_item_text(i)
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


func _on_anim_selected(i: int) -> void:
	_anim = _anim_list.get_item_text(i)
	_frame = 0
	_playing = false
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


# ── State changes ─────────────────────────────────────────────────────────────

func _step_frame(dir: int) -> void:
	if _mode != "hero" or _anim == "":
		return
	var n := _frames.get_frame_count(_anim)
	_frame = wrapi(_frame + dir, 0, n)
	_update_labels()
	_canvas.queue_redraw()


func _toggle_play() -> void:
	if _mode != "hero":
		return
	_playing = not _playing
	_play_t = 0.0


func _set_zoom(z: float) -> void:
	var keep := _pan + _canvas.size / (2.0 * _zoom)
	_zoom = clampf(z, 2.0, 16.0)
	_pan = keep - _canvas.size / (2.0 * _zoom)
	_canvas.queue_redraw()


func _nudge(dx: int, dy: int) -> void:
	if _mode == "item":
		if _item_sel != "":
			var g: Vector2i = _item_grip[_item_sel]
			_item_grip[_item_sel] = g + Vector2i(dx, dy)
			_mark_dirty()
		return
	var r := _row(_hand)
	r[0] = int(r[0]) + dx
	r[1] = int(r[1]) + dy
	_mark_dirty()


func _rotate_by(deg: int) -> void:
	if _mode != "hero":
		return
	var r := _row(_hand)
	r[2] = wrapi(int(r[2]) + deg, -180, 181)
	_mark_dirty()


## Copies the selected hand's current [x, y, rot] onto every frame of the
## current animation — "save as default" for quickly blocking an anim out.
func _apply_all_frames() -> void:
	if _mode != "hero" or _anim == "":
		return
	var cur := _row(_hand)
	for r in (_tables[_anim][_hand] as Array):
		var a := r as Array
		a[0] = int(cur[0])
		a[1] = int(cur[1])
		a[2] = int(cur[2])
	_mark_dirty()
	_status.text = "%s > all %s" % [_hand.to_upper(), _anim]


func _mark_dirty() -> void:
	_dirty = true
	_update_labels()
	_canvas.queue_redraw()


func _update_labels() -> void:
	_status.text = "* unsaved" if _dirty else ""
	if _mode == "item":
		_frame_lbl.text = "item"
		if _item_sel == "":
			_readout.text = ""
		else:
			var g: Vector2i = _item_grip[_item_sel]
			var planted := " planted" if bool(_item_planted.get(_item_sel, false)) else ""
			_readout.text = "%s\nGRIP %d,%d%s" % [_item_sel, g.x, g.y, planted]
		return
	if _anim == "":
		_frame_lbl.text = "frm -/-"
		_readout.text = ""
		return
	_frame_lbl.text = "frm %d/%d" % [_frame + 1, _frames.get_frame_count(_anim)]
	var m := _row("main")
	var o := _row("off")
	_readout.text = "hand: %s\nMAIN %d,%d r%d\nOFF %d,%d r%d" % [
		_hand.to_upper(), m[0], m[1], m[2], o[0], o[1], o[2]]


func _process(delta: float) -> void:
	if not _playing or _anim == "" or _mode != "hero":
		return
	_play_t += delta
	var fps := _frames.get_animation_speed(_anim)
	var n := _frames.get_frame_count(_anim)
	var f := int(_play_t * fps) % n
	if f != _frame:
		_frame = f
		_update_labels()
		_canvas.queue_redraw()


# ── Coordinate mapping ────────────────────────────────────────────────────────

func _content_size() -> Vector2:
	if _mode == "item":
		if _item_sel == "":
			return Vector2(16, 16)
		return (_item_tex[_item_sel] as Texture2D).get_size()
	return _frame_size(_anim) if _anim != "" else Vector2(64, 64)


func _to_screen(p: Vector2) -> Vector2:
	var q := p
	if _flip:
		q.x = _content_size().x - q.x
	return (q - _pan) * _zoom


func _from_screen(s: Vector2) -> Vector2:
	var q := s / _zoom + _pan
	if _flip:
		q.x = _content_size().x - q.x
	return q


## Pans so the visible content (sprite bbox / item art) sits at canvas centre.
func _center_view() -> void:
	var center := _content_size() / 2.0
	if _mode == "hero" and _frames != null and _anim != "":
		var tex := _frames.get_frame_texture(_anim, 0)
		if tex != null:
			var img := tex.get_image()
			if img != null:
				var used := img.get_used_rect()
				if used.size.x > 0:
					center = Vector2(used.get_center())
	if _flip:
		center.x = _content_size().x - center.x
	_pan = center - _canvas.size / (2.0 * _zoom)


func _center_and_redraw() -> void:
	_center_view()
	_canvas.queue_redraw()


func _anchor_screen(hand: String) -> Vector2:
	var r := _row(hand)
	return _to_screen(Vector2(int(r[0]) + 0.5, int(r[1]) + 0.5))


func _grip_screen() -> Vector2:
	var g: Vector2i = _item_grip[_item_sel]
	return _to_screen(Vector2(g) + Vector2(0.5, 0.5))


func _knob_screen() -> Vector2:
	var r := _row(_hand)
	var rot := deg_to_rad(Combatant.held_rotation(float(r[2]), _flip))
	return _anchor_screen(_hand) + Vector2(sin(rot), -cos(rot)) * 34.0


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw_canvas() -> void:
	if _mode == "item":
		_draw_item_mode()
		return
	if _anim == "" or _frames == null:
		return
	var tex := _frames.get_frame_texture(_anim, _frame)
	if tex == null:
		return
	var fs := tex.get_size()

	# Frame (handles AtlasTexture; negative src width mirrors when flipped)
	var base: Texture2D = tex
	var region := Rect2(Vector2.ZERO, fs)
	if tex is AtlasTexture:
		base = (tex as AtlasTexture).atlas
		region = (tex as AtlasTexture).region
	var dst := Rect2(_to_screen(Vector2.ZERO if not _flip else Vector2(fs.x, 0)), fs * _zoom)
	var src := region
	if _flip:
		src = Rect2(Vector2(region.position.x + region.size.x, region.position.y),
				Vector2(-region.size.x, region.size.y))
	if _behind:
		_draw_held(_current_item("main"), "main")
		_draw_held(_current_item("off"), "off")
	_canvas.draw_texture_rect_region(base, dst, src)
	if not _behind:
		_draw_held(_current_item("main"), "main")
		_draw_held(_current_item("off"), "off")
	_draw_grid(fs)

	_draw_crosshair(_anchor_screen("main"), COL_MAIN, _hand == "main")
	_draw_crosshair(_anchor_screen("off"), COL_OFF, _hand == "off")
	_draw_small_cross(_anchor_screen("main"), COL_GRIP)
	_draw_small_cross(_anchor_screen("off"), COL_GRIP)
	var a := _anchor_screen(_hand)
	_canvas.draw_arc(a, 34.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.0)
	var k := _knob_screen()
	_canvas.draw_line(a, k, Color(1, 1, 1, 0.35))
	_canvas.draw_circle(k, 5.0, COL_GRIP if _drag_mode == "rot" else Color(1, 1, 1, 0.9))


func _draw_item_mode() -> void:
	if _item_sel == "":
		return
	var tex: Texture2D = _item_tex[_item_sel]
	var fs := tex.get_size()
	_canvas.draw_texture_rect(tex, Rect2(_to_screen(Vector2.ZERO), fs * _zoom), false)
	_draw_grid(fs)
	_draw_crosshair(_grip_screen(), COL_GRIP, true)


func _draw_grid(fs: Vector2) -> void:
	if _zoom < 6.0:
		return
	var tl := _to_screen(Vector2.ZERO)
	var br := _to_screen(Vector2(fs.x, fs.y))
	var x0 := minf(tl.x, br.x)
	var x1 := maxf(tl.x, br.x)
	for gx in range(0, int(fs.x) + 1):
		var sx := _to_screen(Vector2(gx, 0)).x
		_canvas.draw_line(Vector2(sx, tl.y), Vector2(sx, br.y), Color(1, 1, 1, 0.05))
	for gy in range(0, int(fs.y) + 1):
		var sy := _to_screen(Vector2(0, gy)).y
		_canvas.draw_line(Vector2(x0, sy), Vector2(x1, sy), Color(1, 1, 1, 0.05))


func _current_item(hand: String) -> String:
	if hand == "main":
		return _items[_main_item_btn.selected]
	if _off_item_btn.selected == 0:
		return ""
	return _items[_off_item_btn.selected - 1]


func _draw_held(key: String, hand: String) -> void:
	if key == "" or not _item_tex.has(key):
		return
	var tex: Texture2D = _item_tex[key]
	var grip: Vector2i = _item_grip[key]
	var r := _row(hand)
	var rot := deg_to_rad(Combatant.held_rotation(float(r[2]), _flip))
	var anchor := _anchor_screen(hand)
	var off := Combatant.held_slot_offset(grip, tex.get_size(), _flip)
	_canvas.draw_set_transform(anchor, rot, Vector2(_zoom, _zoom))
	_canvas.draw_texture_rect(tex, Rect2(off, tex.get_size()), false, Color(1, 1, 1, _item_alpha))
	_canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_crosshair(p: Vector2, col: Color, selected: bool) -> void:
	var l := 14.0 if selected else 9.0
	_canvas.draw_line(p + Vector2(-l, 0), p + Vector2(l, 0), col, 1.0)
	_canvas.draw_line(p + Vector2(0, -l), p + Vector2(0, l), col, 1.0)
	if selected:
		_canvas.draw_arc(p, 7.0, 0, TAU, 24, col, 1.0)


func _draw_small_cross(p: Vector2, col: Color) -> void:
	_canvas.draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), col, 1.0)
	_canvas.draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), col, 1.0)


# ── Input ─────────────────────────────────────────────────────────────────────

func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(_zoom + 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(_zoom - 1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_canvas.grab_focus()
				_start_drag(mb.position)
			else:
				_drag_mode = ""
				_canvas.queue_redraw()
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag_mode = "pan"
				_pan_start = _pan
				_pan_mouse = mb.position
			else:
				_drag_mode = ""
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		match _drag_mode:
			"main", "off":
				var p := _from_screen(mm.position)
				var r := _row(_drag_mode)
				r[0] = int(floor(p.x))
				r[1] = int(floor(p.y))
				_mark_dirty()
			"grip":
				var p := _from_screen(mm.position)
				_item_grip[_item_sel] = Vector2i(int(floor(p.x)), int(floor(p.y)))
				_mark_dirty()
			"rot":
				var d := mm.position - _anchor_screen(_hand)
				var deg := rad_to_deg(atan2(d.x, -d.y))
				deg = Combatant.held_rotation(deg, _flip)
				var snap := 1 if Input.is_key_pressed(KEY_SHIFT) else 5
				var r := _row(_hand)
				r[2] = wrapi(int(round(deg / snap)) * snap, -180, 181)
				_mark_dirty()
			"pan":
				_pan = _pan_start - (mm.position - _pan_mouse) / _zoom
				_canvas.queue_redraw()


func _start_drag(pos: Vector2) -> void:
	if _mode == "item":
		if _item_sel == "":
			return
		var p := _from_screen(pos)
		_item_grip[_item_sel] = Vector2i(int(floor(p.x)), int(floor(p.y)))
		_drag_mode = "grip"
		_mark_dirty()
		return
	if _anim == "":
		return
	if pos.distance_to(_knob_screen()) <= 10.0:
		_drag_mode = "rot"
		return
	var dm := pos.distance_to(_anchor_screen("main"))
	var doff := pos.distance_to(_anchor_screen("off"))
	if minf(dm, doff) <= 12.0:
		_hand = "main" if dm <= doff else "off"
		_drag_mode = _hand
		_update_labels()
		_canvas.queue_redraw()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed:
		return
	var k := ev as InputEventKey
	var fine := 1 if k.shift_pressed else 5
	match k.keycode:
		KEY_LEFT:
			_nudge(-1 if not _flip else 1, 0)
		KEY_RIGHT:
			_nudge(1 if not _flip else -1, 0)
		KEY_UP:
			_nudge(0, -1)
		KEY_DOWN:
			_nudge(0, 1)
		KEY_Q:
			_rotate_by(-fine)
		KEY_E:
			_rotate_by(fine)
		KEY_COMMA:
			_step_frame(-1)
		KEY_PERIOD:
			_step_frame(1)
		KEY_P:
			_toggle_play()
		KEY_F:
			if _mode == "hero":
				_flip = not _flip
				_center_view()
				_canvas.queue_redraw()
		KEY_EQUAL, KEY_KP_ADD:
			_set_zoom(_zoom + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_set_zoom(_zoom - 1)
		KEY_C:
			_center_and_redraw()
		KEY_S:
			if k.ctrl_pressed:
				_save()
		KEY_ESCAPE:
			_exit_editor()


## Back to the scene that opened us (dev menu), or quit when standalone.
func _exit_editor() -> void:
	if DebugManager.return_scene != "":
		var back := DebugManager.return_scene
		DebugManager.return_scene = ""
		get_tree().change_scene_to_file(back)
	else:
		get_tree().quit()


# ── Persistence ───────────────────────────────────────────────────────────────

func _save() -> void:
	if _mode == "item":
		_save_item()
	else:
		_save_hero()


func _save_item() -> void:
	if _item_sel == "":
		return
	var g: Vector2i = _item_grip[_item_sel]
	var s := "{\n\t\"grip\": [%d, %d]" % [g.x, g.y]
	if bool(_item_planted.get(_item_sel, false)):
		s += ",\n\t\"planted\": true"
	s += "\n}\n"
	var path := "res://assets/sprites/held/%s.json" % _item_sel
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED"
		return
	f.store_string(s)
	f.close()
	_dirty = false
	_update_labels()
	_status.text = "saved"
	print("grip saved: ", ProjectSettings.globalize_path(path))


func _save_hero() -> void:
	if _hero == "" or _tables.is_empty():
		return
	var idle_first: Array = (_tables.get("idle", {"main": [[0, 0, 0]]})["main"] as Array)[0] as Array
	var base_main: Array = _manifest.get("main", [idle_first[0], idle_first[1]])
	var base_off_row: Array = (_tables.get("idle", {"off": [[0, 0, 0]]})["off"] as Array)[0] as Array
	var base_off: Array = _manifest.get("off", [base_off_row[0], base_off_row[1]])
	var s := "{\n"
	s += "\t\"main\": [%d, %d],\n" % [int(base_main[0]), int(base_main[1])]
	s += "\t\"off\": [%d, %d],\n" % [int(base_off[0]), int(base_off[1])]
	if _manifest.has("idle_bob"):
		var bob_strs: Array[String] = []
		for v in (_manifest["idle_bob"] as Array):
			bob_strs.append(str(int(v)))
		s += "\t\"idle_bob\": [%s],\n" % ", ".join(bob_strs)
	s += "\t\"anims\": {\n"
	var anim_blocks: Array[String] = []
	for anim in ANIMS:
		if not _tables.has(anim):
			continue
		var block := "\t\t\"%s\": {\n" % anim
		block += "\t\t\t\"main\": [%s],\n" % _fmt_rows(_tables[anim]["main"] as Array)
		block += "\t\t\t\"off\":  [%s]\n" % _fmt_rows(_tables[anim]["off"] as Array)
		block += "\t\t}"
		anim_blocks.append(block)
	s += ",\n".join(anim_blocks) + "\n\t}\n}\n"
	var path := "res://assets/sprites/combatants/%s/held.json" % _hero
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED"
		return
	f.store_string(s)
	f.close()
	_dirty = false
	_update_labels()
	_status.text = "saved"
	print("held.json saved: ", ProjectSettings.globalize_path(path))


func _fmt_rows(rows: Array) -> String:
	var parts: Array[String] = []
	for r in rows:
		var a := r as Array
		parts.append("[%d, %d, %d]" % [int(a[0]), int(a[1]), int(a[2])])
	return ", ".join(parts)
