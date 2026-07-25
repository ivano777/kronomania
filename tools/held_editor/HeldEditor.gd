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
#     onto its handle pixel. FLIP H/V checkboxes mirror the art live (here and
#     in the PLAYER preview; grip crosshair tracks the mirror). Per-hand chip
#     strips set the draw order: drag the H/W/G
#     chips left→right (left = drawn first/behind, right = on top); the "glove"
#     checkbox adds/removes the G chip. Saves assets/sprites/held/<key>.json
#     (preserves "planted"). Back variants (<key>_back) and _glove are editable
#     entries with own grip. Switching to PLAYER auto-previews the edited item
#     in the MAIN hand (unless already shown), so tweaks land on the hero.
#   PLAYER preview honours each item's order (behind-slots swap to _back art)
#     and draws the shared glove. EDIT toggles a bigger glove gumball (drag
#     centre = move, knob = rotate) over the weapon's for the selected hand;
#     RESET GLOVE returns it to the weapon's pose. Saved as hero "glove_off"
#     [dx, dy, drot]. "glv" checkbox hides the glove in the preview; "x-ray
#     hero" dims the hero so items drawn behind the body (off-hand shield) show.
#   OVR panel (PLAYER mode, left column) — per-hero override chain (schema in
#     SpriteRegistry): target "(no ovr)" edits the hero base tables as always;
#     "hero dflt" writes item_defaults (tier 2, every item); an item key writes
#     items.<key> (tier 3). With a delta target active, the normal gumball/drag
#     edits store the DIFFERENCE from the base table as "pos"/"rot" (base rows
#     untouched); H/V buttons cycle the flip override inh→ON→off (item targets
#     write it under the shown art's key, so behind-body slots override the
#     _back variant). CPY snapshots the current anim+hand base rows into
#     items.<key>.anims — after that, drags edit those per-frame rows directly.
#     CLR wipes the target's overrides. All saved into the hero held.json.
#
# Keys: arrows nudge 1px · Q/E rotate 5° (Shift 1°) · ,/. frame · P play
#       F flip · +/- zoom · Ctrl+S save · LMB drag · RMB pan

const ANIMS: Array[String] = ["idle", "attack_melee", "cast_spell", "hurt"]
const COL_MAIN := Color("ff8830")
const COL_OFF := Color("30c8ff")
const COL_GRIP := Color("ffe040")
const COL_GLOVE := Color("50e090")
const COL_HERO := Color("8090a0")
const COL_WEAPON := Color("d0a850")
const COL_BG := Color("232028")
const STUB_KEY := "STUB sword"
# Draw-order chip strip geometry (ITEMS mode). Left→right chips = the item's
# "order" tokens back→top: leftmost drawn first (deepest), rightmost on top.
const CHIP_W := 28.0
const CHIP_H := 18.0
const CHIP_GAP := 3.0
const DEFAULT_TOKENS := ["hero", "weapon", "hand"]

var _mode: String = "hero"              # "hero" | "item"

var _heroes: Array[String] = []
var _items: Array[String] = []          # held art keys (STUB first)
var _item_tex: Dictionary = {}          # key -> Texture2D
var _item_grip: Dictionary = {}         # key -> Vector2i (live-edited)
var _item_planted: Dictionary = {}      # key -> bool
var _item_order: Dictionary = {}        # key -> raw "order" value (String | Dictionary | null)
var _item_has_grip: Dictionary = {}     # key -> bool (json authored a grip)
var _item_fliph: Dictionary = {}        # key -> bool (mirror art horizontally)
var _item_flipv: Dictionary = {}        # key -> bool (mirror art vertically)
var _item_smear: Dictionary = {}        # key -> raw "smear" json value (params source)

var _hero: String = ""
var _frames: SpriteFrames = null
var _manifest: Dictionary = {}
var _tables: Dictionary = {}            # anim -> {"main"|"off": [[x,y,rot],..]}
var _ovr_defaults: Dictionary = {}      # hero "item_defaults" override block (tier 2)
var _ovr_items: Dictionary = {}         # hero "items" override block (tier 3), key -> dict
var _ovr_target: String = ""            # "" = no ovr, "*" = hero defaults, else item key
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
var _glove_show: bool = true            # preview toggle only — never saved
var _smear_show: bool = false           # smear preview toggle — never saved
var _xray: bool = false                 # dim hero so behind-body items show
var _glove_edit: bool = false           # glove gumball active (never saved)
var _glove_off: Dictionary = {"main": Vector2i.ZERO, "off": Vector2i.ZERO}
var _glove_rot: Dictionary = {"main": 0, "off": 0}    # deg delta from weapon angle

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
var _strip_main: Control
var _strip_off: Control
var _glove_chk_main: CheckBox
var _glove_chk_off: CheckBox
var _flip_h_chk: CheckBox
var _flip_v_chk: CheckBox
# per-hand editable draw-order token lists (subset/permutation of DEFAULT_TOKENS)
var _edit_tokens: Dictionary = {"main": [], "off": []}
var _chip_drag: Dictionary = {"hand": "", "from": -1, "x": 0.0}
var _glove_edit_btn: Button
var _picker_keys: Array[String] = []    # picker index -> item key (STUB + equippables)
var _pickers: Array[Control] = []
var _ovr_btn: OptionButton
var _ovr_keys: Array[String] = []       # ovr option index -> target token ("", "*", key)
var _ovr_h_btn: Button
var _ovr_v_btn: Button
var _ovr_copy_btn: Button
var _ovr_clear_btn: Button
var _ovr_controls: Array[Control] = []  # hero-mode-only OVR panel
var _item_only: Array[Control] = []
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
	_item_fliph[STUB_KEY] = false
	_item_flipv[STUB_KEY] = false
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
				_item_order[key] = meta.get("order")
				_item_has_grip[key] = g is Array
				_item_fliph[key] = bool(meta.get("flip_h", false))
				_item_flipv[key] = bool(meta.get("flip_v", false))
				_item_smear[key] = meta.get("smear")
		f = d.get_next()
	# Back variants without their own authored grip inherit the front item's
	# grip — same rule as the runtime (Combatant.held_back_grip).
	for key in _items:
		if key.ends_with("_back") and not bool(_item_has_grip.get(key, false)):
			var base := key.trim_suffix("_back")
			if _item_grip.has(base):
				_item_grip[key] = _item_grip[base]


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
	_ovr_defaults = (_manifest.get("item_defaults", {}) as Dictionary).duplicate(true)
	_ovr_items = (_manifest.get("items", {}) as Dictionary).duplicate(true)
	_ovr_target = ""
	for hand in ["main", "off"]:
		var e: Array = Combatant._glove_entry(_manifest, hand)
		_glove_off[hand] = Vector2i(int(e[0]), int(e[1]))
		_glove_rot[hand] = int(e[2])
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
	_rebuild_ovr_options()
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


# ── Override chain (item_defaults / items) ────────────────────────────────────
# Live editor state assembled into a hero-manifest shape so display and edit
# math reuse the exact runtime resolution (Combatant.anchor_entry_for_item &c).

func _ovr_meta() -> Dictionary:
	return {"anims": _tables, "item_defaults": _ovr_defaults, "items": _ovr_items}


