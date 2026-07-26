class_name AuraGen
extends RefCounted

# Procedural magic-aura generator, keyed like an asymmetric pair: a fixed
# PRIVATE_KEY (project salt — never change it, every aura anyone has ever seen
# derives from it) combines with a free-form public key string; the hash of the
# pair seeds ONE RNG stream that deterministically derives the whole aura —
# name, palette, baked particle textures, layer motions, ripple geometry,
# rotation, pulse, mutations. Same key pair = same aura, forever; any
# public-key change = new aura. Draw ORDER in generate_spec is the contract:
# reordering rng draws re-rolls every aura in the wild.
#
# Pure static + Image baking, no scene or autoload deps (unit-tested headless).
# AuraFX (scenes/battle/AuraFX.gd) consumes the spec; the Aura Lab dev scene
# (scenes/debug/experiments/AuraStudioScene.tscn) is the studio around it.
#
# Spec shape:
# {
#   "public_key": String, "seed": int, "name": String,
#   "rarity": String,                    # seed-rolled luck budget (RARITIES)
#   "tier": int,                         # caller power level 1..4 (input, not rolled)
#   "layer_potential": int,              # rolled 3..6; tier reveals a prefix
#   "palette": {"scheme": String, "profile": String, "inverted": bool,
#               "base_hue": float, "ramp": Array[Color] (4, dark→bright),
#               "glow": Color},
#   "textures": Array[Image],            # 1..4 white-tone shapes, tinted at runtime
#   "layers": Array[Dictionary],         # revealed layers, see _gen_layer
#   "rot_deg_s": float,                  # whole-aura slow spin
#   "pulse_hz": float, "pulse_amp": float, "intensity": float,
#   "mutations": Array[String],          # 0..3 rare modifiers, already applied
# }

const PRIVATE_KEY := "KRONO-AURA-V1"

const MOTIONS := ["rise", "orbit", "spiral", "burst", "implode", "spark", "ripple"]
const SCHEMES := ["mono", "analog", "complement", "triad", "clash"]
const PROFILES := ["standard", "neon", "muted", "dark"]
const SHAPES := ["blob", "star", "streak", "ring", "diamond", "glyph", "bolt", "noise"]
const GEOMETRIES := ["circle", "polygon", "star", "ellipse", "dashed", "jagged"]
const MUTATIONS := ["strobe", "giant", "tiny", "mono", "inferno", "sparse"]
const RARITIES := ["common", "fine", "arcane", "relic"]

## Rarity = seed-rolled LUCK budget (equipment vocabulary): mutation slots +
## per-slot chance, eccentric-roll chance, jagged-geometry weight.
const RARITY_LUCK := {
	"common": {"slots": 1, "mut": 0.15, "ecc": 0.10, "jag": 0.06},
	"fine": {"slots": 2, "mut": 0.22, "ecc": 0.18, "jag": 0.10},
	"arcane": {"slots": 2, "mut": 0.35, "ecc": 0.25, "jag": 0.16},
	"relic": {"slots": 3, "mut": 0.45, "ecc": 0.35, "jag": 0.25},
}

## Tier = caller-set power level (1..4), applied as a deterministic
## post-transform (no rng draws): reveals a prefix of the rolled layer
## potential and scales amplitude. Same key = same aura identity at any tier.
const TIER_LAYER_CAP := {1: 2, 2: 3, 3: 4, 4: 6}
const TIER_COUNT_MUL := {1: 0.6, 2: 0.85, 3: 1.1, 4: 1.4}
const TIER_RADIUS_MUL := {1: 0.7, 2: 0.9, 3: 1.05, 4: 1.25}
const TIER_INTENSITY_MUL := {1: 0.85, 2: 1.0, 3: 1.1, 4: 1.25}

## Samples in a jagged ripple's radial profile (ring renderer walks them 1:1).
const JAG_SAMPLES := 48

const NAME_A := ["Umbral", "Solar", "Void", "Ember", "Frost", "Astral", "Chrono",
		"Verdant", "Gilded", "Hollow", "Radiant", "Abyssal", "Storm", "Lunar",
		"Prismal", "Dread"]
const NAME_B := ["Crown", "Ripple", "Bloom", "Cascade", "Halo", "Vortex", "Mantle",
		"Pulse", "Shroud", "Lattice", "Chorus", "Wake", "Veil", "Sigil", "Tide",
		"Furnace"]


