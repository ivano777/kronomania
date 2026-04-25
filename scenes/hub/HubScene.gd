# HubScene — player's base between dungeon runs.
# Shows tier, stats, Fervor state, run progress. Provides rest and navigation buttons.
# All UI is built in code; no sub-nodes required in the .tscn.
extends Control

const _PLAYER_DATA := preload("res://resources/data/player_default.tres")

var _tier_label: Label
var _fervor_label: Label
var _stats_label: Label
var _run_label: Label
var _continue_btn: Button
var _start_run_btn: Button


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "◆  KRONOMANIA — HUB  ◆"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	_tier_label = Label.new()
	vbox.add_child(_tier_label)

	_fervor_label = Label.new()
	vbox.add_child(_fervor_label)

	_stats_label = Label.new()
	vbox.add_child(_stats_label)

	vbox.add_child(HSeparator.new())

	_run_label = Label.new()
	vbox.add_child(_run_label)

	vbox.add_child(HSeparator.new())

	var btn_rest := Button.new()
	btn_rest.text = "Long Rest  (reset Fervor + clear Burnout)"
	btn_rest.pressed.connect(_on_long_rest)
	vbox.add_child(btn_rest)

	var btn_rec := Button.new()
	btn_rec.text = "Recovery  (clear Burnout only)"
	btn_rec.pressed.connect(_on_recovery)
	vbox.add_child(btn_rec)

	var btn_const := Button.new()
	btn_const.text = "Constellation"
	btn_const.pressed.connect(_on_constellation)
	vbox.add_child(btn_const)

	vbox.add_child(HSeparator.new())

	_continue_btn = Button.new()
	_continue_btn.text = "Continue Run"
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)

	_start_run_btn = Button.new()
	_start_run_btn.text = "Start New Run"
	_start_run_btn.pressed.connect(_on_start_run)
	vbox.add_child(_start_run_btn)

	_refresh()


func _refresh() -> void:
	var tier := PlayerProgression.get_tier()
	var hp   := _max_wounds()
	var pts  := PlayerProgression.available_points
	_tier_label.text = "Tier: %d  |  HP: %d  |  Points: %d" % [tier, hp, pts]

	var fervor  := PlayerProgression.saved_fervor_size
	var burned  := PlayerProgression.saved_is_burned_out
	var has_mag := PlayerProgression.get_known_spells().size() > 0 \
				or PlayerProgression.get_known_cantrips().size() > 0
	if has_mag:
		var burnout_str := "  [BURNOUT]" if burned else ""
		_fervor_label.text = "Fervor: d%d%s" % [fervor, burnout_str]
		_fervor_label.show()
	else:
		_fervor_label.hide()

	var dom := _effective_stat_size("dominion")
	var neg := _effective_stat_size("negation")
	var ing := _effective_stat_size("ingenuity")
	_stats_label.text = "Dominion: d%d  |  Negation: d%d  |  Ingenuity: d%d" % [dom, neg, ing]

	var run_text: String
	if DungeonManager.run_active:
		run_text = "Run in progress  (%d / %d cleared)" \
			% [DungeonManager.enemies_cleared(), DungeonManager.enemies_total()]
	elif DungeonManager.is_run_complete():
		run_text = "Run complete!  All enemies defeated."
	elif DungeonManager.last_result == "defeat":
		run_text = "Defeated!  Start a new run to try again."
	else:
		run_text = "Ready — start a new run."
	_run_label.text = run_text

	_continue_btn.visible = DungeonManager.has_next_enemy()
	_start_run_btn.visible = not DungeonManager.run_active


func _on_long_rest() -> void:
	PlayerProgression.apply_long_rest()
	_refresh()


func _on_recovery() -> void:
	PlayerProgression.apply_recovery()
	_refresh()


func _on_constellation() -> void:
	get_tree().change_scene_to_file("res://scenes/constellation/ConstellationScene.tscn")


func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")


func _on_start_run() -> void:
	DungeonManager.start_run()
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")


func _effective_stat_size(stat: String) -> int:
	var base: int
	match stat:
		"dominion":  base = _PLAYER_DATA.dominion_size
		"negation":  base = _PLAYER_DATA.negation_size
		"ingenuity": base = _PLAYER_DATA.ingenuity_size
		_: base = 4
	var best := base
	for node in PlayerProgression.node_levels.keys():
		var lvl: int = PlayerProgression.node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == "stat_size_" + stat:
				best = maxi(best, ld.effect_value)
	return best


func _max_wounds() -> int:
	var tier  := PlayerProgression.get_tier()
	var base  := _PLAYER_DATA.max_wounds
	var equip := _PLAYER_DATA.equipped_weapon.max_wounds_bonus if _PLAYER_DATA.equipped_weapon else 0
	var bonus := 0
	for node in PlayerProgression.node_levels.keys():
		var lvl: int = PlayerProgression.node_levels[node]
		var nd: NodeData = node as NodeData
		for i in range(mini(lvl, nd.levels_data.size())):
			if (nd.levels_data[i] as NodeLevelData).effect_type == "training_wounds":
				bonus += (nd.levels_data[i] as NodeLevelData).effect_value
	return base + equip + (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0) + bonus
