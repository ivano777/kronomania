extends GutTest

# Unit tests for AttackPresenter's pure static helpers (popup formatting and
# emphasis math). Tween choreography is visual-only and exercised through the
# DebugAttackFX widget, per testing rules.


# ── popup_text ────────────────────────────────────────────────────────────────

func test_popup_text_blocked() -> void:
	assert_eq(AttackPresenter.popup_text(false, false, 0), "Blocked")


func test_popup_text_blocked_ignores_wounds() -> void:
	# Guard held → wounds are irrelevant even if a stale value is passed.
	assert_eq(AttackPresenter.popup_text(false, true, 3), "Blocked")


func test_popup_text_single_wound() -> void:
	assert_eq(AttackPresenter.popup_text(true, false, 1), "-1")


func test_popup_text_amplified_wounds() -> void:
	# Hex amplification can push a normal breach above 1 wound.
	assert_eq(AttackPresenter.popup_text(true, false, 2), "-2")


func test_popup_text_massive() -> void:
	assert_eq(AttackPresenter.popup_text(true, true, 2), "-2 MASSIVE")


func test_popup_text_massive_amplified() -> void:
	assert_eq(AttackPresenter.popup_text(true, true, 3), "-3 MASSIVE")


func test_popup_text_suppressed_wound_breach() -> void:
	# Mind Rend / Time Lock: breach lands but the wound is suppressed.
	assert_eq(AttackPresenter.popup_text(true, false, 0), "Breached!")


# ── popup_color ───────────────────────────────────────────────────────────────

func test_popup_color_blocked_is_gray() -> void:
	assert_eq(AttackPresenter.popup_color(false, false), AttackPresenter.COLOR_BLOCKED)


func test_popup_color_wound_is_white() -> void:
	assert_eq(AttackPresenter.popup_color(true, false), AttackPresenter.COLOR_WOUND)


func test_popup_color_massive_is_orange() -> void:
	assert_eq(AttackPresenter.popup_color(true, true), AttackPresenter.COLOR_MASSIVE)


# ── impact_clip_name ──────────────────────────────────────────────────────────

func test_impact_clip_name_defaults_to_generic_burst() -> void:
	assert_eq(AttackPresenter.impact_clip_name(""), "ImpactBurst")


func test_impact_clip_name_uses_action_clip_when_set() -> void:
	assert_eq(AttackPresenter.impact_clip_name("SlashDiagonal"), "SlashDiagonal")


# ── FX intensity mapping ──────────────────────────────────────────────────────

func test_fx_scale_d4_is_minimum() -> void:
	assert_almost_eq(AttackPresenter.fx_scale_for_die(4), 0.85, 0.001)


func test_fx_scale_d6_is_baseline() -> void:
	assert_almost_eq(AttackPresenter.fx_scale_for_die(6), 1.0, 0.001)


func test_fx_scale_d12_is_maximum() -> void:
	assert_almost_eq(AttackPresenter.fx_scale_for_die(12), 1.45, 0.001)


func test_fx_scale_clamps_out_of_track_sizes() -> void:
	assert_almost_eq(AttackPresenter.fx_scale_for_die(2), 0.85, 0.001)
	assert_almost_eq(AttackPresenter.fx_scale_for_die(20), 1.45, 0.001)


func test_fx_count_no_node_is_one() -> void:
	# Enemies and unlearned nodes report level 0 — still one FX instance.
	assert_eq(AttackPresenter.fx_count_for_level(0), 1)


func test_fx_count_matches_node_level() -> void:
	assert_eq(AttackPresenter.fx_count_for_level(2), 2)
	assert_eq(AttackPresenter.fx_count_for_level(3), 3)


func test_fx_count_clamps_above_three() -> void:
	assert_eq(AttackPresenter.fx_count_for_level(5), 3)


func test_rarity_tint_common_is_untinted() -> void:
	assert_eq(AttackPresenter.rarity_tint("common"), Color.WHITE)


func test_rarity_tint_unknown_is_untinted() -> void:
	assert_eq(AttackPresenter.rarity_tint("mythic"), Color.WHITE)


func test_rarity_tint_relic_is_gold() -> void:
	assert_eq(AttackPresenter.rarity_tint("relic"), Color(1.0, 0.86, 0.55))


func test_rarity_scale_bonus_progression() -> void:
	assert_almost_eq(AttackPresenter.rarity_scale_bonus("common"), 0.0, 0.001)
	assert_almost_eq(AttackPresenter.rarity_scale_bonus("fine"), 0.05, 0.001)
	assert_almost_eq(AttackPresenter.rarity_scale_bonus("arcane"), 0.10, 0.001)
	assert_almost_eq(AttackPresenter.rarity_scale_bonus("relic"), 0.15, 0.001)
	assert_almost_eq(AttackPresenter.rarity_scale_bonus("unknown"), 0.0, 0.001)


# ── projectile_flip_h ─────────────────────────────────────────────────────────

func test_projectile_faces_right_when_flying_right() -> void:
	# Player (left) shooting an enemy (right): clip's authored facing, no flip.
	assert_false(AttackPresenter.projectile_flip_h(85.0, 360.0))


func test_projectile_flips_when_flying_left() -> void:
	# Enemy (right) shooting the player (left): mirrored.
	assert_true(AttackPresenter.projectile_flip_h(360.0, 85.0))


# ── emphasis_offset ───────────────────────────────────────────────────────────

func test_emphasis_offset_zero_weight_is_identity() -> void:
	var from := Vector2(85, 190)
	assert_eq(AttackPresenter.emphasis_offset(from, Vector2(320, 235), 0.0), from)


func test_emphasis_offset_full_weight_is_lane_point() -> void:
	var lane := Vector2(320, 235)
	assert_eq(AttackPresenter.emphasis_offset(Vector2(85, 190), lane, 1.0), lane)


func test_emphasis_offset_moves_toward_lane() -> void:
	var from := Vector2(360, 285)
	var lane := Vector2(320, 235)
	var out: Vector2 = AttackPresenter.emphasis_offset(from, lane, 0.2)
	# 20% of the way: each axis strictly between start and lane.
	assert_true(out.x < from.x and out.x > lane.x, "x moves toward lane")
	assert_true(out.y < from.y and out.y > lane.y, "y moves toward lane")
	assert_almost_eq(out.x, 352.0, 0.001)
	assert_almost_eq(out.y, 275.0, 0.001)