static func derive_seed(public_key: String) -> int:
	return ("%s::%s" % [PRIVATE_KEY, public_key]).hash()


static func generate_spec(public_key: String, tier: int = 4) -> Dictionary:
	tier = clampi(tier, 1, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(public_key)
	var aura_name := "%s %s" % [
		NAME_A[rng.randi_range(0, NAME_A.size() - 1)],
		NAME_B[rng.randi_range(0, NAME_B.size() - 1)],
	]
	var rarity := _roll_rarity(rng)
	var luck: Dictionary = RARITY_LUCK[rarity]
	var palette := _gen_palette(rng)
	var tex_n := rng.randi_range(1, 4)
	var textures: Array = []
	for i in tex_n:
		textures.append(_bake_texture(rng, SHAPES[rng.randi_range(0, SHAPES.size() - 1)]))
	# Full layer potential always rolled (keeps the stream tier-independent);
	# _apply_tier reveals a prefix of it.
	var layer_n := rng.randi_range(3, 6)
	var layers: Array = []
	for i in layer_n:
		layers.append(_gen_layer(rng, tex_n, luck))
	var spec := {
		"public_key": public_key,
		"seed": derive_seed(public_key),
		"name": aura_name,
		"rarity": rarity,
		"tier": tier,
		"layer_potential": layer_n,
		"palette": palette,
		"textures": textures,
		"layers": layers,
		"rot_deg_s": rng.randf_range(-25.0, 25.0) if rng.randf() < 0.4 else 0.0,
		"pulse_hz": rng.randf_range(0.4, 2.2),
		"pulse_amp": rng.randf_range(0.03, 0.18),
		"intensity": rng.randf_range(0.55, 1.4),
		"mutations": [],
	}
	var muts: Array = []
	for slot in int(luck["slots"]):
		if rng.randf() < float(luck["mut"]):
			var m: String = MUTATIONS[rng.randi_range(0, MUTATIONS.size() - 1)]
			if not m in muts:
				muts.append(m)
	spec["mutations"] = muts
	_apply_tier(spec)
	_apply_mutations(spec)
	return spec


static func _roll_rarity(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.55:
		return "common"
	if roll < 0.82:
		return "fine"
	if roll < 0.95:
		return "arcane"
	return "relic"


## Tier reveal + amplitude scale. Deterministic (no rng draws) and applied
## before mutations — the tier argument can never shift any roll.
static func _apply_tier(spec: Dictionary) -> void:
	var tier: int = spec["tier"]
	var shown := mini((spec["layers"] as Array).size(), int(TIER_LAYER_CAP[tier]))
	spec["layers"] = (spec["layers"] as Array).slice(0, shown)
	_scale_counts(spec, float(TIER_COUNT_MUL[tier]))
	for l in (spec["layers"] as Array):
		var d := l as Dictionary
		if d.has("max_radius"):
			d["max_radius"] = minf(float(d["max_radius"]) * float(TIER_RADIUS_MUL[tier]), 110.0)
	spec["intensity"] = float(spec["intensity"]) * float(TIER_INTENSITY_MUL[tier])


## Mutations transform the assembled spec deterministically — no rng draws in
## here, so adding/removing a mutation never shifts the stream for other rolls.
static func _apply_mutations(spec: Dictionary) -> void:
	for m in (spec["mutations"] as Array):
		match String(m):
			"strobe":
				spec["pulse_hz"] = clampf(float(spec["pulse_hz"]) * 3.5, 4.0, 8.0)
				spec["pulse_amp"] = maxf(float(spec["pulse_amp"]), 0.3)
			"giant":
				spec["intensity"] = float(spec["intensity"]) * 1.6
			"tiny":
				spec["intensity"] = float(spec["intensity"]) * 0.45
				_scale_counts(spec, 1.5)
			"mono":
				var pal: Dictionary = spec["palette"]
				var ghost: Array = []
				for c in (pal["ramp"] as Array):
					ghost.append(Color.from_hsv(0.0, 0.0, (c as Color).v))
				pal["ramp"] = ghost
				pal["glow"] = Color.WHITE
			"inferno":
				for l in (spec["layers"] as Array):
					if (l as Dictionary).has("additive"):
						(l as Dictionary)["additive"] = true
				_scale_counts(spec, 1.4)
			"sparse":
				_scale_counts(spec, 0.4)
				for l in (spec["layers"] as Array):
					var d := l as Dictionary
					if d.has("scale_min"):
						d["scale_min"] = float(d["scale_min"]) * 1.6
						d["scale_max"] = float(d["scale_max"]) * 1.6


static func _scale_counts(spec: Dictionary, factor: float) -> void:
	for l in (spec["layers"] as Array):
		var d := l as Dictionary
		if d.has("count"):
			d["count"] = clampi(int(float(d["count"]) * factor), 3, 120)


# ── palette ───────────────────────────────────────────────────────────────────

static func _gen_palette(rng: RandomNumberGenerator) -> Dictionary:
	var scheme: String = SCHEMES[rng.randi_range(0, SCHEMES.size() - 1)]
	var base_h := rng.randf()
	var hues: Array[float] = []
	match scheme:
		"mono":
			hues = [base_h, base_h, base_h, base_h]
		"analog":
			hues = [base_h, wrapf(base_h + 0.06, 0.0, 1.0),
					wrapf(base_h - 0.06, 0.0, 1.0), wrapf(base_h + 0.12, 0.0, 1.0)]
		"complement":
			hues = [base_h, base_h, wrapf(base_h + 0.5, 0.0, 1.0), base_h]
		"triad":
			hues = [base_h, wrapf(base_h + 1.0 / 3.0, 0.0, 1.0),
					wrapf(base_h + 2.0 / 3.0, 0.0, 1.0), base_h]
		"clash":
			var h2 := wrapf(base_h + rng.randf_range(0.2, 0.8), 0.0, 1.0)
			hues = [base_h, base_h, h2, h2]
	var profile: String = PROFILES[rng.randi_range(0, PROFILES.size() - 1)]
	var sat := Vector2(0.9, 0.55)   # x = dark end, y = bright end
	var val := Vector2(0.35, 1.0)
	match profile:
		"neon":
			sat = Vector2(1.0, 0.85)
			val = Vector2(0.55, 1.0)
		"muted":
			sat = Vector2(0.5, 0.3)
			val = Vector2(0.4, 0.8)
		"dark":
			sat = Vector2(0.85, 0.6)
			val = Vector2(0.18, 0.55)
	var inverted := rng.randf() < 0.25
	var ramp: Array = []
	for i in 4:
		var t := i / 3.0
		ramp.append(Color.from_hsv(hues[i], lerpf(sat.x, sat.y, t), lerpf(val.x, val.y, t)))
	if inverted:
		ramp.reverse()
	return {
		"scheme": scheme,
		"profile": profile,
		"inverted": inverted,
		"base_hue": base_h,
		"ramp": ramp,
		"glow": Color.from_hsv(base_h, 0.25, 1.0),
	}


# ── particle textures ─────────────────────────────────────────────────────────

## White-tone pixel shape (core white / edge gray) so the runtime color ramp
## tints it; 7–21 px odd square, hard pixels, no AA.
static func _bake_texture(rng: RandomNumberGenerator, shape: String) -> Image:
	var s := 7 + 2 * rng.randi_range(0, 7)
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) / 2.0
	var ci := int(c)
	var r := c
	var core := Color(1.0, 1.0, 1.0, 1.0)
	var edge := Color(0.72, 0.72, 0.8, 1.0)
	match shape:
		"blob":
			for y in s:
				for x in s:
					var d := Vector2(x - c, y - c).length()
					if d <= r * 0.55:
						img.set_pixel(x, y, core)
					elif d <= r:
						img.set_pixel(x, y, edge)
		"ring":
			for y in s:
				for x in s:
					var d := Vector2(x - c, y - c).length()
					if d <= r and d >= r - 2.0:
						img.set_pixel(x, y, core if d < r - 1.0 else edge)
		"diamond":
			for y in s:
				for x in s:
					var d := absf(x - c) + absf(y - c)
					if d <= r * 0.6:
						img.set_pixel(x, y, core)
					elif d <= r * 1.2:
						img.set_pixel(x, y, edge)
		"star":
			for i in s:
				img.set_pixel(i, ci, edge)
				img.set_pixel(ci, i, edge)
			var arm := int(r * 0.5)
			for i in range(-arm, arm + 1):
				img.set_pixel(ci + i, ci + i, edge)
				img.set_pixel(ci + i, ci - i, edge)
			for i in range(-1, 2):
				img.set_pixel(ci + i, ci, core)
				img.set_pixel(ci, ci + i, core)
		"streak":
			for y in s:
				var fade := 1.0 - float(y) / float(s - 1) * 0.5
				img.set_pixel(ci, y, Color(1.0, 1.0, 1.0, fade))
				if s >= 11:
					img.set_pixel(ci - 1, y, Color(0.72, 0.72, 0.8, fade * 0.8))
		"glyph":
			var half := (s + 1) / 2
			for y in s:
				for x in half:
					if rng.randf() < 0.38:
						var col := core if rng.randf() < 0.5 else edge
						img.set_pixel(x, y, col)
						img.set_pixel(s - 1 - x, y, col)
		"bolt":
			var x := ci
			for y in s:
				x = clampi(x + rng.randi_range(-1, 1), 1, s - 2)
				img.set_pixel(x, y, core)
				img.set_pixel(x + (1 if rng.randf() < 0.5 else -1), y, edge)
		"noise":
			for y in s:
				for x in s:
					if rng.randf() < 0.3:
						img.set_pixel(x, y, core if rng.randf() < 0.4 else edge)
	if img.get_used_rect().size.x == 0:
		img.set_pixel(ci, ci, core)
	return img


# ── layers ────────────────────────────────────────────────────────────────────

## One aura layer. "ripple" layers are rings drawn by AuraFX (geometry picks
## the ring outline — jagged is the rare fingerprint-like one); every other
## motion maps onto one CPUParticles2D. All coords/speeds in px at scale 1.
static func _gen_layer(rng: RandomNumberGenerator, tex_count: int, luck: Dictionary) -> Dictionary:
	var motion: String = MOTIONS[rng.randi_range(0, MOTIONS.size() - 1)]
	if motion == "ripple":
		return _gen_ripple(rng, luck)
	var layer := {
		"motion": motion,
		"tex_idx": rng.randi_range(0, tex_count - 1),
		"count": rng.randi_range(8, 64),
		"lifetime": rng.randf_range(0.5, 2.4),
		"lifetime_rand": rng.randf_range(0.0, 0.5),
		"emit_radius": rng.randf_range(0.0, 26.0),
		"emit_fill": rng.randf() < 0.4,
		"spread": rng.randf_range(8.0, 180.0),
		"dir_deg": 0.0,
		"offset": Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-14.0, 14.0)) \
				if rng.randf() < 0.25 else Vector2.ZERO,
		"scale_min": rng.randf_range(0.4, 1.3),
		"scale_max": 0.0,
		"spin": rng.randf_range(-220.0, 220.0) if rng.randf() < 0.5 else 0.0,
		"additive": rng.randf() < 0.55,
		"shrink": rng.randf() < 0.7,
		"ramp_reverse": rng.randf() < 0.35,
		"hue_var": rng.randf_range(0.02, 0.12) if rng.randf() < 0.4 else 0.0,
		"align_y": false,
		"speed_min": 0.0,
		"speed_max": 0.0,
		"explosive": 0.0,
	}
	layer["scale_max"] = float(layer["scale_min"]) + rng.randf_range(0.0, 1.8)
	match motion:
		"rise":
			layer["speed_min"] = rng.randf_range(8.0, 22.0)
			layer["speed_max"] = rng.randf_range(24.0, 55.0)
			layer["gravity_y"] = rng.randf_range(-70.0, -15.0)
			layer["emit_radius"] = rng.randf_range(4.0, 20.0)
			layer["emit_fill"] = true
			layer["align_y"] = rng.randf() < 0.5
			layer["dir_deg"] = rng.randf_range(0.0, 360.0) if rng.randf() < 0.15 \
					else rng.randf_range(-30.0, 30.0)
		"burst":
			layer["speed_min"] = rng.randf_range(20.0, 40.0)
			layer["speed_max"] = rng.randf_range(45.0, 90.0)
			layer["damping"] = rng.randf_range(0.0, 30.0)
			layer["explosive"] = rng.randf_range(0.6, 0.95) if rng.randf() < 0.6 else 0.0
			layer["align_y"] = rng.randf() < 0.5
			layer["dir_deg"] = rng.randf_range(0.0, 360.0)
		"implode":
			layer["emit_radius"] = rng.randf_range(22.0, 44.0)
			layer["radial"] = rng.randf_range(-110.0, -45.0)
		"orbit":
			layer["emit_radius"] = rng.randf_range(12.0, 34.0)
			layer["speed_min"] = rng.randf_range(0.0, 6.0)
			layer["speed_max"] = rng.randf_range(6.0, 14.0)
			layer["orbit_rps"] = rng.randf_range(0.25, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
		"spiral":
			layer["emit_radius"] = rng.randf_range(2.0, 10.0)
			layer["orbit_rps"] = rng.randf_range(0.25, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
			layer["radial"] = rng.randf_range(8.0, 45.0)
		"spark":
			layer["count"] = rng.randi_range(6, 26)
			layer["lifetime"] = rng.randf_range(0.3, 0.9)
			layer["speed_min"] = rng.randf_range(30.0, 60.0)
			layer["speed_max"] = rng.randf_range(60.0, 120.0)
			layer["gravity_y"] = rng.randf_range(20.0, 70.0) if rng.randf() < 0.5 else 0.0
			layer["damping"] = rng.randf_range(10.0, 40.0)
			layer["dir_deg"] = rng.randf_range(0.0, 360.0)
	# Eccentric roll — one stat pushed way out of band; big part of "no two alike".
	if rng.randf() < float(luck["ecc"]):
		match rng.randi_range(0, 3):
			0:
				layer["count"] = clampi(int(layer["count"]) * 2, 3, 120)
			1:
				layer["scale_min"] = float(layer["scale_min"]) * 2.2
				layer["scale_max"] = float(layer["scale_max"]) * 2.2
			2:
				layer["lifetime"] = clampf(float(layer["lifetime"]) * 2.5, 0.3, 6.0)
			3:
				layer["speed_min"] = float(layer["speed_min"]) * 1.8
				layer["speed_max"] = float(layer["speed_max"]) * 1.8
	return layer


static func _gen_ripple(rng: RandomNumberGenerator, luck: Dictionary) -> Dictionary:
	var geometry := _pick_geometry(rng, float(luck["jag"]))
	return {
		"motion": "ripple",
		"interval": rng.randf_range(0.3, 1.4),
		"speed": rng.randf_range(24.0, 120.0),
		"width": float(rng.randi_range(1, 3)),
		"max_radius": rng.randf_range(36.0, 100.0),
		"color_idx": rng.randi_range(0, 3),
		"echo": rng.randf() < 0.35,
		"geometry": geometry,
		"sides": rng.randi_range(3, 8),
		"star_ratio": rng.randf_range(0.35, 0.7),
		"squash": rng.randf_range(0.5, 0.85),
		"dash_count": rng.randi_range(6, 16),
		"rot_deg_s": rng.randf_range(-60.0, 60.0) if rng.randf() < 0.6 else 0.0,
		"wobble_amp": rng.randf_range(1.0, 4.0) if rng.randf() < 0.35 else 0.0,
		"wobble_freq": rng.randi_range(3, 7),
		"offset": Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-14.0, 14.0)) \
				if rng.randf() < 0.25 else Vector2.ZERO,
		"jag": _gen_jag(rng) if geometry == "jagged" else [],
	}


## Weighted pick — jagged (fingerprint-like irregular outline) stays rare;
## its weight comes from the aura's rarity, the rest keep their proportions.
static func _pick_geometry(rng: RandomNumberGenerator, jag_weight: float) -> String:
	var roll := rng.randf()
	if roll < jag_weight:
		return "jagged"
	var t := (roll - jag_weight) / (1.0 - jag_weight)
	if t < 0.333:
		return "circle"
	if t < 0.556:
		return "polygon"
	if t < 0.722:
		return "star"
	if t < 0.856:
		return "ellipse"
	return "dashed"


## Radial profile for jagged rings: a clamped random walk around the circle,
## seam crossfaded so sample 47 meets sample 0 without a step. Every ring of
## the layer reuses it → concentric ridges, fingerprint look.
static func _gen_jag(rng: RandomNumberGenerator) -> Array:
	var prof: Array = []
	var v := 0.0
	for i in JAG_SAMPLES:
		v = clampf(v + rng.randf_range(-0.09, 0.09), -0.28, 0.28)
		prof.append(v)
	for i in 8:
		var t := (i + 1) / 8.0
		var idx := JAG_SAMPLES - 8 + i
		prof[idx] = lerpf(float(prof[idx]), float(prof[0]), t)
	return prof
