class_name Combatant
extends Node2D

const COLOR_PLAYER := Color(0.20, 0.35, 0.80, 1.0)
const COLOR_ENEMY  := Color(0.80, 0.20, 0.20, 1.0)

const _FLASH_SHADER := preload("res://assets/shaders/impact_flash.gdshader")
const FLASH_S := 0.18

# Held-equipment overlay (player only). Placement is data-driven: per-hero hand
# anchors + idle bob live in assets/sprites/combatants/<hero>/held.json, per-item
# grip pixels in assets/sprites/held/<key>.json (schema doc in SpriteRegistry).
# Idle-only for now: other anims hide the overlay and the attack FX layer
# carries the action.

var _is_dead := false
var _sprite_key := ""
var _held_main: Sprite2D
var _held_off: Sprite2D
var _glove_main: Sprite2D
var _glove_off: Sprite2D
var _held_info: Dictionary = {}   # hand -> {"planted": bool}
var _hero_meta: Dictionary = {}
var _frame_size := Vector2.ZERO

@onready var _body:       ColorRect        = $Body
@onready var _sprite:     AnimatedSprite2D = $Sprite
@onready var _name_label: Label            = $NameLabel


func _ready() -> void:
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.animation_changed.connect(_update_held_frame)
	_sprite.frame_changed.connect(_update_held_frame)
	# Per-instance flash material (a shared one would flash every combatant at once).
	var mat := ShaderMaterial.new()
	mat.shader = _FLASH_SHADER
	_sprite.material = mat


func setup(data: CombatantData, is_player: bool) -> void:
	_name_label.text = data.combatant_name
	_body.color = COLOR_PLAYER if is_player else COLOR_ENEMY
	_sprite.flip_h = is_player
	# Player sprite folder is chosen at New Game (cosmetic hero variant); enemies
	# use their combatant_name. combatant_name stays "Player" for HUD / win checks.
	var sprite_key := PlayerProgression.hero_sprite if is_player else data.combatant_name
	var frames := SpriteRegistry.get_combatant_frames(sprite_key)
	if frames != null:
		_sprite.sprite_frames = frames
		_sprite.play("idle")
	_sprite.visible = _sprite.sprite_frames != null
	_body.visible = _sprite.sprite_frames == null
	_sprite_key = sprite_key if is_player else ""
	if is_player:
		_setup_held_overlays(sprite_key)


## Offset (local px) of the idle-frame visible-content centre from the frame
## centre. Menu scenes subtract it (times scale) to centre the character —
## pack frames can carry wide transparent margins that off-centre the figure.
func sprite_center_offset() -> Vector2:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("idle"):
		return Vector2.ZERO
	if _sprite.sprite_frames.get_frame_count("idle") == 0:
		return Vector2.ZERO
	var tex := _sprite.sprite_frames.get_frame_texture("idle", 0)
	if tex == null:
		return Vector2.ZERO
	var img := tex.get_image()
	if img == null:
		return Vector2.ZERO
	var used := img.get_used_rect()
	if used.size.x <= 0:
		return Vector2.ZERO
	var delta := Vector2(used.get_center()) - tex.get_size() / 2.0
	if _sprite.flip_h:
		delta.x = -delta.x
	return delta


# ── Held-equipment overlay ────────────────────────────────────────────────────
# Slots pivot at the item's grip pixel (offset = -grip), so per-frame anchor
# rotation swings the item around the fist. Anchors resolved per
# (animation, hand, frame) from the hero manifest; see anchor_entry().

## Combatant-local position of a hand anchor, honouring the flip_h mirror.
static func held_slot_position(frame_size: Vector2, hand_px: Vector2i, flipped: bool) -> Vector2:
	var hand_local := Vector2(hand_px) - frame_size / 2.0
	if flipped:
		hand_local.x = -hand_local.x
	return hand_local


## Sprite offset that puts the grip pixel on the node origin (rotation pivot),
## accounting for the sprite's horizontal / vertical mirror.
static func held_slot_offset(grip_px: Vector2i, tex_size: Vector2, flip_h: bool,
		flip_v: bool = false) -> Vector2:
	var gx := float(grip_px.x)
	if flip_h:
		gx = tex_size.x - 1.0 - gx
	var gy := float(grip_px.y)
	if flip_v:
		gy = tex_size.y - 1.0 - gy
	return Vector2(-gx, -gy)


