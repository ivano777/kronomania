extends Control

## Static celestial backdrop for the constellation graph: a radial vignette, a faint
## seeded starfield, and gold corner brackets (framed-document feel). Sits behind the
## zoom/pan Canvas and does NOT move with it — atmosphere, not part of the graph.
## Referenced only by ConstellationScene.tscn (no class_name needed).

const STAR_COUNT := 70
const STAR_SEED  := 424242
const GOLD       := Color(0.85, 0.70, 0.20)

var _vignette: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Radial darkening: transparent at centre → dark toward the edges/corners.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.02, 0.02, 0.05, 0.55))
	_vignette = GradientTexture2D.new()
	_vignette.gradient = grad
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(0.5, 0.0)  # radius = half-height; corners clamp to darkest
	_vignette.width = 256
	_vignette.height = 256

	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return

	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false)

	# Seeded starfield — deterministic so it never shimmers between redraws.
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for _i in STAR_COUNT:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var rad := rng.randf_range(0.5, 1.6)
		var a := rng.randf_range(0.10, 0.40)
		var col := Color(0.85, 0.85, 1.0, a)
		if rng.randf() < 0.12:
			col = Color(GOLD.r, GOLD.g, GOLD.b, a + 0.2)  # occasional gold twinkle
		draw_circle(p, rad, col)

	_draw_corner_brackets()


## Gold L-shaped brackets inset from each corner — a light "tangible document" frame.
func _draw_corner_brackets() -> void:
	var m := 6.0    # inset from the edge
	var arm := 18.0  # bracket arm length
	var col := Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	var w := 2.0
	var corners := [
		[Vector2(m, m), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(size.x - m, m), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(m, size.y - m), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(size.x - m, size.y - m), Vector2(-1, 0), Vector2(0, -1)],
	]
	for cdef in corners:
		var o: Vector2 = cdef[0]
		draw_line(o, o + (cdef[1] as Vector2) * arm, col, w, true)
		draw_line(o, o + (cdef[2] as Vector2) * arm, col, w, true)
