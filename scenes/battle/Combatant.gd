class_name Combatant
extends Node2D

const COLOR_PLAYER := Color(0.20, 0.35, 0.80, 1.0)
const COLOR_ENEMY  := Color(0.80, 0.20, 0.20, 1.0)

@onready var _body:       ColorRect        = $Body
@onready var _sprite:     AnimatedSprite2D = $Sprite
@onready var _name_label: Label            = $NameLabel


func setup(data: CombatantData, is_player: bool) -> void:
	_name_label.text = data.combatant_name
	_body.color = COLOR_PLAYER if is_player else COLOR_ENEMY
	_sprite.flip_h = is_player
	_body.visible = _sprite.sprite_frames == null


func _play(anim_name: String) -> void:
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)


func play_idle() -> void:         _play("idle")
func play_attack_melee() -> void: _play("attack_melee")
func play_cast_spell() -> void:   _play("cast_spell")
func play_hurt() -> void:         _play("hurt")
func play_die() -> void:          _play("die")