## Chain-resolved [x, y, rot] for the item previewed in a hand, WITHOUT the
## pos/rot deltas — the base the deltas ride on.
func _base_resolved(hand: String) -> Array:
	var key := _current_item(hand)
	if key != "" and _anim != "" and _tables.has(_anim):
		var e: Variant = Combatant.anchor_entry_for_item(_ovr_meta(), key, _anim, hand, _frame)
		if e is Array and (e as Array).size() >= 2:
			var a := e as Array
			return [int(a[0]), int(a[1]), int(a[2]) if a.size() > 2 else 0]
	return _row(hand)


func _hand_dp(hand: String) -> Vector2i:
	var key := _current_item(hand)
	return Combatant.held_ovr_pos(_ovr_meta(), key, hand) if key != "" else Vector2i.ZERO


func _hand_dr(hand: String) -> int:
	var key := _current_item(hand)
	return int(Combatant.held_ovr_rot(_ovr_meta(), key, hand)) if key != "" else 0


## Effective displayed [x, y, rot] for a hand — what the runtime would render.
## Crosshairs, gumballs, overlays and the glove all follow this.
func _disp_row(hand: String) -> Array:
	var base := _base_resolved(hand)
	if _current_item(hand) == "":
		return base
	var dp := _hand_dp(hand)
	return [int(base[0]) + dp.x, int(base[1]) + dp.y, int(base[2]) + _hand_dr(hand)]


## Tier-3 per-frame override row for the OVR target in a hand (current anim /
## frame, clamped like the runtime), or null when no such table exists.
func _ovr_row(hand: String) -> Variant:
	var entry: Variant = _ovr_items.get(_ovr_target)
	if entry is Dictionary:
		var anims: Variant = (entry as Dictionary).get("anims")
		if anims is Dictionary and (anims as Dictionary).get(_anim) is Dictionary:
			var per := (anims as Dictionary)[_anim] as Dictionary
			if per.get(hand) is Array and not (per[hand] as Array).is_empty():
				var arr := per[hand] as Array
				return arr[clampi(_frame, 0, arr.size() - 1)]
	return null


## Where position/rotation edits for a hand land, given the OVR target:
## "base" = hero tables (no target, or target not previewed in this hand);
## "ovr_table" = the target item's per-frame rows; "delta_hero"/"delta_item"
## = the target's "pos"/"rot" fields (difference from the base row).
func _edit_kind(hand: String) -> String:
	if _ovr_target == "" or _current_item(hand) == "":
		return "base"
	if _ovr_target == "*":
		return "delta_hero"
	if _current_item(hand) != _ovr_target:
		return "base"
	if _ovr_row(hand) != null:
		return "ovr_table"
	return "delta_item"


## While an OVR target is active, base tables are never touched — an edit that
## would fall through to "base" (target not in this hand) is refused instead,
## so a stray drag can't silently corrupt the hero tables.
func _ovr_blocks(kind: String, hand: String) -> bool:
	if kind == "base" and _ovr_target != "":
		_status.text = "OVR: no target in %s hand" % hand.to_upper()
		return true
	return false


## Routes an absolute displayed content-px position into the active edit store.
func _write_pos(hand: String, x: int, y: int) -> void:
	if _ovr_blocks(_edit_kind(hand), hand):
		return
	match _edit_kind(hand):
		"base":
			var r := _row(hand)
			r[0] = x
			r[1] = y
		"ovr_table":
			var r := _ovr_row(hand) as Array
			var dp := _hand_dp(hand)
			r[0] = x - dp.x
			r[1] = y - dp.y
		_:
			var base := _base_resolved(hand)
			_set_target_pos(Vector2i(x - int(base[0]), y - int(base[1])), hand)
	_mark_dirty()
	if _edit_kind(hand).begins_with("delta"):
		_status.text = "delta=ALL frms (CPY=per-frame)"


## Routes an absolute displayed rotation (deg) into the active edit store.
func _write_rot(hand: String, deg: int) -> void:
	if _ovr_blocks(_edit_kind(hand), hand):
		return
	match _edit_kind(hand):
		"base":
			var r := _row(hand)
			r[2] = wrapi(deg, -180, 181)
		"ovr_table":
			var r := _ovr_row(hand) as Array
			r[2] = wrapi(deg - _hand_dr(hand), -180, 181)
		_:
			_set_target_rot(wrapi(deg - int(_base_resolved(hand)[2]), -180, 181), hand)
	_mark_dirty()
	if _edit_kind(hand).begins_with("delta"):
		_status.text = "delta=ALL frms (CPY=per-frame)"


## Override dict the OVR target's pos/rot/anims write into (created on demand).
func _target_dict() -> Dictionary:
	if _ovr_target == "*":
		return _ovr_defaults
	var e: Variant = _ovr_items.get(_ovr_target)
	if not (e is Dictionary):
		e = {}
		_ovr_items[_ovr_target] = e
	return e as Dictionary


## Stores a per-hand override value inside a field that may hold a legacy
## scalar: the scalar is first spread to both hands so the other hand keeps
## its current value, then the edited hand is set (or cleared when zero).
static func _set_hand_field(d: Dictionary, field: String, hand: String,
		value: Variant, clear: bool) -> void:
	var cur: Variant = d.get(field)
	var obj: Dictionary = {}
	if cur is Dictionary:
		obj = cur as Dictionary
	elif cur != null:
		obj = {"main": cur, "off": cur}
	if clear:
		obj.erase(hand)
	else:
		obj[hand] = value
	if obj.is_empty():
		d.erase(field)
	else:
		d[field] = obj


func _set_target_pos(p: Vector2i, hand: String) -> void:
	_set_hand_field(_target_dict(), "pos", hand, [p.x, p.y], p == Vector2i.ZERO)
	_prune_ovr_items()


func _set_target_rot(r: int, hand: String) -> void:
	_set_hand_field(_target_dict(), "rot", hand, r, r == 0)
	_prune_ovr_items()


func _prune_ovr_items() -> void:
	for k in _ovr_items.keys():
		if _ovr_items[k] is Dictionary and (_ovr_items[k] as Dictionary).is_empty():
			_ovr_items.erase(k)


## Hand the OVR target item is previewed in, or "".
func _target_hand() -> String:
	if _current_item("main") == _ovr_target:
		return "main"
	if _current_item("off") == _ovr_target:
		return "off"
	return ""


## Art key the target's flip override belongs under: the _back variant when the
## slot renders behind the body (matches the runtime shown-art rule).
func _ovr_art_key() -> String:
	if _ovr_target == "" or _ovr_target == "*":
		return ""
	var hand := _target_hand()
	if hand != "":
		var raw: Variant = _item_order.get(_ovr_target)
		var order := Combatant.held_order({"order": raw} if raw != null else {}, hand)
		if Combatant.held_layer_z(order, "weapon") < 0 and _item_tex.has(_ovr_target + "_back"):
			return _ovr_target + "_back"
	return _ovr_target


## Dict holding the target's flip override fields, read-only ({} when absent).
func _ovr_flip_dict_read() -> Dictionary:
	if _ovr_target == "*":
		return _ovr_defaults
	var e: Variant = _ovr_items.get(_ovr_art_key())
	return e as Dictionary if e is Dictionary else {}


## Hand a flip/delta edit applies to: the hand holding an item target, else
## the selected hand (hero-defaults target).
func _flip_hand() -> String:
	if _ovr_target != "" and _ovr_target != "*":
		var h := _target_hand()
		if h != "":
			return h
	return _hand