## Manifest rotation is authored in RAW sheet orientation; the runtime mirror
## reverses the visual arc, so flipped rendering negates it.
static func held_rotation(deg: float, flipped: bool) -> float:
	return -deg if flipped else deg


const HELD_ORDER_DEFAULT := ["hero", "weapon", "hand"]


## Resolves the draw-order tokens for a hand slot from the item meta "order"
## field (schema doc in SpriteRegistry). String form applies to both hands;
## object form is per-hand. Missing, unknown-token, or hero/weapon-less
## entries fall back to the default hero;weapon;hand.
static func held_order(meta: Dictionary, hand: String) -> Array:
	var raw: Variant = meta.get("order")
	if raw is Dictionary:
		raw = (raw as Dictionary).get(hand)
	if not (raw is String):
		return HELD_ORDER_DEFAULT
	var tokens: Array = []
	for part in (raw as String).split(";"):
		tokens.append(part.strip_edges())
	for t in tokens:
		if t not in HELD_ORDER_DEFAULT:
			push_warning("Combatant: unknown held-order token '%s' in '%s'" % [t, raw])
			return HELD_ORDER_DEFAULT
	if "hero" not in tokens or "weapon" not in tokens:
		push_warning("Combatant: held order needs hero and weapon tokens: '%s'" % raw)
		return HELD_ORDER_DEFAULT
	return tokens


## z_index of a layer token relative to the hero sprite (hero = 0); negative
## draws behind the body.
static func held_layer_z(tokens: Array, token: String) -> int:
	return tokens.find(token) - tokens.find("hero")


## Grip value for a slot showing the back-variant texture: the back art's own
## authored grip wins, else the front item's grip carries over.
static func held_back_grip(front_meta: Dictionary, back_meta: Dictionary) -> Variant:
	return back_meta.get("grip", front_meta.get("grip"))


# ── Per-hero override chain ───────────────────────────────────────────────────
# Hero manifests may override item behaviour in two tiers on top of the item's
# own held/<key>.json (tier 1): "item_defaults" (tier 2 — this hero, every
# item) and "items": {<key>: {...}} (tier 3 — this hero, one item). Each field
# resolves independently; the highest tier that authors a non-null value WINS
# outright (replace, never stack), null/missing falls through to the tier below.
# flip_h/flip_v/pos/rot accept a scalar (both hands) OR a per-hand object
# {"main": ..., "off": ...} — a missing hand key counts as unauthored and falls
# through the chain like any null. "anims" tables are per-hand by nature.


## Unwraps a possibly per-hand override value: {"main"/"off": ...} picks the
## hand's entry (null when the hand is absent); a scalar passes through.
static func held_hand_value(v: Variant, hand: String) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).get(hand)
	return v


## Walks tier 3 → tier 2 for one field; null = no override (caller applies the
## tier-1 base). Explicit JSON null is treated as absent, per the chain rule.
## Every field except "anims" is unwrapped per-hand; an unwrap miss lets the
## LOWER tier serve the hand.
static func held_override_field(hero_meta: Dictionary, key: String, field: String,
		hand: String = "") -> Variant:
	var items: Variant = hero_meta.get("items")
	if items is Dictionary:
		var v: Variant = _entry_field((items as Dictionary).get(key), field, hand)
		if v != null:
			return v
	return _entry_field(hero_meta.get("item_defaults"), field, hand)


## One tier's contribution for a field: null when the entry doesn't author it
## (or authors it for other hands only).
static func _entry_field(entry: Variant, field: String, hand: String) -> Variant:
	if entry is Dictionary and (entry as Dictionary).get(field) != null:
		var v: Variant = (entry as Dictionary)[field]
		if field != "anims":
			v = held_hand_value(v, hand)
		return v
	return null


