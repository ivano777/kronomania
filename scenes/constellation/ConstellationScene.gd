extends Control

const _PLAYER_DATA: CombatantData = preload("res://resources/data/player_default.tres")
const _DBG_PROGRESSION := "res://scenes/debug/DebugProgressionControl.tscn"

@onready var _points_label: Label = $Main/Header/PointsLabel
@onready var _tier_hp_label: Label = $Main/Header/TierHPLabel
@onready var _budget_label: Label = $Main/BudgetLabel
@onready var _back_btn: Button = $Main/Footer/BackButton
@onready var _tab_container: TabContainer = $Main/TabContainer

var _node_buttons: Dictionary = {}      # NodeData -> Button
var _node_cards: Dictionary = {}        # NodeData -> PanelContainer
var _node_level_labels: Dictionary = {} # NodeData -> Label
var _node_pip_labels: Dictionary = {}   # NodeData -> Label


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_tab_container.set_tab_title(1, "Background / Traits")
	_populate_columns()
	_refresh()
	if ResourceLoader.exists(_DBG_PROGRESSION):
		add_child((load(_DBG_PROGRESSION) as PackedScene).instantiate())


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

	var header_row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = node.display_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var level_lbl := Label.new()
	level_lbl.text = "L0/1"
	level_lbl.add_theme_font_size_override("font_size", 11)

	header_row.add_child(name_lbl)
	header_row.add_child(level_lbl)

	var pip_lbl := Label.new()
	pip_lbl.text = "○"
	pip_lbl.add_theme_font_size_override("font_size", 13)

	var desc_lbl := Label.new()
	desc_lbl.text = node.base_description if node.base_description != "" else "(No description)"
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(0, 36)
	desc_lbl.add_theme_font_size_override("font_size", 11)

	var btn := Button.new()
	btn.pressed.connect(_on_unlock.bind(node))

	_node_buttons[node] = btn
	_node_cards[node] = card
	_node_level_labels[node] = level_lbl
	_node_pip_labels[node] = pip_lbl

	vbox.add_child(header_row)
	vbox.add_child(pip_lbl)
	vbox.add_child(desc_lbl)
	vbox.add_child(btn)
	card.add_child(vbox)
	return card


func _get_column(category: String) -> VBoxContainer:
	match category:
		"Core":     return $Main/TabContainer/Skills/Columns/CoreColumn
		"Training": return $Main/TabContainer/Skills/Columns/TrainingColumn
		"Ability":  return $Main/TabContainer/Skills/Columns/AbilityColumn
		"Flavor":   return $Main/TabContainer/Traits/TraitsBox
	return null


func _refresh() -> void:
	var pts := PlayerProgression.available_points
	var tier := PlayerProgression.get_tier()
	var combat_spent := PlayerProgression.tier_combat_spent
	var flavor_spent := PlayerProgression.tier_flavor_spent

	_points_label.text = "Points: %d" % pts
	_tier_hp_label.text = "Tier %d · HP %d" % [tier, _max_wounds(tier)]

	if tier >= 4:
		_budget_label.text = "Max Tier — Combat: %d/5 · Flavor: %d/2" % [combat_spent, flavor_spent]
	else:
		_budget_label.text = "Combat: %d/5 · Flavor: %d/2  (fill both to reach Tier %d)" % [
			combat_spent, flavor_spent, tier + 1
		]

	for node in _node_buttons:
		var nd := node as NodeData
		var btn: Button = _node_buttons[node]
		var card: PanelContainer = _node_cards[node]
		var level_lbl: Label = _node_level_labels[node]
		var pip_lbl: Label = _node_pip_labels[node]
		var lvl := PlayerProgression.get_level(nd)
		var max_lvl := nd.max_levels
		var at_max := lvl >= max_lvl
		var tier_locked := false
		if not at_max and nd.levels_data.size() > lvl:
			tier_locked = tier < (nd.levels_data[lvl] as NodeLevelData).required_tier

		level_lbl.text = "L%d/%d" % [lvl, max_lvl]
		pip_lbl.text = "●".repeat(lvl) + "○".repeat(max_lvl - lvl)

		if at_max:
			btn.text = "Max Level"
			btn.disabled = true
			card.modulate = Color.WHITE
		elif tier_locked:
			var req_tier: int = (nd.levels_data[lvl] as NodeLevelData).required_tier
			btn.text = "Requires Tier %d" % req_tier
			btn.disabled = true
			card.modulate = Color(1, 1, 1, 0.4)
		elif PlayerProgression.can_upgrade(nd):
			var ld: NodeLevelData = nd.levels_data[lvl]
			var cost := ld.cost
			btn.text = "Upgrade (%d slot%s)" % [cost, "s" if cost > 1 else ""]
			btn.disabled = false
			card.modulate = Color.WHITE
		else:
			btn.text = "Locked"
			btn.disabled = true
			card.modulate = Color.WHITE


func _max_wounds(tier: int) -> int:
	var base := _PLAYER_DATA.max_wounds
	var equip := _PLAYER_DATA.equipped_weapon.max_wounds_bonus if _PLAYER_DATA.equipped_weapon else 0
	return base + equip + (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)


func _on_unlock(node: NodeData) -> void:
	PlayerProgression.upgrade(node)
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/HubScene.tscn")
