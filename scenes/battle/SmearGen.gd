class_name SmearGen
extends RefCounted

# Procedural weapon smear frames (strike swoops). During fast swing frames the
# held-item overlay is replaced by a baked arc "smear" derived from the weapon's
# own art and the resolved anchor-table rotation delta — no hand-authored smear
# art. Pure static math + a texture cache; Combatant decides per frame via
# sweep_for_frames() and draws the baked canvas at the grip anchor.
#
# Conventions (match the held-overlay system, schema doc in SpriteRegistry):
# - Held art is authored VERTICAL, tip up, grip on the symmetry axis; anchor
#   rot° is absolute tilt from vertical, positive clockwise on screen.
# - Bakes are in UNFLIPPED terms with ABSOLUTE arc angles; the canvas centre is
#   the grip pivot, so the sprite draws at the hand anchor with rotation 0 and
#   the runtime facing flip mirrors the whole canvas (arc angles negate with
#   it, consistent with Combatant.held_rotation).
# - Only mass ABOVE the grip smears (blade, not pommel) — classic smear look.

const DEFAULT_THRESHOLD_DEG := 25.0
const DEFAULT_MAX_SWEEP_DEG := 140.0
const DEFAULT_TRAIL_FRAC_MIN := 0.35
## Angular ramp bands over sweep position u (1 = leading edge): core above,
## mid between, trail below — quantized 3-step pixel ramp, no smooth gradient.
const CORE_BAND := 0.8
const MID_BAND := 0.45
## Fraction of the art's used rows (from the tip) sampled for the palette —
## keeps grip/handle colors out of the blade average.
const BLADE_ROW_FRAC := 0.6
const TRAIL_DARKEN := 0.45
## Palette when the art has no opaque pixels to average.
const FALLBACK_MID := Color(0.75, 0.75, 0.78)

const DEFAULTS := {
	"enabled": true,
	"threshold_deg": DEFAULT_THRESHOLD_DEG,
	"max_sweep_deg": DEFAULT_MAX_SWEEP_DEG,
	"trail_frac_min": DEFAULT_TRAIL_FRAC_MIN,
}

static var _cache: Dictionary = {}


## Rotation of a manifest anchor entry ([x, y] = 0, [x, y, rot] = rot).
static func entry_rot(entry: Variant) -> float:
	if entry is Array and (entry as Array).size() > 2:
		return float((entry as Array)[2])
	return 0.0


## Decides whether the swing between two consecutive frame rotations smears.
## Returns null below `threshold_deg` (weapon draws normally), else
## {"from": deg, "to": deg} — `to` is the current frame's rotation, `from`
## trails it by the shortest angular path, magnitude capped at max_sweep_deg.
## Angles may leave [-180, 180]; bake() wraps per pixel.
static func sweep_for_frames(prev_rot: float, cur_rot: float,
		threshold_deg: float = DEFAULT_THRESHOLD_DEG,
		max_sweep_deg: float = DEFAULT_MAX_SWEEP_DEG) -> Variant:
	var delta := wrapf(cur_rot - prev_rot, -180.0, 180.0)
	if absf(delta) < threshold_deg:
		return null
	delta = clampf(delta, -max_sweep_deg, max_sweep_deg)
	return {"from": cur_rot - delta, "to": cur_rot}


## Normalizes a manifest "smear" value (item json or override chain) into a
## params dict. false = disabled; true/null/missing = defaults; a dict merges
## over the defaults key-by-key (unknown keys ignored).
static func params_from_meta(v: Variant) -> Dictionary:
	var p := DEFAULTS.duplicate()
	if v is bool and not v:
		p["enabled"] = false
	elif v is Dictionary:
		var d := v as Dictionary
		for k: String in p.keys():
			if d.get(k) == null:
				continue
			p[k] = bool(d[k]) if k == "enabled" else float(d[k])
	return p