## Cycles a flip override for the edit hand: inherit → ON → off → inherit.
func _cycle_flip(axis: String) -> void:
	if _mode != "hero" or _ovr_target == "":
		return
	var d := _ovr_defaults
	if _ovr_target != "*":
		var key := _ovr_art_key()
		var e: Variant = _ovr_items.get(key)
		if not (e is Dictionary):
			e = {}
			_ovr_items[key] = e
		d = e as Dictionary
	var field := "flip_" + axis
	var hand := _flip_hand()
	var cur: Variant = Combatant.held_hand_value(d.get(field), hand)
	if cur == null:
		_set_hand_field(d, field, hand, true, false)
	elif bool(cur):
		_set_hand_field(d, field, hand, false, false)
	else:
		_set_hand_field(d, field, hand, null, true)
	_prune_ovr_items()
	_sync_ovr_ui()
	_mark_dirty()


## Snapshots the current anim's base rows for the target's previewed hand into
## items.<key>.anims — from then on drags edit those rows per-frame. Copying
## the BASE rows keeps the visual unchanged (deltas keep riding on top).
func _ovr_copy_anims() -> void:
	if _mode != "hero" or _anim == "" or _ovr_target == "" or _ovr_target == "*":
		return
	var hand := _target_hand()
	if hand == "":
		_status.text = "target not previewed"
		return
	var rows: Array = []
	for r in (_tables[_anim][hand] as Array):
		var a := r as Array
		rows.append([int(a[0]), int(a[1]), int(a[2])])
	var d := _target_dict()
	var anims: Dictionary = d.get("anims", {}) as Dictionary
	var per: Dictionary = anims.get(_anim, {}) as Dictionary
	per[hand] = rows
	anims[_anim] = per
	d["anims"] = anims
	_mark_dirty()
	_status.text = "OVR tbl %s/%s" % [_anim, hand]


## Wipes every override the target owns (an item target also drops its _back
## variant's flip entry).
func _ovr_clear() -> void:
	if _mode != "hero" or _ovr_target == "":
		return
	if _ovr_target == "*":
		_ovr_defaults.clear()
	else:
		_ovr_items.erase(_ovr_target)
		_ovr_items.erase(_ovr_target + "_back")
	_sync_ovr_ui()
	_mark_dirty()


## Rebuilds the OVR target picker: none / hero defaults / the previewed items.
func _rebuild_ovr_options() -> void:
	if _ovr_btn == null:
		return
	_ovr_keys.clear()
	_ovr_btn.clear()
	_ovr_btn.add_item("(no ovr)")
	_ovr_keys.append("")
	_ovr_btn.add_item("hero dflt")
	_ovr_keys.append("*")
	for hand in ["main", "off"]:
		var k := _current_item(hand)
		if k != "" and k != STUB_KEY and k not in _ovr_keys:
			_ovr_btn.add_item(k)
			_ovr_keys.append(k)
	var idx := _ovr_keys.find(_ovr_target)
	if idx < 0:
		idx = 0
		_ovr_target = ""
	_ovr_btn.selected = idx
	_sync_ovr_ui()


func _on_ovr_selected(i: int) -> void:
	_ovr_target = _ovr_keys[i]
	# Item target: jump the hand selection to the hand actually holding it, so
	# the gumball the user grabs next edits the target, not the other hand.
	if _ovr_target != "" and _ovr_target != "*":
		var h := _target_hand()
		if h != "":
			_hand = h
	_sync_ovr_ui()
	_update_labels()


