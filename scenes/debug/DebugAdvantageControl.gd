extends HBoxContainer

var _net_advantage: int = 0  # clamped to [-3, +3]

@onready var _value_label: Label = $ValueLabel


func _ready() -> void:
	$MinusButton.pressed.connect(_on_minus)
	$PlusButton.pressed.connect(_on_plus)
	_refresh()


func get_net_advantage() -> int:
	return _net_advantage


func _on_minus() -> void:
	_net_advantage = maxi(_net_advantage - 1, -3)
	_refresh()


func _on_plus() -> void:
	_net_advantage = mini(_net_advantage + 1, 3)
	_refresh()


func _refresh() -> void:
	_value_label.text = str(_net_advantage)
