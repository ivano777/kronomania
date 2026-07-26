class_name AuraFX
extends Node2D

# Runtime consumer of AuraGen specs. Particle layers become CPUParticles2D
# children (nearest-filtered ImageTextures from the baked shapes, palette
# applied via color ramp, per-layer aim + off-center offset); "ripple" layers
# are rings expanded in _process and drawn in _draw with their spec geometry
# (circle / polygon / star / ellipse / dashed / rare jagged fingerprint
# profile, plus rotation and wobble); the whole node breathes via a scale
# pulse and may slow-spin. Mutations are already baked into the spec by
# AuraGen — nothing here knows about them. Self-contained — no autoload deps —
# so battle scenes can adopt it later; the Aura Lab dev scene is the current
# only user.

## Point count for smooth ring outlines (jagged profiles map 1:1 onto it).
const RING_SAMPLES := 48

var _spec: Dictionary = {}
var _ripple_layers: Array[Dictionary] = []   # {"params": layer, "next_at": float}
var _rings: Array[Dictionary] = []           # {"r": float, "params": layer}
var _t := 0.0
var _pulse_hz := 1.0
var _pulse_amp := 0.0
var _intensity := 1.0
var _rot_deg_s := 0.0


func build(spec: Dictionary) -> void:
	_spec = spec
	for c in get_children():
		c.queue_free()
	_ripple_layers.clear()
	_rings.clear()
	_t = 0.0
	rotation = 0.0
	_pulse_hz = float(spec.get("pulse_hz", 1.0))
	_pulse_amp = float(spec.get("pulse_amp", 0.0))
	_intensity = float(spec.get("intensity", 1.0))
	_rot_deg_s = float(spec.get("rot_deg_s", 0.0))
	var tex_cache: Array[ImageTexture] = []
	for img in (spec.get("textures", []) as Array):
		tex_cache.append(ImageTexture.create_from_image(img as Image))
	for layer in (spec.get("layers", []) as Array):
		var l: Dictionary = layer
		if String(l.get("motion", "")) == "ripple":
			_ripple_layers.append({"params": l, "next_at": 0.0})
		else:
			add_child(_make_particles(l, tex_cache))
	queue_redraw()


## Re-run the birth: rings cleared, particles restarted from zero.
func restart() -> void:
	_t = 0.0
	rotation = 0.0
	_rings.clear()
	for rl in _ripple_layers:
		rl["next_at"] = 0.0
	for c in get_children():
		if c is CPUParticles2D:
			(c as CPUParticles2D).restart()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var s := _intensity * (1.0 + _pulse_amp * sin(TAU * _pulse_hz * _t))
	scale = Vector2(s, s)
	rotation_degrees += _rot_deg_s * delta
	if _ripple_layers.is_empty() and _rings.is_empty():
		return
	for rl in _ripple_layers:
		var params: Dictionary = rl["params"]
		while _t >= float(rl["next_at"]):
			_rings.append({"r": 0.0, "params": params})
			if params.get("echo", false):
				_rings.append({
					"r": -float(params["speed"]) * float(params["interval"]) * 0.5,
					"params": params,
				})
			rl["next_at"] = float(rl["next_at"]) + float(params["interval"])
	var alive: Array[Dictionary] = []
	for ring in _rings:
		var params: Dictionary = ring["params"]
		ring["r"] = float(ring["r"]) + float(params["speed"]) * delta
		if float(ring["r"]) < float(params["max_radius"]):
			alive.append(ring)
	_rings = alive
	queue_redraw()


# ── ring rendering ────────────────────────────────────────────────────────────

func _draw() -> void:
	var ramp: Array = ((_spec.get("palette", {}) as Dictionary).get("ramp", []) as Array)
	for ring in _rings:
		var r := float(ring["r"])
		if r < 0.5:
			continue
		var params: Dictionary = ring["params"]
		var col := Color.WHITE
		if not ramp.is_empty():
			col = ramp[clampi(int(params.get("color_idx", 2)), 0, ramp.size() - 1)]
		col.a = clampf(1.0 - r / float(params["max_radius"]), 0.0, 1.0)
		var off := params.get("offset", Vector2.ZERO) as Vector2
		var w := float(params.get("width", 1.0))
		var ang0 := deg_to_rad(float(params.get("rot_deg_s", 0.0)) * _t)
		if String(params.get("geometry", "circle")) == "dashed":
			var n := maxi(2, int(params.get("dash_count", 8)))
			var seg := TAU / n
			for i in n:
				draw_arc(off, roundf(r), ang0 + i * seg, ang0 + i * seg + seg * 0.55,
						6, col, w)
			continue
		var pts := _ring_points(r, params, ang0, off)
		if pts.size() > 2:
			pts.append(pts[0])
			draw_polyline(pts, col, w)


