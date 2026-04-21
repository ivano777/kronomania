extends Control

const CATEGORIES := ["Core", "Training", "Ability", "Flavor"]

@onready var _points_label: Label = $Main/Header/PointsLabel
@onready var _tier_label: Label = $Main/Header/TierLabel
@onready var _progress_label: Label = $Main/ProgressLabel
@onready var _back_btn: Button  = $Main/Footer/BackButton
@onready var _reset_btn: Button = $Main/Footer/ResetButton

var _node_buttons: Dictionary = {}  # NodeData -> Button


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_reset_btn.pressed.connect(_on_reset_pressed)
	_populate_columns()
	_refresh()


func _populate_columns() -> void:
	for node in PlayerProgression.ALL_NODES:
		var col := _get_column(node.category)
		if not col:
			continue
		col.add_child(_make_card(node))


func _make_card(node: NodeData) -> PanelContainer:
	var card := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = node.node_name
	name_lbl.add_theme_font_size_override("font_size", 13)

	var desc_lbl := Label.new()
	desc_lbl.text = node.description if node.description != "" else "(No description)"
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(0, 36)
	desc_lbl.add_theme_font_size_override("font_size", 11)

	var btn := Button.new()
	btn.pressed.connect(_on_unlock.bind(node))
	_node_buttons[node] = btn

	vbox.add_child(name_lbl)
	vbox.add_child(desc_lbl)
	vbox.add_child(btn)
	card.add_child(vbox)
	return card


func _get_column(category: String) -> VBoxContainer:
	match category:
		"Core":     return $Main/ColumnsScroll/Columns/CoreColumn
		"Training": return $Main/ColumnsScroll/Columns/TrainingColumn
		"Ability":  return $Main/ColumnsScroll/Columns/AbilityColumn
		"Flavor":   return $Main/ColumnsScroll/Columns/FlavorColumn
	return null


func _refresh() -> void:
	var pts := PlayerProgression.available_points
	var tier := PlayerProgression.get_tier()

	_points_label.text = "Points: %d" % pts
	_tier_label.text = "Tier %d" % tier

	if tier < 4:
		var need_per_cat := tier
		var worst := 999
		for cat in CATEGORIES:
			worst = mini(worst, PlayerProgression.get_category_count(cat))
		var gap := maxi(0, need_per_cat - worst)
		if gap > 0:
			_progress_label.text = "To reach Tier %d: unlock %d more node(s) in each category." % [tier + 1, gap]
		else:
			_progress_label.text = "Tier %d reached!" % tier
	else:
		_progress_label.text = "Maximum Tier (4) reached."

	for node in _node_buttons:
		var nd := node as NodeData
		var btn: Button = _node_buttons[node]
		if PlayerProgression.is_unlocked(nd):
			btn.text = "Unlocked"
			btn.disabled = true
		elif PlayerProgression.can_unlock(nd):
			btn.text = "Unlock (%d pt)" % nd.unlock_cost
			btn.disabled = false
		else:
			btn.text = "Need %d pt" % nd.unlock_cost
			btn.disabled = true


func _on_unlock(node: NodeData) -> void:
	PlayerProgression.unlock(node)
	_refresh()


func _on_reset_pressed() -> void:
	PlayerProgression.reset()
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
