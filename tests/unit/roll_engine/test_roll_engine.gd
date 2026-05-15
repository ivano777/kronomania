extends GutTest

# RollEngine is a stateless autoload — test it in isolation.
# Determinism strategy:
#   - Use seed(N) before resolve() to compare two runs (proves repeatability).
#   - Use die_size=1 where the outcome must be predictable: randi_range(1,1) always = 1.


func test_keep_grade_0_keeps_1_die() -> void:
	var result: Dictionary = RollEngine.resolve(2, 6, 0)
	assert_eq(result["keep_count"] as int, 1, "grade 0 → keep 1 die")


func test_keep_grade_1_keeps_2_dice() -> void:
	var result: Dictionary = RollEngine.resolve(2, 6, 1)
	assert_eq(result["keep_count"] as int, 2, "grade 1 → keep 2 dice")


func test_keep_grade_2_keeps_3_dice() -> void:
	var result: Dictionary = RollEngine.resolve(3, 6, 2)
	assert_eq(result["keep_count"] as int, 3, "grade 2 → keep 3 dice")


func test_keep_capped_by_pool_size() -> void:
	# Pool has 1 die; even with grade 2 we can only keep 1.
	var result: Dictionary = RollEngine.resolve(1, 6, 2)
	assert_eq(result["keep_count"] as int, 1, "keep capped to pool size when pool < grade+1")


func test_negative_net_advantage_triggers_desperation() -> void:
	# tier=1, net_advantage=-1 → pool_size=0 → Desperation
	var result: Dictionary = RollEngine.resolve(1, 6, 0, 0, -1)
	assert_true(result["desperation"] as bool, "pool ≤ 0 triggers Desperation")


func test_desperation_keeps_1_die() -> void:
	var result: Dictionary = RollEngine.resolve(1, 6, 0, 0, -1)
	assert_eq(result["keep_count"] as int, 1, "Desperation always keeps 1 die")


func test_all_dice_max_when_die_size_1() -> void:
	# d1 always rolls 1, which is its maximum face value.
	var result: Dictionary = RollEngine.resolve(3, 1, 0)
	assert_eq(result["primary_dice_maxed_count"] as int, 3,
		"all 3 dice should be maxed when die_size=1")


func test_fervor_die_adds_to_total() -> void:
	# d1 primary pool + d4 fervor die. Total must be >= 2 (1 kept + at least 1 fervor).
	var result: Dictionary = RollEngine.resolve(1, 1, 0, 0, 0, 4)
	assert_gte(result["fervor_roll"] as int, 1, "fervor_roll must be at least 1")
	assert_gte(result["total"] as int, 2, "total includes fervor die")


func test_fervor_die_not_included_in_maxed_count() -> void:
	# Fervor die rolling max should NOT count toward primary_dice_maxed_count.
	# Use fervor_size=1 (always rolls max) and primary die_size=6 (pool of 1, won't max unless 6).
	# primary_dice_maxed_count must be 0 when the primary die doesn't roll 6.
	# We test with die_size=1 for primary — that DOES max — to confirm fervor is separate.
	var result: Dictionary = RollEngine.resolve(1, 1, 0, 0, 0, 1)
	# primary_dice_maxed_count = 1 (the d1), fervor_maxed = true — these are separate fields.
	assert_eq(result["primary_dice_maxed_count"] as int, 1, "primary dice maxed independent of fervor")
	assert_true(result["fervor_maxed"] as bool, "fervor_maxed set when fervor die rolls its max")


func test_fervor_maxed_flag() -> void:
	# fervor_size=1: randi_range(1,1) always = 1 = die max → fervor_maxed = true
	var result: Dictionary = RollEngine.resolve(1, 6, 0, 0, 0, 1)
	assert_true(result["fervor_maxed"] as bool, "fervor_maxed must be true when fervor die = fervor_size")


func test_post_keep_bonus_adds_to_total() -> void:
	# d1 primary, post_keep_bonus_size=4 → bonus roll in [1,4], total >= 2
	var result: Dictionary = RollEngine.resolve(1, 1, 0, 0, 0, 0, 0, 0, 4)
	assert_gte(result["post_keep_bonus_roll"] as int, 1, "post_keep_bonus_roll >= 1")
	assert_gte(result["total"] as int, 2, "total includes post-keep bonus die")


func test_seeded_calls_are_deterministic() -> void:
	seed(99991)
	var r1: Dictionary = RollEngine.resolve(3, 6, 1)
	seed(99991)
	var r2: Dictionary = RollEngine.resolve(3, 6, 1)
	assert_eq(r1["total"] as int, r2["total"] as int, "same seed → same total")
	assert_eq(r1["primary_dice_maxed_count"] as int, r2["primary_dice_maxed_count"] as int,
		"same seed → same maxed count")


func test_flat_bonus_included_in_total() -> void:
	# die_size=1 → kept die = 1, flat = 7 → total must be 8
	var result: Dictionary = RollEngine.resolve(1, 1, 0, 7)
	assert_eq(result["total"] as int, 8, "flat bonus adds directly to total")


func test_no_post_keep_bonus_by_default() -> void:
	var result: Dictionary = RollEngine.resolve(2, 6, 0)
	assert_eq(result["post_keep_bonus_roll"] as int, 0,
		"post_keep_bonus_roll = 0 when not requested")


func test_no_fervor_by_default() -> void:
	var result: Dictionary = RollEngine.resolve(2, 6, 0)
	assert_eq(result["fervor_roll"] as int, 0, "fervor_roll = 0 when fervor_size not set")
	assert_false(result["fervor_maxed"] as bool, "fervor_maxed = false when no fervor")


func test_is_fast_at_exactly_vt() -> void:
	assert_true(RollEngine.is_fast(10, 10), "total == vt → Fast")


func test_is_fast_below_vt() -> void:
	assert_false(RollEngine.is_fast(9, 10), "total < vt → Slow")


func test_is_massive_overflow_greater_than_die() -> void:
	# overflow = 10 - 0 = 10 > 4 → Massive
	assert_true(RollEngine.is_massive(10, 0, 4), "overflow 10 > d4 → Massive")


func test_is_massive_overflow_equals_die_not_massive() -> void:
	# overflow = 4 - 0 = 4, not > 4 → not Massive
	assert_false(RollEngine.is_massive(4, 0, 4), "overflow == defensive_size → NOT Massive")


func test_is_massive_overflow_below_die_not_massive() -> void:
	assert_false(RollEngine.is_massive(3, 0, 4), "overflow < defensive_size → NOT Massive")
