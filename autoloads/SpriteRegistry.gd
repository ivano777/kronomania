extends Node

const _ICON_ROOT := "res://assets/sprites/icons/"
const _COMB_ROOT := "res://assets/sprites/combatants/"
const _FX_ROOT := "res://assets/sprites/effects/"
const _ANIM_NAMES := ["idle", "attack_melee", "cast_spell", "hurt", "die"]

# Converts a display name to a file-system key.
static func icon_key(display_name: String) -> String:
	return display_name.to_lower().replace(" ", "_")

# Returns Texture2D or null. Prints a warning on miss so missing art is easy to spot.
func get_icon(category: String, key: String) -> Texture2D:
	var path := "%s%s/%s.png" % [_ICON_ROOT, category, key]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("SpriteRegistry: missing icon — %s" % path)
	return null

# Builds SpriteFrames from a compiled effect sheet + metadata JSON produced by
# the tools/sprites pipeline (horizontal strip). Returns null on miss so the
# caller can skip the VFX.
func get_effect_frames(clip_name: String) -> SpriteFrames:
	var sheet_path := "%s%s_sheet.png" % [_FX_ROOT, clip_name]
	var meta_path := "%s%s_sheet.json" % [_FX_ROOT, clip_name]
	if not ResourceLoader.exists(sheet_path) or not FileAccess.file_exists(meta_path):
		push_warning("SpriteRegistry: missing effect clip — %s" % sheet_path)
		return null
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (meta is Dictionary):
		push_warning("SpriteRegistry: bad effect metadata — %s" % meta_path)
		return null
	var sheet := load(sheet_path) as Texture2D
	var fw := int(meta["frame_width"])
	var fh := int(meta["frame_height"])
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", float(meta["fps"]))
	frames.set_animation_loop("default", bool(meta["loop"]))
	for i: int in int(meta["frame_count"]):
		var region := AtlasTexture.new()
		region.atlas = sheet
		region.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame("default", region)
	return frames

# Builds SpriteFrames from per-animation PNGs in combatants/{key}/.
# Returns null if no PNGs are found so the caller can keep the ColorRect fallback.
func get_combatant_frames(combatant_name: String) -> SpriteFrames:
	var key := combatant_name.to_lower().replace(" ", "_")
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	var has_any := false
	for anim: String in _ANIM_NAMES:
		frames.add_animation(anim)
		var path := "%s%s/%s.png" % [_COMB_ROOT, key, anim]
		if ResourceLoader.exists(path):
			frames.add_frame(anim, load(path) as Texture2D)
			has_any = true
	return frames if has_any else null
