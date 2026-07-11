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


# ── popup_color ───────────────────────────────────────────────────────────────

func test_popup_color_blocked_is_gray() -> void:
	assert_eq(AttackPresenter.popup_color(false, false), AttackPresenter.COLOR_BLOCKED)


func test_popup_color_wound_is_white() -> void:
	assert_eq(AttackPresenter.popup_color(true, false), AttackPresenter.COLOR_WOUND)


func test_popup_color_massive_is_orange() -> void:
	assert_eq(AttackPresenter.popup_color(true, true), AttackPresenter.COLOR_MASSIVE)


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
