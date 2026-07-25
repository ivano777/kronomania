extends Node

const _ICON_ROOT := "res://assets/sprites/icons/"
const _HELD_ROOT := "res://assets/sprites/held/"
const _COMB_ROOT := "res://assets/sprites/combatants/"
const _FX_ROOT := "res://assets/sprites/effects/"
const _BG_ROOT := "res://assets/sprites/backgrounds/"
const _ANIM_NAMES := ["idle", "attack_melee", "cast_spell", "hurt", "die"]

# Converts a display name to a file-system key.
static func icon_key(display_name: String) -> String:
	return display_name.to_lower().replace(" ", "_")

# Returns the in-hand overlay sprite for an equipment key, or null. Silent on
# miss: held art is rolled out weapon-by-weapon, so absences are expected and
# the overlay simply stays hidden.
func get_held(key: String) -> Texture2D:
	var path := "%s%s.png" % [_HELD_ROOT, key]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ── Held-equipment placement manifests ────────────────────────────────────────
# Formal per-hero / per-item positioning convention (all coords in raw sheet
# pixels, i.e. the UNFLIPPED facing; runtime mirroring is applied by Combatant):
#   assets/sprites/held/<key>.json            → {"grip": [x, y]} — the pixel of
#     the held art that sits in the hand. Held art is authored VERTICAL (tip
#     up, grip on the symmetry axis); anchor-table rot° is absolute tilt from
#     vertical, so one per-hero table serves every item.
#     Optional "flip_h"/"flip_v": mirror the art (bool); stacks on the hero
#     facing flip, rotation unaffected. Read from the art actually shown, so a
#     <key>_back variant carries its OWN flip (front's flip does not apply to
#     the back). Optional "order": draw layers for the hand slot, tokens "hero"/"weapon"/
#     "hand" joined by ";", first = drawn deepest. Default "hero;weapon;hand"
#     (item over hero, shared glove over the item). Omit "hand" → no glove
#     (e.g. shield face covers the fist). String = both hands; object form
#     {"main": ..., "off": ...} overrides per hand, missing key → default.
#     A slot whose order puts "weapon" before "hero" renders BEHIND the body
#     and swaps to <key>_back.png when installed (internal side of asymmetric
#     items, e.g. shields); same grip applies. Glove art is the shared
#     held/_glove.png (+_glove.json grip) — underscore keeps it off the
#     item-key namespace; missing glove art simply draws no glove.
#   assets/sprites/combatants/<hero>/held.json → {"main": [x, y], "off": [x, y],
#     "idle_bob": [8 ints]} — hand anchors + per-frame idle breathing offset.
#     "main" = the character's RIGHT hand (front / weapon hand), "off" = LEFT
#     (back hand). No manifest → that hero shows no held overlays. Optional
#     "glove_off": {"main": [dx, dy, drot], "off": [dx, dy, drot]} nudges the
#     shared glove off the hand anchor and rotates it relative to the weapon
#     angle (unflipped px/deg, mirrored at runtime; 2-element legacy entry =
#     drot 0); absent = 0.
#     Optional per-hero override chain on top of the item's own json (tier 1):
#     "item_defaults" (tier 2 — every item this hero holds) and "items":
#     {"<key>": {...}} (tier 3 — one item). Fields, each resolved independently,
#     highest tier with a non-null value wins outright (replace, never stack;
#     null/missing falls through):
#       "flip_h"/"flip_v" (bool) — art mirror, keyed by the SHOWN art's key
#         (a <key>_back entry overrides only the back variant);
#       "pos" [dx, dy] / "rot" (deg) — deltas added to the resolved anchor
#         entry (unflipped terms, mirrored/negated at runtime), keyed by the
#         item key;
#       each of the four may be a scalar (both hands) or a per-hand object
#         {"main": ..., "off": ...} — a missing hand counts as unauthored and
#         falls through the chain (also honoured on the item's own flip flags);
#       "anims" — per-frame anchor tables (same schema as the hero-level
#         "anims"); a miss inside them (anim/hand/empty) falls through to the
#         hero-level tables, so an item override cannot hide a hand.
#     Resolution lives in Combatant.held_override_field and friends.

func get_held_meta(key: String) -> Dictionary:
	return _load_json("%s%s.json" % [_HELD_ROOT, key])


func get_hero_held_meta(hero_key: String) -> Dictionary:
	return _load_json("%s%s/held.json" % [_COMB_ROOT, hero_key])


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# Returns Texture2D or null. Prints a warning on miss so missing art is easy to spot.
func get_icon(category: String, key: String) -> Texture2D:
	var path := "%s%s/%s.png" % [_ICON_ROOT, category, key]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("SpriteRegistry: missing icon — %s" % path)
	return null

# Returns a 640x360 scene background (tools/sprites/import_env.py output) or
# null. Silent on miss — scenes keep their flat-color fallback by design.
func get_background(key: String) -> Texture2D:
	var path := "%s%s.png" % [_BG_ROOT, key]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# Slices a compiled sheet + metadata JSON (tools/sprites pipeline, horizontal
# strip) into the named animation on an existing SpriteFrames. False on miss.
func _add_sheet_animation(frames: SpriteFrames, anim: String, sheet_path: String, meta_path: String) -> bool:
	if not ResourceLoader.exists(sheet_path) or not FileAccess.file_exists(meta_path):
		return false
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (meta is Dictionary):
		push_warning("SpriteRegistry: bad sheet metadata — %s" % meta_path)
		return false
	var sheet := load(sheet_path) as Texture2D
	var fw := int(meta["frame_width"])
	var fh := int(meta["frame_height"])
	if not frames.has_animation(anim):
		frames.add_animation(anim)
	frames.set_animation_speed(anim, float(meta["fps"]))
	frames.set_animation_loop(anim, bool(meta["loop"]))
	for i: int in int(meta["frame_count"]):
		var region := AtlasTexture.new()
		region.atlas = sheet
		region.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim, region)
	return true

# Builds SpriteFrames from a compiled effect sheet + metadata JSON produced by
# the tools/sprites pipeline (horizontal strip). Returns null on miss so the
# caller can skip the VFX.
func get_effect_frames(clip_name: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var sheet_path := "%s%s_sheet.png" % [_FX_ROOT, clip_name]
	var meta_path := "%s%s_sheet.json" % [_FX_ROOT, clip_name]
	if not _add_sheet_animation(frames, "default", sheet_path, meta_path):
		push_warning("SpriteRegistry: missing effect clip — %s" % sheet_path)
		return null
	return frames

# Builds SpriteFrames from combatants/{key}/. Each animation is either a
# multi-frame sheet pair (<anim>_sheet.png + <anim>_sheet.json, pipeline
# format) or a single-frame <anim>.png — the sheet wins when both exist.
# Returns null if no PNGs are found so the caller can keep the ColorRect fallback.
func get_combatant_frames(combatant_name: String) -> SpriteFrames:
	var key := combatant_name.to_lower().replace(" ", "_")
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	var has_any := false
	for anim: String in _ANIM_NAMES:
		var base := "%s%s/%s" % [_COMB_ROOT, key, anim]
		if _add_sheet_animation(frames, anim, base + "_sheet.png", base + "_sheet.json"):
			has_any = true
			continue
		frames.add_animation(anim)
		var path := base + ".png"
		if ResourceLoader.exists(path):
			frames.add_frame(anim, load(path) as Texture2D)
			has_any = true
	return frames if has_any else null
