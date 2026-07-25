extends GutTest

# Unit tests for the held-equipment overlay: pure anchor math, manifest
# parsing, and manifest/art consistency. Overlay rendering is visual-only,
# exercised by equipping weapons in the Equipment screen.

const FRAME := Vector2(39, 69)
const HAND := Vector2i(26, 42)
const GRIP := Vector2i(5, 5)
const TEX := Vector2(33, 10)


# ── slot transform math ───────────────────────────────────────────────────────

func test_slot_position_unflipped() -> void:
	assert_eq(Combatant.held_slot_position(FRAME, HAND, false), Vector2(6.5, 7.5))


func test_slot_position_flipped_mirrors_x() -> void:
	assert_eq(Combatant.held_slot_position(FRAME, HAND, true), Vector2(-6.5, 7.5))


func test_slot_offset_puts_grip_on_origin() -> void:
	assert_eq(Combatant.held_slot_offset(GRIP, TEX, false), Vector2(-5, -5))
	# flipped: grip x becomes 33-1-5 = 27
	assert_eq(Combatant.held_slot_offset(GRIP, TEX, true), Vector2(-27, -5))


func test_slot_offset_flip_v_mirrors_y() -> void:
	# flip_v: grip y becomes 10-1-5 = 4
	assert_eq(Combatant.held_slot_offset(GRIP, TEX, false, true), Vector2(-5, -4))
	assert_eq(Combatant.held_slot_offset(GRIP, TEX, true, true), Vector2(-27, -4))


func test_rotation_negates_when_flipped() -> void:
	assert_eq(Combatant.held_rotation(30.0, false), 30.0)
	assert_eq(Combatant.held_rotation(30.0, true), -30.0)


# ── anchor_entry resolution ───────────────────────────────────────────────────

const META := {
	"main": [26, 42],
	"idle_bob": [0, 0, 1, 0],
	"anims": {
		"attack_melee": {
			"main": [[26, 41, 0], [5, 35, -150], [33, 31, -20]],
		},
	},
}


func test_anchor_per_frame_lookup() -> void:
	assert_eq(Combatant.anchor_entry(META, "attack_melee", "main", 1), [5, 35, -150])


func test_anchor_frame_clamps_to_last() -> void:
	assert_eq(Combatant.anchor_entry(META, "attack_melee", "main", 99), [33, 31, -20])


func test_anchor_missing_hand_in_anim_hides() -> void:
	assert_null(Combatant.anchor_entry(META, "attack_melee", "off", 0))


func test_anchor_missing_anim_hides() -> void:
	assert_null(Combatant.anchor_entry(META, "cast_spell", "main", 0))


func test_anchor_idle_legacy_fallback_with_bob() -> void:
	assert_eq(Combatant.anchor_entry(META, "idle", "main", 2), [26, 43])
	assert_eq(Combatant.anchor_entry(META, "idle", "main", 0), [26, 42])


func test_anchor_idle_legacy_missing_hand_hides() -> void:
	assert_null(Combatant.anchor_entry(META, "idle", "off", 0))


# ── manifest parsing ──────────────────────────────────────────────────────────

func test_json_v2i_parses_pair() -> void:
	assert_eq(Combatant.json_v2i([27, 5], Vector2i.ZERO), Vector2i(27, 5))


func test_json_v2i_malformed_falls_back() -> void:
	assert_eq(Combatant.json_v2i(null, Vector2i(1, 2)), Vector2i(1, 2))
	assert_eq(Combatant.json_v2i([1], Vector2i(1, 2)), Vector2i(1, 2))
	assert_eq(Combatant.json_v2i("x", Vector2i(1, 2)), Vector2i(1, 2))


func test_get_held_missing_key_null_no_warning() -> void:
	assert_null(SpriteRegistry.get_held("no_such_weapon"))


func test_held_meta_missing_key_empty() -> void:
	assert_eq(SpriteRegistry.get_held_meta("no_such_weapon"), {})


func test_hero_meta_missing_hero_empty() -> void:
	assert_eq(SpriteRegistry.get_hero_held_meta("no_such_hero"), {})


# ── manifest / art consistency ────────────────────────────────────────────────

func test_iron_sword_held_art_and_grip_installed() -> void:
	assert_not_null(SpriteRegistry.get_held("iron_sword"))
	var grip := Combatant.json_v2i(
			SpriteRegistry.get_held_meta("iron_sword").get("grip"), Vector2i(-1, -1))
	assert_ne(grip, Vector2i(-1, -1), "iron_sword.json missing grip")


