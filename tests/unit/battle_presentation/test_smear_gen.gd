extends GutTest

# Unit tests for SmearGen's pure static math: sweep decision, params parsing,
# palette extraction, coverage profile, analytic arc bake, and texture cache.
# Fixtures are tiny hand-built Images — no assets, fully deterministic.


# ── fixtures ──────────────────────────────────────────────────────────────────

## 8×12 art: a 3px-wide opaque red "blade" column (x 2..4, y 0..9), grip row
## (y 10) transparent. Grip pixel (3, 10) → used rect y-size 10, max radius 10.
func _blade_img() -> Image:
	var img := Image.create_empty(8, 12, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in range(2, 5):
			img.set_pixel(x, y, Color(1, 0, 0, 1))
	return img


const _GRIP := Vector2i(3, 10)


## Palette used by bake tests — distinct colors so band assertions can't alias.
const _PAL := {
	"core": Color.WHITE,
	"mid": Color(1, 0, 0, 1),
	"trail": Color(0.3, 0, 0, 1),
}


## Color at the canvas pixel whose centre sits nearest polar (rho, phi°) from
## the bake centre (phi measured from vertical, positive clockwise).
func _sample(img: Image, rho: float, phi_deg: float) -> Color:
	var center := img.get_width() / 2.0
	var dx := rho * sin(deg_to_rad(phi_deg))
	var dy := -rho * cos(deg_to_rad(phi_deg))
	return img.get_pixel(
			clampi(floori(center + dx), 0, img.get_width() - 1),
			clampi(floori(center + dy), 0, img.get_height() - 1))


# ── entry_rot ─────────────────────────────────────────────────────────────────

func test_entry_rot_reads_third_element() -> void:
	assert_eq(SmearGen.entry_rot([4, 5, 35.0]), 35.0)


func test_entry_rot_two_element_entry_is_zero() -> void:
	assert_eq(SmearGen.entry_rot([4, 5]), 0.0)


func test_entry_rot_null_is_zero() -> void:
	assert_eq(SmearGen.entry_rot(null), 0.0)


# ── sweep_for_frames ──────────────────────────────────────────────────────────

func test_sweep_below_threshold_is_null() -> void:
	assert_null(SmearGen.sweep_for_frames(0.0, 10.0))


func test_sweep_above_threshold_returns_arc() -> void:
	var s: Dictionary = SmearGen.sweep_for_frames(0.0, 40.0)
	assert_eq(s["from"], 0.0)
	assert_eq(s["to"], 40.0)


func test_sweep_negative_direction_preserved() -> void:
	var s: Dictionary = SmearGen.sweep_for_frames(40.0, 0.0)
	assert_eq(s["from"], 40.0)
	assert_eq(s["to"], 0.0)


func test_sweep_takes_shortest_angular_path() -> void:
	# 170° → -150° is a +40° swing through 180, not a -320° one.
	var s: Dictionary = SmearGen.sweep_for_frames(170.0, -150.0)
	assert_eq(s["from"], -190.0)
	assert_eq(s["to"], -150.0)


func test_sweep_clamped_to_max() -> void:
	var s: Dictionary = SmearGen.sweep_for_frames(0.0, 170.0)
	assert_eq(s["from"], 30.0)
	assert_eq(s["to"], 170.0)


func test_sweep_custom_threshold() -> void:
	assert_null(SmearGen.sweep_for_frames(0.0, 40.0, 45.0))


# ── params_from_meta ──────────────────────────────────────────────────────────

func test_params_missing_is_enabled_defaults() -> void:
	var p := SmearGen.params_from_meta(null)
	assert_true(p["enabled"])
	assert_eq(p["threshold_deg"], SmearGen.DEFAULT_THRESHOLD_DEG)


func test_params_false_disables() -> void:
	assert_false(SmearGen.params_from_meta(false)["enabled"])


func test_params_dict_overrides_key() -> void:
	var p := SmearGen.params_from_meta({"threshold_deg": 40})
	assert_eq(p["threshold_deg"], 40.0)
	assert_eq(p["max_sweep_deg"], SmearGen.DEFAULT_MAX_SWEEP_DEG)


func test_params_dict_can_disable() -> void:
	assert_false(SmearGen.params_from_meta({"enabled": false})["enabled"])


# ── smear_palette ─────────────────────────────────────────────────────────────

func test_palette_averages_blade_rows_only() -> void:
	# Top 6 of 10 used rows red, bottom 4 brown — mid must be pure red.
	var img := Image.create_empty(4, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 4:
			img.set_pixel(x, y, Color(1, 0, 0, 1) if y < 6 else Color(0.4, 0.2, 0.1, 1))
	var pal := SmearGen.smear_palette(img)
	assert_almost_eq((pal["mid"] as Color).r, 1.0, 0.01)
	assert_almost_eq((pal["mid"] as Color).g, 0.0, 0.01)


func test_palette_transparent_art_falls_back() -> void:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var pal := SmearGen.smear_palette(img)
	assert_eq(pal["mid"], SmearGen.FALLBACK_MID)


func test_palette_core_is_white_trail_darker() -> void:
	var pal := SmearGen.smear_palette(_blade_img())
	assert_eq(pal["core"], Color.WHITE)
	assert_lt((pal["trail"] as Color).r, (pal["mid"] as Color).r)


# ── coverage_profile ──────────────────────────────────────────────────────────

func test_coverage_spans_grip_to_top() -> void:
	var cov := SmearGen.coverage_profile(_blade_img(), _GRIP)
	assert_eq(cov.size(), 11)


func test_coverage_full_on_blade_rows() -> void:
	var cov := SmearGen.coverage_profile(_blade_img(), _GRIP)
	assert_eq(cov[5], 1.0)
	assert_eq(cov[10], 1.0)


func test_coverage_zero_on_empty_rows() -> void:
	# Grip row itself (radius 0) holds no blade pixels.
	var cov := SmearGen.coverage_profile(_blade_img(), _GRIP)
	assert_eq(cov[0], 0.0)


func test_coverage_empty_art_is_empty() -> void:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	assert_eq(SmearGen.coverage_profile(img, Vector2i(2, 3)).size(), 0)


# ── bake ──────────────────────────────────────────────────────────────────────

func test_bake_canvas_covers_max_radius() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	assert_eq(img.get_width(), 23)   # 2 * max_r(10) + 3
	assert_eq(img.get_width(), img.get_height())


func test_bake_leading_edge_is_core() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	assert_eq(_sample(img, 6.0, 85.0), _PAL["core"])


func test_bake_mid_band_is_weapon_color() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	assert_eq(_sample(img, 6.0, 55.0), _PAL["mid"])


func test_bake_trail_band_is_trail_color() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	# RGBA8 storage quantizes 0.3 to 76/255 — compare with 8-bit tolerance.
	var got := _sample(img, 6.0, 20.0)
	assert_almost_eq(got.r, (_PAL["trail"] as Color).r, 1.0 / 255.0)
	assert_almost_eq(got.g, (_PAL["trail"] as Color).g, 1.0 / 255.0)
	assert_eq(got.a, 1.0)


func test_bake_outside_arc_transparent() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	assert_eq(_sample(img, 6.0, -20.0).a, 0.0)


func test_bake_beyond_radius_transparent() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, 90.0, _PAL)
	assert_eq(_sample(img, 11.0, 90.0).a, 0.0)


func test_bake_counterclockwise_arc() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 0.0, -90.0, _PAL)
	assert_eq(_sample(img, 6.0, -85.0), _PAL["core"])
	assert_eq(_sample(img, 6.0, 20.0).a, 0.0)


