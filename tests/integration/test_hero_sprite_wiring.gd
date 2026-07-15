extends GutTest

# Verifies the cosmetic hero-variant wiring: the player's battle sprite follows
# PlayerProgression.hero_sprite, while enemies keep using combatant_name.
# Frame width is the discriminator — player pack idle frames are 125px wide,
# the heroine pack is 44px.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _COMBATANT_SCENE = preload("res://scenes/battle/Combatant.tscn")
const _HERO_SELECT_SCENE = preload("res://scenes/hero_select/HeroSelectScene.tscn")

var pp: Node


func before_each() -> void:
	pp = get_node("/root/PlayerProgression")
	pp.reset()


func _make_combatant() -> Node:
	var c = _COMBATANT_SCENE.instantiate()
	add_child_autofree(c)
	return c


func _idle_frame_width(c: Node) -> int:
	var spr = c.get_node("Sprite")
	if spr.sprite_frames == null or not spr.sprite_frames.has_animation("idle"):
		return -1
	var tex = spr.sprite_frames.get_frame_texture("idle", 0)
	return tex.get_width() if tex != null else -1


func test_default_player_loads_player_pack() -> void:
	pp.hero_sprite = "player"
	var c = _make_combatant()
	c.setup(_PLAYER_DATA, true)
	assert_eq(_idle_frame_width(c), 125, "default hero uses player pack (125px idle frame)")


func test_heroine_loads_heroine_pack() -> void:
	pp.hero_sprite = "heroine"
	var c = _make_combatant()
	c.setup(_PLAYER_DATA, true)
	var spr = c.get_node("Sprite")
	assert_not_null(spr.sprite_frames, "heroine sprite frames loaded")
	assert_eq(spr.sprite_frames.get_frame_count("idle"), 8, "heroine idle has 8 frames")
	assert_eq(_idle_frame_width(c), 39, "heroine idle frame is 39px wide (distinct from player pack)")


func test_enemy_ignores_hero_sprite() -> void:
	pp.hero_sprite = "heroine"
	var c = _make_combatant()
	c.setup(_PLAYER_DATA, false)  # is_player=false → keyed by combatant_name "Player"
	assert_eq(_idle_frame_width(c), 125, "enemy path uses combatant_name, not hero_sprite")


func test_hero_select_scene_builds_and_applies_choice() -> void:
	pp.hero_sprite = "player"
	var scene = _HERO_SELECT_SCENE.instantiate()
	add_child_autofree(scene)  # runs _ready(): builds cards + previews without error
	assert_eq(scene._anim_previews.size(), 2, "both hero cards register an animated idle preview")
	scene._apply_choice("heroine")
	assert_eq(pp.hero_sprite, "heroine", "HeroSelectScene._apply_choice sets hero_sprite")
