extends Node

const _ICON_ROOT := "res://assets/sprites/icons/"
const _COMB_ROOT := "res://assets/sprites/combatants/"
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