## Flip-button captions + enabled states from the target's current overrides.
func _sync_ovr_ui() -> void:
	if _ovr_btn == null:
		return
	var has_target := _ovr_target != ""
	var d := _ovr_flip_dict_read() if has_target else {}
	for pair in [[_ovr_h_btn, "flip_h", "H"], [_ovr_v_btn, "flip_v", "V"]]:
		var b := pair[0] as Button
		b.disabled = not has_target
		var v: Variant = Combatant.held_hand_value(d.get(pair[1]), _flip_hand())
		var tag := "inh"
		if v != null:
			tag = "ON" if bool(v) else "off"
		b.text = "%s·%s" % [pair[2], tag]
	_ovr_copy_btn.disabled = not has_target or _ovr_target == "*"
	_ovr_clear_btn.disabled = not has_target
	if _canvas != null:
		_canvas.queue_redraw()


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
	_hero_list.custom_minimum_size = Vector2(104, 56)
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
	_anim_list.custom_minimum_size = Vector2(104, 76)
	_anim_list.item_selected.connect(_on_anim_selected)
	left.add_child(_anim_list)

	var save_row := HBoxContainer.new()
	var save_btn := _mk_btn("SAVE", _save)
	save_row.add_child(save_btn)
	var all_btn := _mk_btn("ALL FRMS", _apply_all_frames)
	save_row.add_child(all_btn)
	left.add_child(save_row)
	var ovr_row := HBoxContainer.new()
	ovr_row.add_child(_mk_label("OVR"))
	_ovr_btn = OptionButton.new()
	_tune_picker(_ovr_btn)
	_ovr_btn.custom_minimum_size = Vector2(74, 0)
	_ovr_btn.item_selected.connect(_on_ovr_selected)
	ovr_row.add_child(_ovr_btn)
	left.add_child(ovr_row)
	var ovr_flip_row := HBoxContainer.new()
	_ovr_h_btn = _mk_btn("H·inh", func() -> void: _cycle_flip("h"))
	_ovr_v_btn = _mk_btn("V·inh", func() -> void: _cycle_flip("v"))
	ovr_flip_row.add_child(_ovr_h_btn)
	ovr_flip_row.add_child(_ovr_v_btn)
	left.add_child(ovr_flip_row)
	var ovr_btn_row := HBoxContainer.new()
	_ovr_copy_btn = _mk_btn("CPY", _ovr_copy_anims)
	_ovr_clear_btn = _mk_btn("CLR", _ovr_clear)
	ovr_btn_row.add_child(_ovr_copy_btn)
	ovr_btn_row.add_child(_ovr_clear_btn)
	left.add_child(ovr_btn_row)
	_ovr_controls = [ovr_row, ovr_flip_row, ovr_btn_row]
	_status = _mk_label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(104, 0)
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
	_picker_keys.clear()
	for k in _items:
		if k == STUB_KEY or _is_equippable_key(k):
			_picker_keys.append(k)
	var main_lbl := _mk_label("MAIN item")
	right.add_child(main_lbl)
	_main_item_btn = OptionButton.new()
	_tune_picker(_main_item_btn)
	for k in _picker_keys:
		_main_item_btn.add_item(k)
	_main_item_btn.selected = 0
	_main_item_btn.item_selected.connect(func(_i: int) -> void:
		_rebuild_ovr_options()
		_canvas.queue_redraw())
	right.add_child(_main_item_btn)
	var off_lbl := _mk_label("OFF item")
	right.add_child(off_lbl)
	_off_item_btn = OptionButton.new()
	_tune_picker(_off_item_btn)
	_off_item_btn.add_item("(none)")
	for k in _picker_keys:
		_off_item_btn.add_item(k)
	_off_item_btn.selected = 0
	_off_item_btn.item_selected.connect(func(_i: int) -> void:
		_rebuild_ovr_options()
		_canvas.queue_redraw())
	right.add_child(_off_item_btn)
	var alpha_row := HBoxContainer.new()
	alpha_row.add_child(_mk_label("alpha"))
	var alpha_slider := HSlider.new()
	alpha_slider.min_value = 0.1
	alpha_slider.max_value = 1.0
	alpha_slider.step = 0.05
	alpha_slider.value = _item_alpha
	alpha_slider.custom_minimum_size = Vector2(58, 16)
	alpha_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alpha_slider.focus_mode = Control.FOCUS_NONE
	alpha_slider.value_changed.connect(func(v: float) -> void:
		_item_alpha = v
		_canvas.queue_redraw())
	alpha_row.add_child(alpha_slider)
	right.add_child(alpha_row)
	var xray_box := CheckBox.new()
	xray_box.text = "x-ray hero"
	xray_box.focus_mode = Control.FOCUS_NONE
	xray_box.toggled.connect(func(on: bool) -> void:
		_xray = on
		_canvas.queue_redraw())
	right.add_child(xray_box)
	var smear_box := CheckBox.new()
	smear_box.text = "smear prev"
	smear_box.focus_mode = Control.FOCUS_NONE
	smear_box.toggled.connect(func(on: bool) -> void:
		_smear_show = on
		_canvas.queue_redraw())
	right.add_child(smear_box)
	var glove_row := HBoxContainer.new()
	var glove_box := CheckBox.new()
	glove_box.text = "glv"
	glove_box.button_pressed = true
	glove_box.focus_mode = Control.FOCUS_NONE
	glove_box.toggled.connect(func(on: bool) -> void:
		_glove_show = on
		_canvas.queue_redraw())
	glove_row.add_child(glove_box)
	_glove_edit_btn = _mk_btn("EDIT", _toggle_glove_edit)
	glove_row.add_child(_glove_edit_btn)
	right.add_child(glove_row)
	var glove_reset := _mk_btn("RESET GLOVE", _reset_glove)
	right.add_child(glove_reset)
	_pickers = [main_lbl, _main_item_btn, off_lbl, _off_item_btn,
			alpha_row, xray_box, smear_box, glove_row, glove_reset, all_btn]
	var flip_lbl := _mk_label("FLIP art")
	right.add_child(flip_lbl)
	var flip_row := HBoxContainer.new()
	_flip_h_chk = CheckBox.new()
	_flip_h_chk.text = "H"
	_flip_h_chk.focus_mode = Control.FOCUS_NONE
	_flip_h_chk.toggled.connect(_on_flip_toggled.bind("h"))
	flip_row.add_child(_flip_h_chk)
	_flip_v_chk = CheckBox.new()
	_flip_v_chk.text = "V"
	_flip_v_chk.focus_mode = Control.FOCUS_NONE
	_flip_v_chk.toggled.connect(_on_flip_toggled.bind("v"))
	flip_row.add_child(_flip_v_chk)
	right.add_child(flip_row)
	var order_hint := _mk_label("ORDER  L=back R=top")
	right.add_child(order_hint)
	var main_o_lbl := _mk_label("MAIN")
	right.add_child(main_o_lbl)
	_glove_chk_main = _mk_glove_chk("main")
	right.add_child(_glove_chk_main)
	_strip_main = _mk_strip("main")
	right.add_child(_strip_main)
	var off_o_lbl := _mk_label("OFF")
	right.add_child(off_o_lbl)
	_glove_chk_off = _mk_glove_chk("off")
	right.add_child(_glove_chk_off)
	_strip_off = _mk_strip("off")
	right.add_child(_strip_off)
	_item_only = [flip_lbl, flip_row, order_hint, main_o_lbl, _glove_chk_main,
			_strip_main, off_o_lbl, _glove_chk_off, _strip_off]
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


# Real equipment keys only — "_"-prefixed shared art and back variants are
# editable ITEMS entries but never picker choices.
static func _is_equippable_key(k: String) -> bool:
	return not k.begins_with("_") and not k.ends_with("_back")


# Fixed width + clipped text so long keys can't push the right column past
# the 640px window edge (fit_to_longest_item grows with content).
func _tune_picker(b: OptionButton) -> void:
	b.fit_to_longest_item = false
	b.clip_text = true
	b.custom_minimum_size = Vector2(96, 0)
	b.focus_mode = Control.FOCUS_NONE


func _mk_glove_chk(hand: String) -> CheckBox:
	var b := CheckBox.new()
	b.text = "glove"
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(_on_glove_token_toggled.bind(hand))
	return b


func _mk_strip(hand: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(96, CHIP_H + 4)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw_strip.bind(c, hand))
	c.gui_input.connect(_strip_input.bind(hand, c))
	return c


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
	if not hero_mode and _glove_edit:
		_toggle_glove_edit()
	_hero_list.visible = hero_mode
	_anim_list.visible = hero_mode
	_anims_lbl.visible = hero_mode
	_item_list.visible = not hero_mode
	for c in _pickers:
		c.visible = hero_mode
	for c in _item_only:
		c.visible = not hero_mode
	for c in _hero_only_btns:
		c.visible = hero_mode
	for c in _ovr_controls:
		c.visible = hero_mode
	_mode_hero_btn.modulate = Color(1, 1, 1) if hero_mode else Color(0.55, 0.55, 0.55)
	_mode_item_btn.modulate = Color(0.55, 0.55, 0.55) if hero_mode else Color(1, 1, 1)
	if not hero_mode:
		_flip = false
		if _item_sel == "" and _item_list.item_count > 0:
			_item_list.select(0)
			_item_sel = _item_list.get_item_text(0)
		_sync_order_ui()
		_zoom = 10.0
	else:
		_zoom = 5.0
		_preview_edited_item()
		_rebuild_ovr_options()
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


func _on_item_selected(i: int) -> void:
	_item_sel = _item_list.get_item_text(i)
	_sync_order_ui()
	_center_view()
	_update_labels()
	_canvas.queue_redraw()


## On entering PLAYER mode, show the item just edited in ITEMS mode in the MAIN
## hand — unless it is already previewed in a hand — so grip/flip/order tweaks
## are visible on the hero without hunting through the MAIN picker.
func _preview_edited_item() -> void:
	var idx := _picker_keys.find(_item_sel)
	if idx < 0:
		return
	var main_key := _picker_keys[_main_item_btn.selected]
	var off_key := "" if _off_item_btn.selected == 0 else _picker_keys[_off_item_btn.selected - 1]
	if main_key != _item_sel and off_key != _item_sel:
		_main_item_btn.selected = idx


# ── Draw-order editing (chip strip) ───────────────────────────────────────────

static func _order_hand_str(raw: Variant, hand: String) -> String:
	if raw is String:
		return raw
	if raw is Dictionary:
		return str((raw as Dictionary).get(hand, ""))
	return ""


## Minimal raw form: both default → null (field omitted); same → string;
## else object with only the non-default hands.
static func _make_order_raw(main_s: String, off_s: String) -> Variant:
	if main_s == "" and off_s == "":
		return null
	if main_s == off_s:
		return main_s
	var d := {}
	if main_s != "":
		d["main"] = main_s
	if off_s != "":
		d["off"] = off_s
	return d


