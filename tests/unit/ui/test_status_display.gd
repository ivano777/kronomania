extends GutTest

# Unit tests for the status-icon display formatters (CustomTooltip statics) and
# the CombatManager status accessor. Square rendering / hover choreography is
# visual-only, exercised via Training Room casts.

const CustomTooltipScript := preload("res://scenes/ui/CustomTooltip.gd")


# ── status_display_name ───────────────────────────────────────────────────────

func test_display_name_known_status() -> void:
	assert_eq(CustomTooltipScript.status_display_name("hex_marked"), "Hexed")


func test_display_name_unknown_status_prettified() -> void:
	assert_eq(CustomTooltipScript.status_display_name("purple_hollow_boon"), "Purple Hollow Boon")


# ── status_duration_text ──────────────────────────────────────────────────────

func test_duration_permanent() -> void:
	assert_eq(CustomTooltipScript.status_duration_text(-1), "Permanent")


func test_duration_single_round() -> void:
	assert_eq(CustomTooltipScript.status_duration_text(1), "1 round")


func test_duration_plural_rounds() -> void:
	assert_eq(CustomTooltipScript.status_duration_text(3), "3 rounds")


# ── status_description ────────────────────────────────────────────────────────

func test_description_known_status_nonempty() -> void:
	assert_true(CustomTooltipScript.status_description("time_locked").length() > 0)


func test_description_unknown_status_empty() -> void:
	assert_eq(CustomTooltipScript.status_description("no_such_status"), "")


# ── every known status has a stub square color ────────────────────────────────

func test_status_colors_cover_catalog() -> void:
	for status_id in CustomTooltipScript.STATUS_INFO:
		assert_true(CombatantHUD.STATUS_COLORS.has(status_id),
				"missing stub color for %s" % status_id)


# ── CombatManager.get_active_statuses guards ──────────────────────────────────

func test_accessor_out_of_range_enemy_returns_empty() -> void:
	assert_eq(CombatManager.get_active_statuses(false, 999), [])