## Effective art mirror for the SHOWN texture: override chain (keyed by the
## shown art's key, so a <key>_back variant is overridden independently of the
## front) → the art's own held/<key>.json flag → false. Both the overrides and
## the art's own flag may be per-hand objects.
static func held_flip(hero_meta: Dictionary, art_key: String, art_meta: Dictionary,
		field: String, hand: String = "") -> bool:
	var ovr: Variant = held_override_field(hero_meta, art_key, field, hand)
	if ovr != null:
		return bool(ovr)
	var own: Variant = held_hand_value(art_meta.get(field), hand)
	return bool(own) if own != null else false


## Per-hero anchor position delta for an item ("pos" [dx, dy], unflipped px).
## Zero when no tier authors one, or on a malformed value.
static func held_ovr_pos(hero_meta: Dictionary, key: String, hand: String = "") -> Vector2i:
	return json_v2i(held_override_field(hero_meta, key, "pos", hand), Vector2i.ZERO)


## Per-hero anchor rotation delta for an item ("rot", deg in unflipped terms —
## negated with the rest of the entry when the sprite is mirrored).
static func held_ovr_rot(hero_meta: Dictionary, key: String, hand: String = "") -> float:
	var r: Variant = held_override_field(hero_meta, key, "rot", hand)
	if r is float or r is int:
		return float(r)
	return 0.0


## Anchor for (anim, hand, frame) honouring the per-item chain: an "anims"
## table from the override chain wins per lookup; any miss inside it (anim,
## hand, or empty table) falls through to the hero-level tables — an item
## override can therefore never HIDE a hand the hero tables show.
static func anchor_entry_for_item(hero_meta: Dictionary, key: String, anim: String,
		hand: String, frame: int) -> Variant:
	var ovr: Variant = held_override_field(hero_meta, key, "anims")
	if ovr is Dictionary:
		var entry: Variant = anchor_entry({"anims": ovr}, anim, hand, frame)
		if entry != null:
			return entry
	return anchor_entry(hero_meta, anim, hand, frame)


## Per-hand glove fine-tune entry [dx, dy, drot] from the hero manifest
## ("glove_off"). Accepts legacy 2-element [dx, dy] (rot 0). Missing → zeros.
static func _glove_entry(hero_meta: Dictionary, hand: String) -> Array:
	var go: Variant = hero_meta.get("glove_off")
	if go is Dictionary and (go as Dictionary).get(hand) is Array:
		var a := (go as Dictionary)[hand] as Array
		return [
			int(a[0]) if a.size() > 0 else 0,
			int(a[1]) if a.size() > 1 else 0,
			int(a[2]) if a.size() > 2 else 0,
		]
	return [0, 0, 0]


## Per-hero fine offset of the glove from the hand anchor, mirrored with the
## sprite flip. Missing → zero.
static func held_glove_offset(hero_meta: Dictionary, hand: String, flipped: bool) -> Vector2:
	var e := _glove_entry(hero_meta, hand)
	return Vector2(-int(e[0]) if flipped else int(e[0]), int(e[1]))


## Per-hero glove rotation DELTA (deg) added to the weapon's angle; 0 = follow
## the weapon exactly. Negated on flip, like held_rotation.
static func held_glove_rot(hero_meta: Dictionary, hand: String, flipped: bool) -> float:
	var r := float(_glove_entry(hero_meta, hand)[2])
	return -r if flipped else r


## Resolves the anchor for (anim, hand, frame) from a hero held-manifest.
## Returns [x, y] or [x, y, rot_deg] (Array), or null = item hidden this anim.
## Priority: "anims" per-frame tables; legacy top-level main/off (+idle_bob)
## serve idle only. Frame index clamps to the last authored entry.
static func anchor_entry(hero_meta: Dictionary, anim: String, hand: String, frame: int) -> Variant:
	var anims: Dictionary = hero_meta.get("anims", {}) as Dictionary
	if anims.has(anim):
		var per: Dictionary = anims[anim] as Dictionary
		if not per.has(hand):
			return null
		var arr: Array = per[hand] as Array
		if arr.is_empty():
			return null
		return arr[clampi(frame, 0, arr.size() - 1)]
	if anim == "idle" and hero_meta.has(hand):
		var base: Variant = hero_meta[hand]
		if base is Array and (base as Array).size() == 2:
			var bob: Array = hero_meta.get("idle_bob", []) as Array
			var dy := 0 if bob.is_empty() else int(bob[frame % bob.size()])
			return [int((base as Array)[0]), int((base as Array)[1]) + dy]
	return null