func test_every_held_grip_json_has_art() -> void:
	var dir := DirAccess.open("res://assets/sprites/held")
	assert_not_null(dir)
	for file in dir.get_files():
		if file.ends_with(".json"):
			var key := file.trim_suffix(".json")
			assert_not_null(SpriteRegistry.get_held(key),
					"grip manifest without held art: %s" % key)


func test_refresh_held_before_setup_is_safe() -> void:
	var comb: Combatant = (load("res://scenes/battle/Combatant.tscn") as PackedScene).instantiate()
	add_child_autofree(comb)
	comb.refresh_held()  # no setup() yet — must not crash or create slots
	assert_true(true, "refresh_held before setup did not crash")


func test_refresh_held_rebinds_after_equip_change() -> void:
	var comb: Combatant = (load("res://scenes/battle/Combatant.tscn") as PackedScene).instantiate()
	add_child_autofree(comb)
	var prev_hero: String = PlayerProgression.hero_sprite
	var prev_main: EquipmentData = PlayerProgression.main_hand
	PlayerProgression.hero_sprite = "heroine"
	PlayerProgression.main_hand = load("res://resources/data/weapons/iron_sword.tres")
	var pd: CombatantData = load("res://resources/data/player_default.tres")
	comb.setup(pd, true)
	PlayerProgression.main_hand = null
	comb.refresh_held()
	# after unequip + refresh, no held texture may remain bound
	var bound := 0
	for child in comb.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			bound += 1
	assert_eq(bound, 0, "held overlay still bound after unequip refresh")
	PlayerProgression.hero_sprite = prev_hero
	PlayerProgression.main_hand = prev_main


func test_heroine_manifest_complete() -> void:
	var meta := SpriteRegistry.get_hero_held_meta("heroine")
	assert_true(meta.has("main"), "heroine held.json missing main anchor")
	assert_true(meta.has("off"), "heroine held.json missing off anchor")
	var bob: Array = meta.get("idle_bob", [])
	assert_eq(bob.size(), 8, "heroine idle_bob must cover the 8-frame idle loop")


# ── draw-order resolution ─────────────────────────────────────────────────────

func test_order_default_when_absent() -> void:
	assert_eq(Combatant.held_order({}, "main"), ["hero", "weapon", "hand"])


func test_order_string_applies_to_both_hands() -> void:
	var meta := {"order": "hero;weapon"}
	assert_eq(Combatant.held_order(meta, "main"), ["hero", "weapon"])
	assert_eq(Combatant.held_order(meta, "off"), ["hero", "weapon"])


func test_order_per_hand_object() -> void:
	var meta := {"order": {"main": "hero;weapon", "off": "weapon;hero"}}
	assert_eq(Combatant.held_order(meta, "main"), ["hero", "weapon"])
	assert_eq(Combatant.held_order(meta, "off"), ["weapon", "hero"])


func test_order_object_missing_hand_falls_back() -> void:
	var meta := {"order": {"off": "weapon;hero"}}
	assert_eq(Combatant.held_order(meta, "main"), ["hero", "weapon", "hand"])


func test_order_unknown_token_falls_back() -> void:
	assert_eq(Combatant.held_order({"order": "hero;sword"}, "main"),
			["hero", "weapon", "hand"])


func test_order_missing_required_token_falls_back() -> void:
	assert_eq(Combatant.held_order({"order": "weapon;hand"}, "main"),
			["hero", "weapon", "hand"])


func test_layer_z_default_bands() -> void:
	var order := Combatant.held_order({}, "main")
	assert_eq(Combatant.held_layer_z(order, "weapon"), 1)
	assert_eq(Combatant.held_layer_z(order, "hand"), 2)


func test_layer_z_weapon_behind_hero_negative() -> void:
	assert_eq(Combatant.held_layer_z(["weapon", "hero"], "weapon"), -1)


# ── back-variant grip fallback ────────────────────────────────────────────────

func test_back_grip_prefers_back_meta() -> void:
	assert_eq(Combatant.held_back_grip({"grip": [8, 8]}, {"grip": [3, 5]}), [3, 5])


func test_back_grip_falls_back_to_front() -> void:
	assert_eq(Combatant.held_back_grip({"grip": [8, 8]}, {}), [8, 8])


# ── glove fine offset ─────────────────────────────────────────────────────────

func test_glove_offset_zero_when_absent() -> void:
	assert_eq(Combatant.held_glove_offset({}, "main", false), Vector2.ZERO)


func test_glove_offset_reads_hand_and_mirrors_x() -> void:
	var meta := {"glove_off": {"main": [2, -3], "off": [1, 4]}}
	assert_eq(Combatant.held_glove_offset(meta, "main", false), Vector2(2, -3))
	assert_eq(Combatant.held_glove_offset(meta, "main", true), Vector2(-2, -3))
	assert_eq(Combatant.held_glove_offset(meta, "off", false), Vector2(1, 4))