## Default token order collapses to "" (field omitted); anything else joins.
static func _tokens_to_str(tokens: Array) -> String:
	return "" if tokens == DEFAULT_TOKENS else ";".join(PackedStringArray(tokens))


static func _token_abbr(tok: String) -> String:
	return {"hero": "H", "weapon": "W", "hand": "G"}.get(tok, "?")


func _token_color(tok: String) -> Color:
	match tok:
		"hero": return COL_HERO
		"weapon": return COL_WEAPON
		"hand": return COL_GLOVE
	return Color.GRAY


## Rebuilds the editable token lists + glove checkboxes from the selected
## item's stored order (default hero;weapon;hand when unset).
func _sync_order_ui() -> void:
	var raw: Variant = _item_order.get(_item_sel)
	var meta := {"order": raw} if raw != null else {}
	for hand in ["main", "off"]:
		_edit_tokens[hand] = Combatant.held_order(meta, hand).duplicate()
	_glove_chk_main.set_pressed_no_signal("hand" in _edit_tokens["main"])
	_glove_chk_off.set_pressed_no_signal("hand" in _edit_tokens["off"])
	_flip_h_chk.set_pressed_no_signal(bool(_item_fliph.get(_item_sel, false)))
	_flip_v_chk.set_pressed_no_signal(bool(_item_flipv.get(_item_sel, false)))
	if _strip_main != null:
		_strip_main.queue_redraw()
		_strip_off.queue_redraw()


## Serializes both hands' token lists back into _item_order and marks dirty.
func _commit_order() -> void:
	if _item_sel == "":
		return
	_item_order[_item_sel] = _make_order_raw(
			_tokens_to_str(_edit_tokens["main"]), _tokens_to_str(_edit_tokens["off"]))
	_mark_dirty()
	if _strip_main != null:
		_strip_main.queue_redraw()
		_strip_off.queue_redraw()


func _on_glove_token_toggled(on: bool, hand: String) -> void:
	if _mode != "item" or _item_sel == "":
		return
	var toks: Array = _edit_tokens[hand]
	if on and "hand" not in toks:
		toks.append("hand")
	elif not on:
		toks.erase("hand")
	_commit_order()


func _on_flip_toggled(on: bool, axis: String) -> void:
	if _mode != "item" or _item_sel == "":
		return
	if axis == "h":
		_item_fliph[_item_sel] = on
	else:
		_item_flipv[_item_sel] = on
	_mark_dirty()
	_canvas.queue_redraw()


func _chip_x(i: int) -> float:
	return i * (CHIP_W + CHIP_GAP)


## Chip index under a strip-local x, or -1.
func _chip_at(hand: String, x: float) -> int:
	var n: int = (_edit_tokens[hand] as Array).size()
	for i in n:
		if x >= _chip_x(i) and x < _chip_x(i) + CHIP_W:
			return i
	return -1


## Insertion slot (0..n-1) nearest a strip-local x.
func _chip_slot(hand: String, x: float) -> int:
	var n: int = (_edit_tokens[hand] as Array).size()
	return clampi(int(floor(x / (CHIP_W + CHIP_GAP) + 0.5)), 0, maxi(0, n - 1))


func _move_token(hand: String, from: int, to: int) -> void:
	var toks: Array = _edit_tokens[hand]
	if from < 0 or from >= toks.size() or from == to:
		return
	var t: Variant = toks[from]
	toks.remove_at(from)
	toks.insert(clampi(to, 0, toks.size()), t)
	_commit_order()


func _draw_strip(c: Control, hand: String) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.25))
	var toks: Array = _edit_tokens[hand]
	var font := ThemeDB.fallback_font
	var dragging_i: int = int(_chip_drag["from"]) if _chip_drag["hand"] == hand else -1
	for i in toks.size():
		var tok := String(toks[i])
		var is_drag: bool = i == dragging_i
		var x: float = (float(_chip_drag["x"]) - CHIP_W / 2.0) if is_drag else _chip_x(i)
		var rect := Rect2(x, 2, CHIP_W, CHIP_H)
		c.draw_rect(rect, Color(_token_color(tok), 1.0 if is_drag else 0.85))
		c.draw_rect(rect, Color.WHITE if is_drag else Color(0, 0, 0, 0.6), false, 1.0)
		c.draw_string(font, rect.position + Vector2(9, 14), _token_abbr(tok),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)


func _strip_input(ev: InputEvent, hand: String, c: Control) -> void:
	if _item_sel == "":
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			var i := _chip_at(hand, mb.position.x)
			if i >= 0:
				_chip_drag = {"hand": hand, "from": i, "x": mb.position.x}
				c.queue_redraw()
		elif _chip_drag["hand"] == hand:
			_move_token(hand, int(_chip_drag["from"]), _chip_slot(hand, mb.position.x))
			_chip_drag = {"hand": "", "from": -1, "x": 0.0}
			c.queue_redraw()
	elif ev is InputEventMouseMotion and _chip_drag["hand"] == hand:
		_chip_drag["x"] = (ev as InputEventMouseMotion).position.x
		c.queue_redraw()


func _toggle_glove_edit() -> void:
	if _mode != "hero":
		return
	_glove_edit = not _glove_edit
	_glove_edit_btn.modulate = COL_GLOVE if _glove_edit else Color(1, 1, 1)
	_drag_mode = ""
	_update_labels()
	_canvas.queue_redraw()


## Glove back to the weapon's exact pose: on the hand anchor (offset 0), same
## angle as the weapon (rotation delta 0).
func _reset_glove() -> void:
	if _mode != "hero":
		return
	_glove_off[_hand] = Vector2i.ZERO
	_glove_rot[_hand] = 0
	_mark_dirty()


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
			var ddx := -dx if bool(_item_fliph.get(_item_sel, false)) else dx
			var ddy := -dy if bool(_item_flipv.get(_item_sel, false)) else dy
			_item_grip[_item_sel] = g + Vector2i(ddx, ddy)
			_mark_dirty()
		return
	var d := _disp_row(_hand)
	_write_pos(_hand, int(d[0]) + dx, int(d[1]) + dy)


func _rotate_by(deg: int) -> void:
	if _mode != "hero":
		return
	_write_rot(_hand, int(_disp_row(_hand)[2]) + deg)


