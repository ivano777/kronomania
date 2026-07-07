extends GutTest

# Tests for SpriteRegistry loaders — effect clips from the XPM pipeline and
# combatant animation sheets converted from the CC0 packs (import_pack.py).


func test_fireball_clip_loads() -> void:
	var frames: SpriteFrames = SpriteRegistry.get_effect_frames("Fireball")
	assert_not_null(frames, "Fireball sheet + json should build SpriteFrames")
	if frames == null:
		return
	assert_eq(frames.get_frame_count("default"), 3, "Fireball clip has 3 frames")
	assert_eq(frames.get_animation_speed("default"), 12.0, "fps read from metadata")
	assert_true(frames.get_animation_loop("default"), "loop flag read from metadata")


func test_fireball_frames_are_16px_slices() -> void:
	var frames: SpriteFrames = SpriteRegistry.get_effect_frames("Fireball")
	if frames == null:
		return
	var tex: Texture2D = frames.get_frame_texture("default", 1)
	assert_not_null(tex, "each frame should carry an AtlasTexture slice")
	assert_eq(int(tex.get_width()), 16, "frame slice width from metadata")
	assert_eq(int(tex.get_height()), 16, "frame slice height from metadata")


func test_missing_clip_returns_null() -> void:
	var frames: SpriteFrames = SpriteRegistry.get_effect_frames("DoesNotExist")
	assert_null(frames, "unknown clip should return null (warning logged)")


func test_player_full_animation_set() -> void:
	var frames: SpriteFrames = SpriteRegistry.get_combatant_frames("Player")
	assert_not_null(frames, "player combatant art should exist")
	if frames == null:
		return
	assert_gt(frames.get_frame_count("idle"), 1, "idle is multi-frame")
	assert_true(frames.get_animation_loop("idle"), "idle loops")
	for anim: String in ["attack_melee", "cast_spell", "hurt", "die"]:
		assert_gt(frames.get_frame_count(anim), 0, "%s has frames" % anim)
		assert_false(frames.get_animation_loop(anim), "%s does not loop" % anim)


func test_enemy_animation_sets() -> void:
	for enemy: String in ["Grunt", "Soldier", "Knight"]:
		var frames: SpriteFrames = SpriteRegistry.get_combatant_frames(enemy)
		assert_not_null(frames, "%s combatant art should exist" % enemy)
		if frames == null:
			continue
		assert_gt(frames.get_frame_count("idle"), 1, "%s idle is multi-frame" % enemy)
		assert_true(frames.get_animation_loop("idle"), "%s idle loops" % enemy)
		for anim: String in ["attack_melee", "hurt", "die"]:
			assert_gt(frames.get_frame_count(anim), 0, "%s %s has frames" % [enemy, anim])
		assert_false(frames.get_animation_loop("die"), "%s die freezes on last frame" % enemy)