func test_glove_offset_ignores_rot_component() -> void:
	assert_eq(Combatant.held_glove_offset({"glove_off": {"main": [2, -3, 45]}},
			"main", false), Vector2(2, -3))


func test_glove_rot_zero_when_absent_or_legacy() -> void:
	assert_eq(Combatant.held_glove_rot({}, "main", false), 0.0)
	# legacy 2-element entry has no rotation
	assert_eq(Combatant.held_glove_rot({"glove_off": {"main": [2, 3]}}, "main", false), 0.0)


func test_glove_rot_reads_and_negates_on_flip() -> void:
	var meta := {"glove_off": {"main": [0, 0, 20], "off": [0, 0, -10]}}
	assert_eq(Combatant.held_glove_rot(meta, "main", false), 20.0)
	assert_eq(Combatant.held_glove_rot(meta, "main", true), -20.0)
	assert_eq(Combatant.held_glove_rot(meta, "off", false), -10.0)


# ── glove + shield-back install ───────────────────────────────────────────────

func test_glove_art_and_grip_installed() -> void:
	assert_not_null(SpriteRegistry.get_held("_glove"), "held/_glove.png missing")
	var grip := Combatant.json_v2i(
			SpriteRegistry.get_held_meta("_glove").get("grip"), Vector2i(-1, -1))
	assert_ne(grip, Vector2i(-1, -1), "_glove.json missing grip")


func test_shield_back_art_installed() -> void:
	assert_not_null(SpriteRegistry.get_held("heater_shield_back"),
			"heater_shield_back.png missing")


func test_shield_orders_hide_glove_and_flip_off_hand_behind() -> void:
	var meta := SpriteRegistry.get_held_meta("heater_shield")
	var main_order := Combatant.held_order(meta, "main")
	var off_order := Combatant.held_order(meta, "off")
	assert_false("hand" in main_order, "shield face must cover the fist (no glove)")
	assert_false("hand" in off_order, "off-hand shield draws no glove")
	assert_lt(Combatant.held_layer_z(off_order, "weapon"), 0,
			"off-hand shield must render behind the body")


# ── per-hero override chain (item_defaults → items) ───────────────────────────

const OVR_META := {
	"main": [26, 42],
	"anims": {
		"idle": {"main": [[26, 42, 10], [27, 43, 10]]},
	},
	"item_defaults": {"flip_h": true, "rot": 5, "pos": [0, 1]},
	"items": {
		"iron_sword": {"rot": -15, "pos": [2, 0]},
		"heater_shield_back": {"flip_h": false, "flip_v": true},
		"arcane_focus": {"anims": {"idle": {"main": [[30, 40, -90], [31, 41, -90]]}}},
	},
}


func test_override_field_tier3_beats_tier2() -> void:
	assert_eq(Combatant.held_override_field(OVR_META, "iron_sword", "rot"), -15)
	assert_eq(Combatant.held_override_field(OVR_META, "iron_sword", "pos"), [2, 0])


func test_override_field_tier2_when_item_silent() -> void:
	# iron_sword authors no flip_h → falls through to item_defaults
	assert_eq(Combatant.held_override_field(OVR_META, "iron_sword", "flip_h"), true)
	# unlisted item → item_defaults serves everything it authors
	assert_eq(Combatant.held_override_field(OVR_META, "crude_club", "rot"), 5)


func test_override_field_null_when_no_tier_authors() -> void:
	assert_null(Combatant.held_override_field({}, "iron_sword", "rot"))
	assert_null(Combatant.held_override_field(OVR_META, "iron_sword", "grip"))


func test_override_field_explicit_null_falls_through() -> void:
	var meta := {"item_defaults": {"rot": 5}, "items": {"iron_sword": {"rot": null}}}
	assert_eq(Combatant.held_override_field(meta, "iron_sword", "rot"), 5)


func test_held_flip_chain_beats_art_meta() -> void:
	# tier 3 explicit false wins over the art's own flip_h true
	assert_false(Combatant.held_flip(OVR_META, "heater_shield_back", {"flip_h": true}, "flip_h"))
	assert_true(Combatant.held_flip(OVR_META, "heater_shield_back", {}, "flip_v"))
	# no override chain → art meta rules
	assert_true(Combatant.held_flip({}, "heater_shield", {"flip_h": true}, "flip_h"))
	assert_false(Combatant.held_flip({}, "heater_shield", {}, "flip_h"))