## Copies the selected hand's current [x, y, rot] onto every frame of the
## current animation — "save as default" for quickly blocking an anim out.
## With an OVR per-frame table active it blankets the override rows instead;
## delta targets are already all-frames, so there is nothing to copy.
func _apply_all_frames() -> void:
	if _mode != "hero" or _anim == "":
		return
	if _ovr_blocks(_edit_kind(_hand), _hand):
		return
	match _edit_kind(_hand):
		"base":
			var cur := _row(_hand)
			for r in (_tables[_anim][_hand] as Array):
				var a := r as Array
				a[0] = int(cur[0])
				a[1] = int(cur[1])
				a[2] = int(cur[2])
			_mark_dirty()
			_status.text = "%s > all %s" % [_hand.to_upper(), _anim]
		"ovr_table":
			var cur := _ovr_row(_hand) as Array
			var anims := (_ovr_items[_ovr_target] as Dictionary)["anims"] as Dictionary
			for r in ((anims[_anim] as Dictionary)[_hand] as Array):
				var a := r as Array
				a[0] = int(cur[0])
				a[1] = int(cur[1])
				a[2] = int(cur[2])
			_mark_dirty()
			_status.text = "OVR %s > all %s" % [_hand.to_upper(), _anim]
		_:
			_status.text = "delta is all-frames"


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
			var flip := ""
			if bool(_item_fliph.get(_item_sel, false)):
				flip += " flipH"
			if bool(_item_flipv.get(_item_sel, false)):
				flip += " flipV"
			var raw: Variant = _item_order.get(_item_sel)
			_readout.text = "%s\nGRIP %d,%d%s%s\nM %s\nO %s" % [_item_sel, g.x, g.y,
					planted, flip, _abbr_order(_order_hand_str(raw, "main")),
					_abbr_order(_order_hand_str(raw, "off"))]
		return
	if _anim == "":
		_frame_lbl.text = "frm -/-"
		_readout.text = ""
		return
	_frame_lbl.text = "frm %d/%d" % [_frame + 1, _frames.get_frame_count(_anim)]
	var m := _disp_row("main")
	var o := _disp_row("off")
	var gv: Vector2i = _glove_off[_hand]
	var edit := " EDIT" if _glove_edit else ""
	_readout.text = "hand: %s\nMAIN %d,%d r%d\nOFF %d,%d r%d\nGLV %+d,%+d r%+d%s%s" % [
		_hand.to_upper(), m[0], m[1], m[2], o[0], o[1], o[2],
		gv.x, gv.y, int(_glove_rot[_hand]), edit, _ovr_readout()]


## Extra readout line while an OVR target is active: target, its stored
## deltas, and TBL when a per-frame override table serves the selected hand.
func _ovr_readout() -> String:
	if _ovr_target == "":
		return ""
	var tgt := "hero" if _ovr_target == "*" else _ovr_target.left(12)
	var td := _ovr_defaults if _ovr_target == "*" \
			else (_ovr_items.get(_ovr_target, {}) as Dictionary)
	var hand := _flip_hand()
	var p := Combatant.json_v2i(Combatant.held_hand_value(td.get("pos"), hand), Vector2i.ZERO)
	var rv: Variant = Combatant.held_hand_value(td.get("rot"), hand)
	var rr := int(rv) if (rv is int or rv is float) else 0
	var tbl := " TBL" if _ovr_row(_hand) != null else ""
	return "\nOVR %s %s\ndP%+d,%+d dR%+d%s" % [tgt, hand.to_upper(), p.x, p.y, rr, tbl]


static func _abbr_order(s: String) -> String:
	if s == "":
		return "default"
	return s.replace("hero", "H").replace("weapon", "W").replace("hand", "G")


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
	var r := _disp_row(hand)
	return _to_screen(Vector2(int(r[0]) + 0.5, int(r[1]) + 0.5))


## Mirrors a grip point per the selected item's flip flags (its own inverse):
## maps between stored (unflipped-sheet) coords and displayed content coords.
func _flip_grip(v: Vector2i, size: Vector2) -> Vector2i:
	var x := (int(size.x) - 1 - v.x) if bool(_item_fliph.get(_item_sel, false)) else v.x
	var y := (int(size.y) - 1 - v.y) if bool(_item_flipv.get(_item_sel, false)) else v.y
	return Vector2i(x, y)


## Stores the grip from a mouse position on the (possibly mirrored) item canvas,
## un-mirroring so the stored value stays in unflipped-sheet coords.
func _set_grip_from_mouse(screen_pos: Vector2) -> void:
	var p := _from_screen(screen_pos)
	var size := (_item_tex[_item_sel] as Texture2D).get_size()
	_item_grip[_item_sel] = _flip_grip(Vector2i(int(floor(p.x)), int(floor(p.y))), size)
	_mark_dirty()


func _grip_screen() -> Vector2:
	var size := (_item_tex[_item_sel] as Texture2D).get_size()
	var disp := _flip_grip(_item_grip[_item_sel], size)
	return _to_screen(Vector2(disp) + Vector2(0.5, 0.5))


func _knob_screen() -> Vector2:
	var r := _disp_row(_hand)
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
	_draw_held_pass(true)
	# X-ray dims the hero so items drawn behind the body (off-hand shield etc.)
	# stay visible for authoring; normal preview is fully opaque.
	_canvas.draw_texture_rect_region(base, dst, src,
			Color(1, 1, 1, 0.28 if _xray else 1.0))
	_draw_held_pass(false)
	_draw_grid(fs)

	_draw_crosshair(_anchor_screen("main"), COL_MAIN, _hand == "main")
	_draw_crosshair(_anchor_screen("off"), COL_OFF, _hand == "off")
	_draw_small_cross(_anchor_screen("main"), COL_GRIP)
	_draw_small_cross(_anchor_screen("off"), COL_GRIP)
	if _glove_show and not _glove_edit:
		_draw_crosshair(_glove_screen(_hand), COL_GLOVE, false)
	var a := _anchor_screen(_hand)
	_canvas.draw_arc(a, 34.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.0)
	var k := _knob_screen()
	_canvas.draw_line(a, k, Color(1, 1, 1, 0.35))
	_canvas.draw_circle(k, 5.0, COL_GRIP if _drag_mode == "rot" else Color(1, 1, 1, 0.9))
	# Glove gumball on top: bigger ring so it stays grabbable over the weapon's.
	if _glove_edit:
		var gc := _glove_screen(_hand)
		_canvas.draw_arc(gc, GLOVE_RING, 0, TAU, 56, Color(COL_GLOVE, 0.7), 1.5)
		var gk := _glove_knob_screen(_hand)
		_canvas.draw_line(gc, gk, Color(COL_GLOVE, 0.6))
		_canvas.draw_circle(gk, 6.0,
				COL_GLOVE if _drag_mode == "glove_rot" else Color(1, 1, 1, 0.9))
		_draw_crosshair(gc, COL_GLOVE, true)


func _draw_item_mode() -> void:
	if _item_sel == "":
		return
	var tex: Texture2D = _item_tex[_item_sel]
	var fs := tex.get_size()
	# Mirror the art live per the flip flags via negative transform scale, so
	# the toggle shows here immediately (not only in the PLAYER preview). The
	# scale mirrors around the flipped edge, keeping the art on the same span.
	var fh := bool(_item_fliph.get(_item_sel, false))
	var fv := bool(_item_flipv.get(_item_sel, false))
	var origin := _to_screen(Vector2(fs.x if fh else 0.0, fs.y if fv else 0.0))
	_canvas.draw_set_transform(origin, 0.0,
			Vector2((-1.0 if fh else 1.0) * _zoom, (-1.0 if fv else 1.0) * _zoom))
	_canvas.draw_texture_rect(tex, Rect2(Vector2.ZERO, fs), false)
	_canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
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
		return _picker_keys[_main_item_btn.selected]
	if _off_item_btn.selected == 0:
		return ""
	return _picker_keys[_off_item_btn.selected - 1]


