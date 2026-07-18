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


## Sprite offset that puts the grip pixel on the node origin (rotation pivot).
static func held_slot_offset(grip_px: Vector2i, tex_size: Vector2, flipped: bool) -> Vector2:
	var gx := float(grip_px.x)
	if flipped:
		gx = tex_size.x - 1.0 - gx
	return Vector2(-gx, -float(grip_px.y))


## Manifest rotation is authored in RAW sheet orientation; the runtime mirror
## reverses the visual arc, so flipped rendering negates it.
static func held_rotation(deg: float, flipped: bool) -> float:
	return -deg if flipped else deg


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
	_hero_meta = SpriteRegistry.get_hero_held_meta(sprite_key)
	var frame_tex: Texture2D = null
	if _sprite.sprite_frames != null:
		frame_tex = _sprite.sprite_frames.get_frame_texture("idle", 0)
	_frame_size = frame_tex.get_size() if frame_tex != null else Vector2.ZERO
	_bind_held(_held_main, "main", PlayerProgression.main_hand)
	_bind_held(_held_off, "off", PlayerProgression.off_hand)
	_update_held_frame()


func _make_held_slot() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.visible = false
	add_child(s)
	return s


func _bind_held(slot: Sprite2D, hand: String, item: EquipmentData) -> void:
	slot.texture = null
	_held_info[hand] = {}
	if item == null or _frame_size == Vector2.ZERO:
		return
	var key := SpriteRegistry.icon_key(item.item_name)
	var tex := SpriteRegistry.get_held(key)
	if tex == null:
		return
	var meta := SpriteRegistry.get_held_meta(key)
	var grip_default := Vector2i(tex.get_width() / 2, tex.get_height() / 2)
	var grip_px := json_v2i(meta.get("grip"), grip_default)
	slot.texture = tex
	slot.flip_h = _sprite.flip_h
	slot.offset = held_slot_offset(grip_px, tex.get_size(), _sprite.flip_h)
	slot.modulate = AttackPresenter.rarity_tint(item.rarity)
	_held_info[hand] = {"planted": bool(meta.get("planted", false))}


# Anchors the held items to the current animation frame's hand positions.
func _update_held_frame() -> void:
	for pair in [[_held_main, "main"], [_held_off, "off"]]:
		var slot := pair[0] as Sprite2D
		var hand := pair[1] as String
		if slot == null:
			continue
		if slot.texture == null or _is_dead:
			slot.visible = false
			continue
		var anim := String(_sprite.animation)
		var planted: bool = (_held_info.get(hand, {}) as Dictionary).get("planted", false)
		if planted and anim != "idle":
			slot.visible = false
			continue
		var entry: Variant = anchor_entry(_hero_meta, anim, hand, _sprite.frame)
		if entry == null:
			slot.visible = false
			continue
		var e := entry as Array
		slot.visible = true
		slot.position = held_slot_position(
				_frame_size, Vector2i(int(e[0]), int(e[1])), _sprite.flip_h)
		slot.rotation_degrees = held_rotation(
				float(e[2]) if e.size() > 2 else 0.0, _sprite.flip_h)


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