func test_bake_zero_sweep_is_empty() -> void:
	var img := SmearGen.bake(_blade_img(), _GRIP, 30.0, 30.0, _PAL)
	assert_eq(img.get_width(), 1)


func test_bake_empty_art_is_empty() -> void:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	assert_eq(SmearGen.bake(img, Vector2i(2, 3), 0.0, 90.0, _PAL).get_width(), 1)


# ── texture cache ─────────────────────────────────────────────────────────────

func test_texture_for_caches_by_key() -> void:
	SmearGen.clear_cache()
	var img := _blade_img()
	var a := SmearGen.texture_for("test_blade", img, _GRIP, 0.0, 90.0, {})
	var b := SmearGen.texture_for("test_blade", img, _GRIP, 0.0, 90.0, {})
	assert_true(a == b, "same args must hit the cache")
	SmearGen.clear_cache()


func test_texture_for_distinct_arcs_distinct_textures() -> void:
	SmearGen.clear_cache()
	var img := _blade_img()
	var a := SmearGen.texture_for("test_blade", img, _GRIP, 0.0, 90.0, {})
	var b := SmearGen.texture_for("test_blade", img, _GRIP, 0.0, 60.0, {})
	assert_true(a != b, "different arcs must bake separately")
	SmearGen.clear_cache()