## Draws both hands' overlays on one side of the hero (behind or in front),
## honouring each item's order tokens — mirrors the runtime layering exactly,
## including the _back art swap for behind-the-body slots.
func _draw_held_pass(behind: bool) -> void:
	for hand in ["main", "off"]:
		var key := _current_item(hand)
		if key == "" or not _item_tex.has(key):
			continue
		var raw: Variant = _item_order.get(key)
		var order := Combatant.held_order({"order": raw} if raw != null else {}, hand)
		var wz := Combatant.held_layer_z(order, "weapon")
		if (wz < 0) == behind:
			var draw_key := key
			if wz < 0 and _item_tex.has(key + "_back"):
				draw_key = key + "_back"
			# flip resolved through the per-hero override chain, keyed by the art
			# actually shown, so a _back variant flips independently of the front
			# (matches Combatant._bind_held).
			var ifh := Combatant.held_flip(_ovr_meta(), draw_key,
					{"flip_h": _item_fliph.get(draw_key, false)}, "flip_h", hand)
			var ifv := Combatant.held_flip(_ovr_meta(), draw_key,
					{"flip_v": _item_flipv.get(draw_key, false)}, "flip_v", hand)
			var smear_tex := _smear_texture(key, draw_key, hand, ifh, ifv)
			if smear_tex != null:
				# Swing frame: the smear replaces the weapon (crunch style). A
				# faint ghost keeps the anchor readable under it while tuning.
				_draw_overlay(_item_tex[draw_key], _item_grip[draw_key], hand,
						Vector2.ZERO, _item_alpha * 0.25, 0.0, ifh, ifv)
				_draw_smear(smear_tex, hand)
			else:
				_draw_overlay(_item_tex[draw_key], _item_grip[draw_key], hand,
						Vector2.ZERO, _item_alpha, 0.0, ifh, ifv)
		if _glove_show and "hand" in order and _item_tex.has("_glove"):
			if (Combatant.held_layer_z(order, "hand") < 0) == behind:
				_draw_overlay(_item_tex["_glove"], _item_grip["_glove"], hand,
						Vector2(_glove_off[hand]), 1.0, float(_glove_rot[hand]))


## `extra` = content-px offset from the hand anchor (unflipped terms; the
## screen mapping applies the mirror, matching Combatant.held_glove_offset).
## `rot_extra` = extra degrees added to the weapon angle (glove rotation delta).
## `flip_h`/`flip_v` = per-item art mirror, stacked on the hero flip. The grip
## sits at the transform origin and negative scale mirrors around it — same
## result as Sprite2D.flip_h/flip_v + held_slot_offset at runtime.
func _draw_overlay(tex: Texture2D, grip: Vector2i, hand: String, extra: Vector2,
		alpha: float, rot_extra: float = 0.0, flip_h: bool = false, flip_v: bool = false) -> void:
	var r := _disp_row(hand)
	var rot := deg_to_rad(Combatant.held_rotation(float(r[2]) + rot_extra, _flip))
	var anchor := _to_screen(Vector2(int(r[0]) + 0.5, int(r[1]) + 0.5) + extra)
	var sx := -1.0 if _flip != flip_h else 1.0
	var sy := -1.0 if flip_v else 1.0
	_canvas.draw_set_transform(anchor, rot, Vector2(sx * _zoom, sy * _zoom))
	_canvas.draw_texture_rect(tex, Rect2(Vector2(-grip.x, -grip.y), tex.get_size()),
			false, Color(1, 1, 1, alpha))
	_canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Baked smear texture for a hand's current frame, or null when the preview is
## off or the frame doesn't swing past the threshold. Mirrors the runtime
## exactly: live tables + override blocks resolve arc and params, the shown art
## with its item flips applied feeds the bake; cache keys carry grip and flips,
## so live edits re-bake automatically.
func _smear_texture(key: String, draw_key: String, hand: String,
		ifh: bool, ifv: bool) -> ImageTexture:
	if not _smear_show or _anim == "" or not _tables.has(_anim):
		return null
	var params := Combatant.smear_params(_ovr_meta(), key, {"smear": _item_smear.get(key)})
	var arc: Variant = Combatant.smear_arc(_ovr_meta(), key, _anim, hand, _frame, params)
	if arc == null:
		return null
	var img: Image = (_item_tex[draw_key] as Texture2D).get_image()
	if img == null:
		return null
	var grip: Vector2i = _item_grip[draw_key]
	if ifh:
		img.flip_x()
		grip.x = img.get_width() - 1 - grip.x
	if ifv:
		img.flip_y()
		grip.y = img.get_height() - 1 - grip.y
	var a := arc as Dictionary
	return SmearGen.texture_for(
			draw_key + ("+fh" if ifh else "") + ("+fv" if ifv else ""),
			img, grip, float(a["from"]), float(a["to"]), params)


## Smear canvases centre on the grip pivot and never rotate — only the facing
## mirror applies (matches Combatant._update_smear).
func _draw_smear(tex: ImageTexture, hand: String) -> void:
	var r := _disp_row(hand)
	var anchor := _to_screen(Vector2(int(r[0]) + 0.5, int(r[1]) + 0.5))
	var sx := -1.0 if _flip else 1.0
	_canvas.draw_set_transform(anchor, 0.0, Vector2(sx * _zoom, _zoom))
	var half := Vector2(tex.get_size()) / 2.0
	_canvas.draw_texture_rect(tex, Rect2(-half, Vector2(tex.get_size())), false,
			Color(1, 1, 1, _item_alpha))
	_canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _glove_screen(hand: String) -> Vector2:
	var r := _disp_row(hand)
	return _to_screen(Vector2(int(r[0]) + 0.5, int(r[1]) + 0.5) + Vector2(_glove_off[hand]))


## Glove rotation-gumball knob: weapon angle + glove delta, on a bigger radius
## than the weapon's so it stays grabbable where the two gumballs overlap.
const GLOVE_RING := 44.0

func _glove_knob_screen(hand: String) -> Vector2:
	var deg := float(_disp_row(hand)[2]) + int(_glove_rot[hand])
	var rot := deg_to_rad(Combatant.held_rotation(deg, _flip))
	return _glove_screen(hand) + Vector2(sin(rot), -cos(rot)) * GLOVE_RING


## Stores the glove offset (content px, unflipped terms) from a screen mouse
## position: mapped-back point minus the hand anchor.
func _set_glove_from_mouse(screen_pos: Vector2) -> void:
	var p := _from_screen(screen_pos)
	var r := _disp_row(_hand)
	_glove_off[_hand] = Vector2i(int(floor(p.x)) - int(r[0]), int(floor(p.y)) - int(r[1]))
	_mark_dirty()


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
				_write_pos(_drag_mode, int(floor(p.x)), int(floor(p.y)))
			"grip":
				_set_grip_from_mouse(mm.position)
			"glove":
				_set_glove_from_mouse(mm.position)
			"glove_rot":
				var d := mm.position - _glove_screen(_hand)
				var deg := rad_to_deg(atan2(d.x, -d.y))
				deg = Combatant.held_rotation(deg, _flip)
				var snap := 1 if Input.is_key_pressed(KEY_SHIFT) else 5
				# stored value is the delta from the weapon's current angle
				var delta := int(round(deg / snap)) * snap - int(_disp_row(_hand)[2])
				_glove_rot[_hand] = wrapi(delta, -180, 181)
				_mark_dirty()
			"rot":
				var d := mm.position - _anchor_screen(_hand)
				var deg := rad_to_deg(atan2(d.x, -d.y))
				deg = Combatant.held_rotation(deg, _flip)
				var snap := 1 if Input.is_key_pressed(KEY_SHIFT) else 5
				_write_rot(_hand, int(round(deg / snap)) * snap)
			"pan":
				_pan = _pan_start - (mm.position - _pan_mouse) / _zoom
				_canvas.queue_redraw()