## 3-step smear ramp from the weapon art: white core, alpha-weighted mean of
## the blade rows (top BLADE_ROW_FRAC of the used rect — grip rows excluded)
## as mid, darkened mid as trail.
static func smear_palette(img: Image) -> Dictionary:
	var mid := FALLBACK_MID
	var used := img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var rows := maxi(1, ceili(used.size.y * BLADE_ROW_FRAC))
		var sum := Vector3.ZERO
		var weight := 0.0
		for y in range(used.position.y, used.position.y + rows):
			for x in range(used.position.x, used.position.x + used.size.x):
				var c := img.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				sum += Vector3(c.r, c.g, c.b) * c.a
				weight += c.a
		if weight > 0.0:
			mid = Color(sum.x / weight, sum.y / weight, sum.z / weight)
	return {"core": Color.WHITE, "mid": mid, "trail": mid.darkened(TRAIL_DARKEN)}


## Opaque fraction of the art row at each integer radius above the grip
## (index 0 = grip row, last = top of the used rect). Sparse rows shorten the
## smear trail at that radius (streaky taper); empty rows leave gaps.
static func coverage_profile(img: Image, grip_px: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return out
	var max_r := grip_px.y - used.position.y
	if max_r <= 0:
		return out
	out.resize(max_r + 1)
	for r in max_r + 1:
		var y := grip_px.y - r
		if y < 0 or y >= img.get_height():
			continue
		var opaque := 0
		for x in range(used.position.x, used.position.x + used.size.x):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
		out[r] = float(opaque) / float(used.size.x)
	return out


## Bakes one smear frame: a square canvas centred on the grip pivot, holding
## the annular arc swept from `from_deg` to `to_deg`. Per pixel: radius picks
## the coverage row (0 coverage = gap), sweep position u ∈ [0, 1] (1 = leading
## edge) must clear the trail cut 1 − lerp(trail_frac_min, 1, coverage) —
## thick rows sweep the full arc, sparse rows leave short streaks — then the
## quantized ramp colors it (u ≥ CORE_BAND core, ≥ MID_BAND mid, else trail).
static func bake(img: Image, grip_px: Vector2i, from_deg: float, to_deg: float,
		palette: Dictionary, trail_frac_min: float = DEFAULT_TRAIL_FRAC_MIN) -> Image:
	var cov := coverage_profile(img, grip_px)
	var max_r := cov.size() - 1
	var sweep := to_deg - from_deg
	if max_r < 1 or absf(sweep) < 0.01:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var side := 2 * max_r + 3
	var center := side / 2.0
	var out := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var core: Color = palette.get("core", Color.WHITE)
	var mid: Color = palette.get("mid", FALLBACK_MID)
	var trail: Color = palette.get("trail", FALLBACK_MID)
	for py in side:
		for px in side:
			var dx := px + 0.5 - center
			var dy := py + 0.5 - center
			var ri := roundi(sqrt(dx * dx + dy * dy))
			if ri < 1 or ri > max_r:
				continue
			var c := cov[ri]
			if c <= 0.0:
				continue
			# Angle from vertical, positive clockwise (rot° convention).
			var phi := rad_to_deg(atan2(dx, -dy))
			var u := wrapf(phi - from_deg, -180.0, 180.0) / sweep
			if u < 0.0 or u > 1.0:
				continue
			if u < 1.0 - lerpf(trail_frac_min, 1.0, c):
				continue
			var col := trail
			if u >= CORE_BAND:
				col = core
			elif u >= MID_BAND:
				col = mid
			out.set_pixel(px, py, col)
	return out


## Stable cache identity for one baked frame. `art_key` must already encode
## anything that changes the silhouette (flips, back variant).
static func cache_key(art_key: String, grip_px: Vector2i, from_deg: float,
		to_deg: float, trail_frac_min: float) -> String:
	return "%s|%d,%d|%d>%d|%d" % [art_key, grip_px.x, grip_px.y,
			roundi(from_deg), roundi(to_deg), roundi(trail_frac_min * 100.0)]


## Cached bake → ImageTexture. Lazy: first strike of a given (art, arc) pair
## pays the bake, repeats are dictionary hits. clear_cache() after anchor or
## param edits (held-editor) forces regeneration.
static func texture_for(art_key: String, img: Image, grip_px: Vector2i,
		from_deg: float, to_deg: float, params: Dictionary) -> ImageTexture:
	var tf := float(params.get("trail_frac_min", DEFAULT_TRAIL_FRAC_MIN))
	var key := cache_key(art_key, grip_px, from_deg, to_deg, tf)
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(
			bake(img, grip_px, from_deg, to_deg, smear_palette(img), tf))
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()
