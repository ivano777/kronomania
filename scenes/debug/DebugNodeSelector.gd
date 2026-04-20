extends VBoxContainer

@onready var _toggle: Button = $ToggleButton
@onready var _panel: VBoxContainer = $Panel
@onready var _status: Label = $Panel/StatusLabel


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	_add_button("No Training (keep 1)", 0)
	_add_button("Training I (keep 2)", 1)
	_add_button("Training II (keep 3)", 2)
	_refresh_status()


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "Training ▾" if _panel.visible else "Training ▸"


func _add_button(label: String, grade: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(_apply_grade.bind(grade))
	$Panel/Buttons.add_child(btn)


func _apply_grade(grade: int) -> void:
	var nodes: Array[NodeData] = []
	if grade >= 1:
		nodes.append(load("res://resources/data/nodes/training_keep_1.tres") as NodeData)
	if grade >= 2:
		nodes.append(load("res://resources/data/nodes/training_keep_2.tres") as NodeData)
	CombatManager.debug_set_player_nodes(nodes)
	_refresh_status()


func _refresh_status() -> void:
	var grade := CombatManager.debug_get_player_keep_grade()
	_status.text = "Keep grade: %d (keep %d dice)" % [grade, grade + 1]