## Re-reads PlayerProgression hands and rebinds the held overlays. Safe no-op
## before setup() or on non-player combatants. Used by the Equipment screen to
## live-update its doll when the player equips items.
func refresh_held() -> void:
	if _sprite_key != "":
		_setup_held_overlays(_sprite_key)


## Parses a manifest [x, y] entry; returns `fallback` on any malformed value.
static func json_v2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		var a := value as Array
		return Vector2i(int(a[0]), int(a[1]))
	return fallback


func _setup_held_overlays(sprite_key: String) -> void:
	if _held_main == null:
		_held_main = _make_held_slot()
		_held_off = _make_held_slot()
		_glove_main = _make_held_slot()
		_glove_off = _make_held_slot()
	_hero_meta = SpriteRegistry.get_hero_held_meta(sprite_key)
	var frame_tex: Texture2D = null
	if _sprite.sprite_frames != null:
		frame_tex = _sprite.sprite_frames.get_frame_texture("idle", 0)
	_frame_size = frame_tex.get_size() if frame_tex != null else Vector2.ZERO
	_bind_held(_held_main, _glove_main, "main", PlayerProgression.main_hand)
	_bind_held(_held_off, _glove_off, "off", PlayerProgression.off_hand)
	_update_held_frame()


func _make_held_slot() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.visible = false
	add_child(s)
	return s


func _bind_held(slot: Sprite2D, glove: Sprite2D, hand: String, item: EquipmentData) -> void:
	slot.texture = null
	glove.texture = null
	_held_info[hand] = {}
	if item == null or _frame_size == Vector2.ZERO:
		return
	var key := SpriteRegistry.icon_key(item.item_name)
	var tex := SpriteRegistry.get_held(key)
	if tex == null:
		return
	var meta := SpriteRegistry.get_held_meta(key)
	var order := held_order(meta, hand)
	var grip_value: Variant = meta.get("grip")
	var art_meta := meta   # meta of the texture actually shown (front or back)
	var art_key := key     # key of the shown art — flip overrides resolve per shown art
	# Behind-the-body slots show the item's internal side when the art ships one
	# (asymmetric items, e.g. shields); its own grip wins, else the front's.
	if held_layer_z(order, "weapon") < 0:
		var back := SpriteRegistry.get_held(key + "_back")
		if back != null:
			tex = back
			art_key = key + "_back"
			art_meta = SpriteRegistry.get_held_meta(art_key)
			grip_value = held_back_grip(meta, art_meta)
	var grip_default := Vector2i(tex.get_width() / 2, tex.get_height() / 2)
	var grip_px := json_v2i(grip_value, grip_default)
	# Per-art mirror ("flip_h"/"flip_v"), stacked on top of the hero's facing
	# flip. Resolved through the per-hero override chain, keyed by the shown
	# art's key so a <key>_back variant flips independently of the front.
	# Rotation is unaffected — the item still points where its anchor rot° says;
	# only the art mirrors.
	var item_flip_h := held_flip(_hero_meta, art_key, art_meta, "flip_h", hand)
	var item_flip_v := held_flip(_hero_meta, art_key, art_meta, "flip_v", hand)
	var eff_flip_h := _sprite.flip_h != item_flip_h
	slot.texture = tex
	slot.flip_h = eff_flip_h
	slot.flip_v = item_flip_v
	slot.offset = held_slot_offset(grip_px, tex.get_size(), eff_flip_h, item_flip_v)
	slot.modulate = AttackPresenter.rarity_tint(item.rarity)
	slot.z_index = held_layer_z(order, "weapon")
	_held_info[hand] = {"planted": bool(meta.get("planted", false)), "key": key}
	if "hand" in order:
		_bind_glove(glove, order)


