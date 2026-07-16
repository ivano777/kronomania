class_name Combatant
extends Node2D

const COLOR_PLAYER := Color(0.20, 0.35, 0.80, 1.0)
const COLOR_ENEMY  := Color(0.80, 0.20, 0.20, 1.0)

const _FLASH_SHADER := preload("res://assets/shaders/impact_flash.gdshader")
const FLASH_S := 0.18

var _is_dead := false

@onready var _body:       ColorRect        = $Body
@onready var _sprite:     AnimatedSprite2D = $Sprite
@onready var _name_label: Label            = $NameLabel


func _ready() -> void:
	_sprite.animation_finished.connect(_on_animation_finished)
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
