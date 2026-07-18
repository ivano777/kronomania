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
