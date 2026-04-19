# Combatant — placeholder visual for a combatant (colored rect + name label).
# No game logic here; all state is in CombatManager.
class_name Combatant
extends Control

const COLOR_PLAYER := Color(0.20, 0.35, 0.80, 1.0)
const COLOR_ENEMY  := Color(0.80, 0.20, 0.20, 1.0)

@onready var _body:       ColorRect = $Body
@onready var _name_label: Label     = $NameLabel


# Call once from BattleScene after instantiation.
func setup(data: CombatantData, is_player: bool) -> void:
	_name_label.text = data.combatant_name
	_body.color = COLOR_PLAYER if is_player else COLOR_ENEMY