func test_cache_key_encodes_art_and_arc() -> void:
	var a := SmearGen.cache_key("sword", Vector2i(3, 10), 0.0, 90.0, 0.35)
	var b := SmearGen.cache_key("sword", Vector2i(3, 10), 0.0, 60.0, 0.35)
	var c := SmearGen.cache_key("axe", Vector2i(3, 10), 0.0, 90.0, 0.35)
	assert_ne(a, b)
	assert_ne(a, c)


# ── Combatant.smear_arc (frame decision over resolved anchor tables) ──────────

## Swing table: frame 0→1 swings 100° (smears), 1→2 only 5° (below threshold).
const _HERO_META := {
	"anims": {"attack_melee": {"main": [[10, 20, -60], [12, 20, 40], [12, 20, 45]]}},
}

const _P := {}   # empty params → SmearGen defaults at every use site


func test_smear_arc_frame_zero_never_smears() -> void:
	assert_null(Combatant.smear_arc(_HERO_META, "sword", "attack_melee", "main", 0, _P))


func test_smear_arc_big_swing_smears() -> void:
	var a: Dictionary = Combatant.smear_arc(_HERO_META, "sword", "attack_melee", "main", 1, _P)
	assert_eq(a["from"], -60.0)
	assert_eq(a["to"], 40.0)


func test_smear_arc_small_swing_does_not() -> void:
	assert_null(Combatant.smear_arc(_HERO_META, "sword", "attack_melee", "main", 2, _P))


func test_smear_arc_clamped_frame_repeats_no_smear() -> void:
	# Beyond the table both frames clamp to the last entry — delta 0.
	assert_null(Combatant.smear_arc(_HERO_META, "sword", "attack_melee", "main", 9, _P))


func test_smear_arc_missing_anim_no_smear() -> void:
	assert_null(Combatant.smear_arc(_HERO_META, "sword", "hurt", "main", 1, _P))


func test_smear_arc_disabled_params_no_smear() -> void:
	assert_null(Combatant.smear_arc(_HERO_META, "sword", "attack_melee", "main", 1,
			{"enabled": false}))


func test_smear_arc_applies_per_hero_rot_delta() -> void:
	# items.sword rot +10 shifts BOTH absolute angles; the delta is unchanged.
	var meta := _HERO_META.duplicate()
	meta["items"] = {"sword": {"rot": 10}}
	var a: Dictionary = Combatant.smear_arc(meta, "sword", "attack_melee", "main", 1, _P)
	assert_eq(a["from"], -50.0)
	assert_eq(a["to"], 50.0)


# ── Combatant.smear_params (override chain resolution) ────────────────────────

func test_smear_params_item_json_false_disables() -> void:
	assert_false(Combatant.smear_params({}, "sword", {"smear": false})["enabled"])


func test_smear_params_hero_override_beats_item_json() -> void:
	var hero := {"items": {"sword": {"smear": {"threshold_deg": 60}}}}
	var p := Combatant.smear_params(hero, "sword", {"smear": false})
	assert_true(p["enabled"])
	assert_eq(p["threshold_deg"], 60.0)


func test_smear_params_item_defaults_tier_applies() -> void:
	# Dict params must survive the per-hand unwrap exemption ("smear" is not a
	# per-hand field — a {"threshold_deg": ...} dict is params, not hands).
	var hero := {"item_defaults": {"smear": {"threshold_deg": 33}}}
	assert_eq(Combatant.smear_params(hero, "sword", {})["threshold_deg"], 33.0)


func test_smear_params_missing_everywhere_is_defaults() -> void:
	var p := Combatant.smear_params({}, "sword", {})
	assert_true(p["enabled"])
	assert_eq(p["threshold_deg"], SmearGen.DEFAULT_THRESHOLD_DEG)
