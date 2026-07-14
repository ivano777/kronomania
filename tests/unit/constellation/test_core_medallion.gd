extends GutTest

# CoreMedallion.tier_to_roman is a pure static mapping — test it without instancing
# the Control (no scene tree needed). MAX_TIER = 4, so I..IV are the expected inputs.


func test_tier_1_is_I() -> void:
	assert_eq(CoreMedallion.tier_to_roman(1), "I")


func test_tier_2_is_II() -> void:
	assert_eq(CoreMedallion.tier_to_roman(2), "II")


func test_tier_3_is_III() -> void:
	assert_eq(CoreMedallion.tier_to_roman(3), "III")


func test_tier_4_is_IV() -> void:
	assert_eq(CoreMedallion.tier_to_roman(4), "IV")


func test_out_of_range_falls_back_to_number() -> void:
	assert_eq(CoreMedallion.tier_to_roman(7), "7", "unexpected tier degrades to its number")