func _start_drag(pos: Vector2) -> void:
	if _mode == "item":
		if _item_sel == "":
			return
		_set_grip_from_mouse(pos)
		_drag_mode = "grip"
		return
	if _anim == "":
		return
	# Glove-edit mode: LMB drives the glove gumball only (knob rotates, centre
	# moves); the other hand's crosshair still switches hands.
	if _glove_edit:
		if pos.distance_to(_glove_knob_screen(_hand)) <= 12.0:
			_drag_mode = "glove_rot"
			return
		if pos.distance_to(_glove_screen(_hand)) <= 16.0:
			_drag_mode = "glove"
			_set_glove_from_mouse(pos)
			return
		var other := "off" if _hand == "main" else "main"
		if pos.distance_to(_anchor_screen(other)) <= 12.0:
			_hand = other
			_update_labels()
			_canvas.queue_redraw()
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
	# Baked smears key on grip/tables/params — dump the cache so anything an
	# edit invalidated is regenerated from the saved state.
	SmearGen.clear_cache()


func _save_item() -> void:
	if _item_sel == "":
		return
	var g: Vector2i = _item_grip[_item_sel]
	var s := "{\n\t\"grip\": [%d, %d]" % [g.x, g.y]
	if bool(_item_planted.get(_item_sel, false)):
		s += ",\n\t\"planted\": true"
	if bool(_item_fliph.get(_item_sel, false)):
		s += ",\n\t\"flip_h\": true"
	if bool(_item_flipv.get(_item_sel, false)):
		s += ",\n\t\"flip_v\": true"
	var raw: Variant = _item_order.get(_item_sel)
	if raw is String and raw != "":
		s += ",\n\t\"order\": \"%s\"" % raw
	elif raw is Dictionary and not (raw as Dictionary).is_empty():
		var parts: Array[String] = []
		for h in ["main", "off"]:
			if (raw as Dictionary).has(h):
				parts.append("\"%s\": \"%s\"" % [h, (raw as Dictionary)[h]])
		s += ",\n\t\"order\": { %s }" % ", ".join(parts)
	# "smear" is authored by hand in the json (editor only previews it) — carry
	# it through the regenerating save instead of dropping it.
	var sm: Variant = _item_smear.get(_item_sel)
	if sm != null:
		s += ",\n\t\"smear\": %s" % JSON.stringify(sm)
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
	if _glove_off["main"] != Vector2i.ZERO or _glove_off["off"] != Vector2i.ZERO \
			or _glove_rot["main"] != 0 or _glove_rot["off"] != 0:
		s += "\t\"glove_off\": { \"main\": [%d, %d, %d], \"off\": [%d, %d, %d] },\n" % [
				_glove_off["main"].x, _glove_off["main"].y, _glove_rot["main"],
				_glove_off["off"].x, _glove_off["off"].y, _glove_rot["off"]]
	if _manifest.has("idle_bob"):
		var bob_strs: Array[String] = []
		for v in (_manifest["idle_bob"] as Array):
			bob_strs.append(str(int(v)))
		s += "\t\"idle_bob\": [%s],\n" % ", ".join(bob_strs)
	s += _fmt_ovr_defaults()
	s += _fmt_ovr_items()
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


## "item_defaults" manifest block, or "" when the hero authors none.
func _fmt_ovr_defaults() -> String:
	var body := _fmt_ovr_fields(_ovr_defaults, "\t\t")
	if body == "":
		return ""
	return "\t\"item_defaults\": {\n%s\n\t},\n" % body


## "items" manifest block (sorted keys, empty entries dropped), or "".
func _fmt_ovr_items() -> String:
	if _ovr_items.is_empty():
		return ""
	var entries: Array[String] = []
	var keys := _ovr_items.keys()
	keys.sort()
	for k in keys:
		if not (_ovr_items[k] is Dictionary):
			continue
		var body := _fmt_ovr_fields(_ovr_items[k] as Dictionary, "\t\t\t")
		if body != "":
			entries.append("\t\t\"%s\": {\n%s\n\t\t}" % [k, body])
	if entries.is_empty():
		return ""
	return "\t\"items\": {\n%s\n\t},\n" % ",\n".join(entries)


## Scalar formatters — "" = value carries nothing worth saving (inherit).
static func _fmt_flip_scalar(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	return ""


static func _fmt_rot_scalar(v: Variant) -> String:
	if (v is int or v is float) and int(v) != 0:
		return str(int(v))
	return ""


static func _fmt_pos_scalar(v: Variant) -> String:
	if v is Array and (v as Array).size() == 2 \
			and not (int(v[0]) == 0 and int(v[1]) == 0):
		return "[%d, %d]" % [int(v[0]), int(v[1])]
	return ""


## Formats a field that may be a scalar (both hands) or a per-hand object;
## empty hands are dropped, an empty object collapses to "".
static func _fmt_hand_field(v: Variant, fn: Callable) -> String:
	if v is Dictionary:
		var hp: Array[String] = []
		for hand in ["main", "off"]:
			var s: String = fn.call((v as Dictionary).get(hand))
			if s != "":
				hp.append("\"%s\": %s" % [hand, s])
		if hp.is_empty():
			return ""
		return "{ %s }" % ", ".join(hp)
	if v == null:
		return ""
	return fn.call(v)


## Serializes one override dict's known fields (flip_h/flip_v/rot/pos/anims);
## zero deltas and empty tables are omitted — absent = inherit. flip/rot/pos
## may each be scalar or per-hand {"main": ..., "off": ...}.
func _fmt_ovr_fields(d: Dictionary, ind: String) -> String:
	var parts: Array[String] = []
	var fmts := {"flip_h": _fmt_flip_scalar, "flip_v": _fmt_flip_scalar,
			"rot": _fmt_rot_scalar, "pos": _fmt_pos_scalar}
	for f in ["flip_h", "flip_v", "rot", "pos"]:
		var s := _fmt_hand_field(d.get(f), fmts[f] as Callable)
		if s != "":
			parts.append("%s\"%s\": %s" % [ind, f, s])
	# Hand-authored smear params ride the override chain too — preserve them
	# verbatim through the regenerating save.
	var sm: Variant = d.get("smear")
	if sm != null:
		parts.append("%s\"smear\": %s" % [ind, JSON.stringify(sm)])
	var anims: Variant = d.get("anims")
	if anims is Dictionary and not (anims as Dictionary).is_empty():
		var ablocks: Array[String] = []
		for anim in ANIMS:
			if not (anims as Dictionary).get(anim) is Dictionary:
				continue
			var per := (anims as Dictionary)[anim] as Dictionary
			var hparts: Array[String] = []
			for hand in ["main", "off"]:
				if per.get(hand) is Array and not (per[hand] as Array).is_empty():
					hparts.append("%s\t\t\"%s\": [%s]" % [ind, hand, _fmt_rows(per[hand] as Array)])
			if not hparts.is_empty():
				ablocks.append("%s\t\"%s\": {\n%s\n%s\t}" % [ind, anim, ",\n".join(hparts), ind])
		if not ablocks.is_empty():
			parts.append("%s\"anims\": {\n%s\n%s}" % [ind, ",\n".join(ablocks), ind])
	return ",\n".join(parts)