## Outline points for one ring at radius r. The shape is built unrotated (so
## jag profiles and squash stay anchored to it), then rotated as a whole.
func _ring_points(r: float, params: Dictionary, ang0: float, off: Vector2) -> PackedVector2Array:
	var geometry := String(params.get("geometry", "circle"))
	var sides := maxi(3, int(params.get("sides", 5)))
	var jag: Array = params.get("jag", [])
	var wob_amp := float(params.get("wobble_amp", 0.0))
	var wob_freq := int(params.get("wobble_freq", 4))
	var n := RING_SAMPLES
	match geometry:
		"polygon":
			n = sides
		"star":
			n = sides * 2
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var ri := r
		match geometry:
			"star":
				if i % 2 == 1:
					ri = r * float(params.get("star_ratio", 0.5))
			"jagged":
				if not jag.is_empty():
					ri = r * (1.0 + float(jag[i % jag.size()]))
		if wob_amp > 0.0 and geometry != "polygon" and geometry != "star":
			ri += sin(a * wob_freq + _t * 3.0) * wob_amp
		var p := Vector2(cos(a), sin(a)) * ri
		if geometry == "ellipse":
			p.y *= float(params.get("squash", 0.7))
		pts.append(p.rotated(ang0) + off)
	return pts


# ── particle mapping ──────────────────────────────────────────────────────────

func _make_particles(layer: Dictionary, tex: Array[ImageTexture]) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	if not tex.is_empty():
		p.texture = tex[clampi(int(layer.get("tex_idx", 0)), 0, tex.size() - 1)]
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = layer.get("offset", Vector2.ZERO) as Vector2
	p.amount = int(layer.get("count", 12))
	p.lifetime = float(layer.get("lifetime", 1.0))
	p.lifetime_randomness = float(layer.get("lifetime_rand", 0.2))
	p.explosiveness = float(layer.get("explosive", 0.0))
	p.emitting = true
	p.gravity = Vector2.ZERO
	var er := float(layer.get("emit_radius", 0.0))
	if er <= 1.5:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	else:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE if layer.get("emit_fill", false) \
				else CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		p.emission_sphere_radius = er
	p.spread = float(layer.get("spread", 45.0))
	p.direction = Vector2.UP.rotated(deg_to_rad(float(layer.get("dir_deg", 0.0))))
	p.initial_velocity_min = float(layer.get("speed_min", 0.0))
	p.initial_velocity_max = float(layer.get("speed_max", 0.0))
	p.scale_amount_min = float(layer.get("scale_min", 1.0))
	p.scale_amount_max = float(layer.get("scale_max", 1.0))
	var spin := float(layer.get("spin", 0.0))
	p.angular_velocity_min = -absf(spin)
	p.angular_velocity_max = absf(spin)
	var hv := float(layer.get("hue_var", 0.0))
	p.hue_variation_min = -hv
	p.hue_variation_max = hv
	p.particle_flag_align_y = bool(layer.get("align_y", false))
	var damp := float(layer.get("damping", 0.0))
	if damp > 0.0:
		p.damping_min = damp * 0.5
		p.damping_max = damp
	if layer.get("shrink", false):
		var cur := Curve.new()
		cur.add_point(Vector2(0.0, 1.0))
		cur.add_point(Vector2(1.0, 0.1))
		p.scale_amount_curve = cur
	if layer.get("additive", false):
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	_apply_ramp(p, layer)
	# Aimed motions keep their spec spread (narrow spread = directed jet);
	# center-symmetric ones always cover the full circle.
	match String(layer.get("motion", "rise")):
		"rise":
			p.gravity = Vector2(0.0, float(layer.get("gravity_y", -30.0)))
		"implode":
			p.spread = 180.0
			var ra := float(layer.get("radial", -60.0))
			p.radial_accel_min = minf(ra, ra * 0.7)
			p.radial_accel_max = maxf(ra, ra * 0.7)
		"orbit":
			p.spread = 180.0
			var o := float(layer.get("orbit_rps", 0.5))
			p.orbit_velocity_min = minf(o, o * 0.7)
			p.orbit_velocity_max = maxf(o, o * 0.7)
		"spiral":
			p.spread = 180.0
			var o2 := float(layer.get("orbit_rps", 0.5))
			p.orbit_velocity_min = minf(o2, o2 * 0.8)
			p.orbit_velocity_max = maxf(o2, o2 * 0.8)
			var ra2 := float(layer.get("radial", 20.0))
			p.radial_accel_min = minf(ra2, ra2 * 0.7)
			p.radial_accel_max = maxf(ra2, ra2 * 0.7)
		"spark":
			p.gravity = Vector2(0.0, float(layer.get("gravity_y", 0.0)))
	return p


## Palette over lifetime: bright birth fading to dark + transparent (reversed
## when the layer says so). Offsets before colors — Gradient resizes on offsets.
func _apply_ramp(p: CPUParticles2D, layer: Dictionary) -> void:
	var ramp: Array = ((_spec.get("palette", {}) as Dictionary).get("ramp", []) as Array)
	if ramp.size() < 4:
		return
	var cols: Array[Color] = [ramp[3], ramp[2], ramp[1], ramp[0]]
	if layer.get("ramp_reverse", false):
		cols.reverse()
	var pc := PackedColorArray()
	for i in 4:
		var c: Color = cols[i]
		if i == 3:
			c.a = 0.0
		pc.append(c)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	g.colors = pc
	p.color_ramp = g
