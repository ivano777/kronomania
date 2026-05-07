class_name Combatant
extends Node2D

const COLOR_PLAYER := Color(0.20, 0.35, 0.80, 1.0)
const COLOR_ENEMY  := Color(0.80, 0.20, 0.20, 1.0)

var _is_dead := false
var _idle_timer: SceneTreeTimer = null

@onready var _body:       ColorRect        = $Body
@onready var _sprite:     AnimatedSprite2D = $Sprite
@onready var _name_label: Label            = $NameLabel


func setup(data: CombatantData, is_player: bool) -> void:
	_name_label.text = data.combatant_name
	_body.color = COLOR_PLAYER if is_player else COLOR_ENEMY
	_sprite.flip_h = is_player
	var frames := SpriteRegistry.get_combatant_frames(data.combatant_name)
	if frames != null:
		_sprite.sprite_frames = frames
		_sprite.play("idle")
	_sprite.visible = _sprite.sprite_frames != null
	_body.visible = _sprite.sprite_frames == null


func _cancel_idle_timer() -> void:
	if _idle_timer != null and _idle_timer.timeout.is_connected(play_idle):
		_idle_timer.timeout.disconnect(play_idle)
	_idle_timer = null


func _schedule_idle(delay: float) -> void:
	_cancel_idle_timer()
	_idle_timer = get_tree().create_timer(delay)
	_idle_timer.timeout.connect(play_idle, CONNECT_ONE_SHOT)


func _play(anim_name: String) -> void:
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)


func play_idle() -> void:
	if _is_dead:
		return
	_idle_timer = null
	_play("idle")


func play_attack_melee() -> void:
	_cancel_idle_timer()
	_play("attack_melee")
	_schedule_idle(0.5)


func play_cast_spell() -> void:
	_cancel_idle_timer()
	_play("cast_spell")
	_schedule_idle(0.5)


func play_hurt() -> void:
	_cancel_idle_timer()
	_play("hurt")
	_schedule_idle(0.6)


func play_die() -> void:
	_cancel_idle_timer()
	_is_dead = true
	_play("die")