func test_held_ovr_deltas_replace_not_stack() -> void:
	# tier 3 rot -15 replaces tier 2 rot 5 — never -10
	assert_eq(Combatant.held_ovr_rot(OVR_META, "iron_sword"), -15.0)
	assert_eq(Combatant.held_ovr_pos(OVR_META, "iron_sword"), Vector2i(2, 0))
	# tier 2 serves items without their own entry
	assert_eq(Combatant.held_ovr_rot(OVR_META, "crude_club"), 5.0)
	assert_eq(Combatant.held_ovr_pos(OVR_META, "crude_club"), Vector2i(0, 1))
	# empty chain → zeros
	assert_eq(Combatant.held_ovr_rot({}, "iron_sword"), 0.0)
	assert_eq(Combatant.held_ovr_pos({}, "iron_sword"), Vector2i.ZERO)


func test_held_ovr_malformed_values_zero() -> void:
	var meta := {"items": {"iron_sword": {"rot": "big", "pos": [1]}}}
	assert_eq(Combatant.held_ovr_rot(meta, "iron_sword"), 0.0)
	assert_eq(Combatant.held_ovr_pos(meta, "iron_sword"), Vector2i.ZERO)


func test_anchor_for_item_override_table_wins() -> void:
	assert_eq(Combatant.anchor_entry_for_item(OVR_META, "arcane_focus", "idle", "main", 1),
			[31, 41, -90])


func test_anchor_for_item_miss_falls_through_to_hero() -> void:
	# arcane_focus override lacks "off" and any other anim → hero tables serve
	assert_eq(Combatant.anchor_entry_for_item(OVR_META, "arcane_focus", "idle", "main", 0),
			[30, 40, -90])
	assert_null(Combatant.anchor_entry_for_item(OVR_META, "arcane_focus", "idle", "off", 0))
	assert_eq(Combatant.anchor_entry_for_item(OVR_META, "iron_sword", "idle", "main", 1),
			[27, 43, 10])


func test_anchor_for_item_no_override_matches_plain_entry() -> void:
	assert_eq(Combatant.anchor_entry_for_item(OVR_META, "crude_club", "idle", "main", 0),
			Combatant.anchor_entry(OVR_META, "idle", "main", 0))


# ── per-hand override values ──────────────────────────────────────────────────

const HAND_META := {
	"item_defaults": {"rot": 5},
	"items": {
		"iron_sword": {"rot": {"main": -15, "off": 30}, "pos": {"off": [1, 2]}},
		"heater_shield": {"flip_h": {"off": true}},
	},
}


func test_hand_value_unwraps_object_and_passes_scalar() -> void:
	assert_eq(Combatant.held_hand_value({"main": 3, "off": 7}, "off"), 7)
	assert_null(Combatant.held_hand_value({"off": 7}, "main"))
	assert_eq(Combatant.held_hand_value(12, "main"), 12)


func test_per_hand_rot_resolves_by_hand() -> void:
	assert_eq(Combatant.held_ovr_rot(HAND_META, "iron_sword", "main"), -15.0)
	assert_eq(Combatant.held_ovr_rot(HAND_META, "iron_sword", "off"), 30.0)


func test_per_hand_missing_hand_falls_to_lower_tier() -> void:
	# pos authored for off only → main falls through the chain (no tier-2 pos → zero)
	assert_eq(Combatant.held_ovr_pos(HAND_META, "iron_sword", "off"), Vector2i(1, 2))
	assert_eq(Combatant.held_ovr_pos(HAND_META, "iron_sword", "main"), Vector2i.ZERO)


func test_per_hand_flip_only_named_hand() -> void:
	assert_true(Combatant.held_flip(HAND_META, "heater_shield", {}, "flip_h", "off"))
	assert_false(Combatant.held_flip(HAND_META, "heater_shield", {}, "flip_h", "main"))


func test_per_hand_art_meta_flip_unwraps() -> void:
	# the item's own held/<key>.json flag may itself be per-hand
	var art := {"flip_h": {"off": true}}
	assert_true(Combatant.held_flip({}, "heater_shield", art, "flip_h", "off"))
	assert_false(Combatant.held_flip({}, "heater_shield", art, "flip_h", "main"))


func test_per_hand_miss_falls_to_tier2_scalar() -> void:
	var meta := {"item_defaults": {"rot": 5}, "items": {"iron_sword": {"rot": {"off": 9}}}}
	assert_eq(Combatant.held_ovr_rot(meta, "iron_sword", "off"), 9.0)
	# main not authored at tier 3 → tier-2 scalar serves it
	assert_eq(Combatant.held_ovr_rot(meta, "iron_sword", "main"), 5.0)
