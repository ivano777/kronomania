extends GutTest

# Tests for SpriteRegistry.get_effect_frames — builds SpriteFrames from the
# compiled Fireball sample sheet installed by the tools/sprites pipeline.


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
