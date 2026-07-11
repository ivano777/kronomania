extends GutTest

# Equip hand-slot rules on PlayerProgression (previously untested — the
# Equipment scene relies on them): two-handed items claim both hands, one-
# handed items evict a two-hander, null unequips. Also covers the Equipment
# scene's icon-fallback initials helper.

const _EQUIP_SCENE := preload("res://scenes/equipment/EquipmentScene.gd")

var _sword: EquipmentData      # 1H
var _greatsword: EquipmentData # 2H
var _shield: EquipmentData     # 1H


func before_each() -> void:
	PlayerProgression.reset()
	_sword = load("res://resources/data/weapons/iron_sword.tres")
	_greatsword = load("res://resources/data/weapons/greatsword.tres")
	_shield = load("res://resources/data/weapons/heater_shield.tres")


func test_equip_main_and_off() -> void:
	PlayerProgression.equip_main_hand(_sword)
	PlayerProgression.equip_off_hand(_shield)
	assert_eq(PlayerProgression.main_hand, _sword)
	assert_eq(PlayerProgression.off_hand, _shield)


func test_two_handed_clears_off_hand() -> void:
	PlayerProgression.equip_main_hand(_sword)
	PlayerProgression.equip_off_hand(_shield)
	PlayerProgression.equip_main_hand(_greatsword)
	assert_eq(PlayerProgression.main_hand, _greatsword)
	assert_null(PlayerProgression.off_hand, "2H main hand must evict the off hand")


func test_two_handed_via_off_hand_lands_in_main() -> void:
	PlayerProgression.equip_off_hand(_greatsword)
	assert_eq(PlayerProgression.main_hand, _greatsword, "2H delegates to main hand")
	assert_null(PlayerProgression.off_hand)


func test_off_hand_over_two_hander_clears_main() -> void:
	PlayerProgression.equip_main_hand(_greatsword)
	PlayerProgression.equip_off_hand(_shield)
	assert_null(PlayerProgression.main_hand, "equipping off hand must evict a 2H main")
	assert_eq(PlayerProgression.off_hand, _shield)


func test_null_unequips() -> void:
	PlayerProgression.equip_main_hand(_sword)
	PlayerProgression.equip_main_hand(null)
	assert_null(PlayerProgression.main_hand)


# ── EquipmentScene.fallback_initials ─────────────────────────────────────────

func test_fallback_initials_two_words() -> void:
	assert_eq(_EQUIP_SCENE.fallback_initials("Iron Sword"), "IS")


func test_fallback_initials_single_word() -> void:
	assert_eq(_EQUIP_SCENE.fallback_initials("Greatsword"), "GR")


func test_fallback_initials_empty() -> void:
	assert_eq(_EQUIP_SCENE.fallback_initials(""), "??")
