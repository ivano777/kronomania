extends Control
class_name CoreMedallion

## Central "core" widget for the constellation screen — a drawn faceted gold gem
## showing the player's Tier (big Roman numeral), HP capacity (crimson wound pips),
## and unspent points (♦ badge). Replaces the former bare `_heart_label`.
## Pure presentation; holds no game state — fed via set_state().

const GOLD      := Color(0.85, 0.70, 0.20)          # core token colour
const GOLD_DIM  := Color(0.85, 0.70, 0.20, 0.55)
const GEM_FILL  := Color(0.12, 0.10, 0.05, 0.92)     # dark amber, reads on the vignette
const GEM_FACET := Color(0.85, 0.70, 0.20, 0.18)
const HP_FILL   := Color(0.80, 0.25, 0.22)           # crimson, matches dominion token
const PIP_PX    := 6

var _numeral: Label
var _pip_row: HBoxContainer
var _badge: Label
var _hp: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Centred content stack painted over the drawn gem (children render above _draw()).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	var caption := Label.new()
	caption.text = "TIER"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", GOLD_DIM)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(caption)

	_numeral = Label.new()
	_numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numeral.add_theme_font_size_override("font_size", 32)
	_numeral.add_theme_color_override("font_color", GOLD)
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_numeral)

	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_row.add_theme_constant_override("separation", 1)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_pip_row)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 16)
	_badge.add_theme_color_override("font_color", GOLD)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	vbox.add_child(_badge)


## Rebuild the readout: tier drives the numeral, hp the pip count, points the badge.
func set_state(tier: int, hp: int, points: int) -> void:
	if _numeral == null:
		return  # add_child not yet run _ready(); the scene re-calls set_state in _refresh
	_numeral.text = tier_to_roman(tier)
	if hp != _hp:
		_hp = hp
		_rebuild_pips(hp)
	if points > 0:
		_badge.text = "♦ %d" % points
		_badge.visible = true
	else:
		_badge.visible = false


func _rebuild_pips(hp: int) -> void:
	for c in _pip_row.get_children():
		c.queue_free()
	for _i in maxi(hp, 0):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(PIP_PX, PIP_PX)
		pip.color = HP_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)


## Faceted gem silhouette: pointy-top hexagon, dark fill, gold rim + facet spokes.
func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)

	draw_colored_polygon(pts, GEM_FILL)
	for p in pts:
		draw_line(c, p, GEM_FACET, 1.0, true)  # facet spokes

	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, GOLD, 2.0, true)

	var inner := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * PI / 3.0
		inner.append(c + Vector2(cos(a), sin(a)) * (r - 5.0))
	inner.append(inner[0])
	draw_polyline(inner, GOLD_DIM, 1.0, true)


## Convert a tier number to a Roman numeral (I..IV expected; MAX_TIER = 4).
static func tier_to_roman(t: int) -> String:
	match t:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
	return str(t)
