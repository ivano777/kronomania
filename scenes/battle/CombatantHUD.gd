# CombatantHUD — displays one combatant's name, wound slots, and current Guard.
class_name CombatantHUD
extends VBoxContainer

const COLOR_WOUND_EMPTY  := Color(0.25, 0.25, 0.25, 1.0)
const COLOR_WOUND_FILLED := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_WOUND_HIDDEN := Color(0.0, 0.0, 0.0, 0.0)

@onready var _name_label:     Label         = $NameLabel
@onready var _wound_slots:    HBoxContainer = $WoundsRow/WoundSlots
@onready var _stance_value:   Label         = $StanceRow/StanceValue
@onready var _resolve_value:  Label         = $ResolveRow/ResolveValue
@onready var _stamina_value:  Label         = $StaminaRow/StaminaValue

var _slot_nodes: Array[ColorRect] = []
var _max_wounds: int = 3


func _ready() -> void:
	for child in _wound_slots.get_children():
		if child is ColorRect:
			_slot_nodes.append(child as ColorRect)


# Call once after instantiation to bind combatant data.
func setup(data: CombatantData) -> void:
	_name_label.text = data.combatant_name
	_max_wounds = data.max_wounds
	_refresh_wounds(0)
	set_guard("stance",  0)
	set_guard("resolve", 0)
	set_guard("stamina", 0)


# Update wound slot display. current = wounds taken so far.
func set_wounds(current: int, max_wounds: int) -> void:
	_max_wounds = max_wounds
	_refresh_wounds(current)


# Update the guard value label for a specific pool.
func set_guard(pool: String, value: int) -> void:
	match pool:
		"stance":  _stance_value.text  = str(value)
		"resolve": _resolve_value.text = str(value)
		"stamina": _stamina_value.text = str(value)


func _refresh_wounds(current: int) -> void:
	for i in _slot_nodes.size():
		var slot := _slot_nodes[i]
		if i < _max_wounds:
			slot.visible = true
			slot.color = COLOR_WOUND_FILLED if i < current else COLOR_WOUND_EMPTY
		else:
			# Slots beyond max_wounds are hidden (enemy may have fewer than 3).
			slot.visible = false