# The shared glove rides the same anchor + rotation as the item so the fist
# stays wrapped around the grip. No rarity tint: it is the hero's hand, not gear.
func _bind_glove(glove: Sprite2D, order: Array) -> void:
	var tex := SpriteRegistry.get_held("_glove")
	if tex == null:
		return
	var meta := SpriteRegistry.get_held_meta("_glove")
	var grip_default := Vector2i(tex.get_width() / 2, tex.get_height() / 2)
	var grip_px := json_v2i(meta.get("grip"), grip_default)
	glove.texture = tex
	glove.flip_h = _sprite.flip_h
	glove.offset = held_slot_offset(grip_px, tex.get_size(), _sprite.flip_h)
	glove.z_index = held_layer_z(order, "hand")


# Anchors the held items to the current animation frame's hand positions.
func _update_held_frame() -> void:
	for trio in [[_held_main, _glove_main, "main"], [_held_off, _glove_off, "off"]]:
		var slot := trio[0] as Sprite2D
		var glove := trio[1] as Sprite2D
		var hand := trio[2] as String
		if slot == null:
			continue
		var info := _held_info.get(hand, {}) as Dictionary
		var item_key := String(info.get("key", ""))
		var entry: Variant = null
		if slot.texture != null and not _is_dead:
			var anim := String(_sprite.animation)
			var planted: bool = info.get("planted", false)
			if not (planted and anim != "idle"):
				entry = anchor_entry_for_item(_hero_meta, item_key, anim, hand, _sprite.frame)
		if entry == null:
			slot.visible = false
			if glove != null:
				glove.visible = false
			continue
		var e := entry as Array
		# Per-hero item deltas ride on top of whichever table resolved the entry
		# (unflipped terms; the mirror below handles facing). Glove follows the
		# slot, so it inherits both automatically.
		var dpos := held_ovr_pos(_hero_meta, item_key, hand)
		slot.visible = true
		slot.position = held_slot_position(
				_frame_size, Vector2i(int(e[0]) + dpos.x, int(e[1]) + dpos.y), _sprite.flip_h)
		slot.rotation_degrees = held_rotation(
				(float(e[2]) if e.size() > 2 else 0.0) + held_ovr_rot(_hero_meta, item_key, hand),
				_sprite.flip_h)
		if glove != null:
			glove.visible = glove.texture != null
			glove.position = slot.position \
					+ held_glove_offset(_hero_meta, hand, _sprite.flip_h)
			glove.rotation_degrees = slot.rotation_degrees \
					+ held_glove_rot(_hero_meta, hand, _sprite.flip_h)


func _on_animation_finished() -> void:
	# Non-looping anims (attack/cast/hurt) hand back to idle; the death anim
	# stays frozen on its last frame.
	if _is_dead:
		return
	if _sprite.animation != "idle":
		_play("idle")


func _play(anim_name: String) -> void:
	if _sprite.sprite_frames == null:
		return
	if not _sprite.sprite_frames.has_animation(anim_name):
		return
	if _sprite.sprite_frames.get_frame_count(anim_name) == 0:
		return
	_sprite.play(anim_name)


func play_idle() -> void:
	if _is_dead:
		return
	_play("idle")


## Plays a per-attack pose animation; falls back to `fallback` when the pose
## (or the requested clip itself) is missing from the loaded sprite frames.
func play_attack(anim_name: String, fallback: String = "attack_melee") -> void:
	if anim_name != "" and _sprite.sprite_frames != null \
			and _sprite.sprite_frames.has_animation(anim_name):
		_play(anim_name)
	else:
		_play(fallback)


func play_attack_melee() -> void:
	play_attack("attack_melee")


func play_cast_spell() -> void:
	play_attack("cast_spell", "cast_spell")


func fade_name_label(alpha: float = 0.4) -> void:
	_name_label.modulate.a = alpha


func play_hurt() -> void:
	_play("hurt")


## White impact flash — decays back to normal over `duration`. Re-triggering
## restarts the decay (last tween wins; harmless at this timescale).
func flash(duration: float = FLASH_S) -> void:
	var mat := _sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	var t := create_tween()
	t.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("flash_amount", v),
		1.0, 0.0, duration)


func play_die() -> void:
	_is_dead = true
	_play("die")
