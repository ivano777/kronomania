extends GutTest
# Constellation icon-token overhaul — structural checks for the reskinned tree.
# Covers branch resolution (category strings are unreliable), initials fallback,
# and that every node gets a token whose pip strip tracks its level.

const SCENE := "res://scenes/constellation/ConstellationScene.tscn"


func before_each() -> void:
	SaveManager.active_slot = 0  # keep scene _ready from touching save files
	PlayerProgression.reset()


func _make_scene() -> Node:
	var inst: Control = (load(SCENE) as PackedScene).instantiate() as Control
	add_child_autofree(inst)
	await wait_frames(2)
	return inst


func test_every_node_gets_a_token() -> void:
	var scene := await _make_scene()
	assert_gt(scene._node_cards.size(), 0, "cards were built")
	# Each token owns a pip strip sized to its node's max_levels.
	for node in scene._node_cards:
		var nd := node as NodeData
		assert_true(scene._node_pips.has(node), "%s has a pip strip" % nd.node_id)
		assert_eq((scene._node_pips[node] as Array).size(), nd.max_levels,
			"%s pip count == max_levels" % nd.node_id)


func test_branch_of_resolves_by_id() -> void:
	var scene := await _make_scene()
	var m: Dictionary = scene._node_by_id_map
	assert_eq(scene._branch_of(m["dom_core"]), "core")
	assert_eq(scene._branch_of(m["dom_brutal"]), "dominion")
	assert_eq(scene._branch_of(m["neg_stance"]), "negation")
	assert_eq(scene._branch_of(m["ing_resolve"]), "ingenuity")
	# hex_mastery carries the lowercase "ingenuity" category — must still resolve.
	assert_eq(scene._branch_of(m["hex_mastery"]), "ingenuity")
	assert_eq(scene._branch_of(m["warrior_oath"]), "flavor")


func test_initials_fallback() -> void:
	var scene := await _make_scene()
	assert_eq(scene._node_initials("Hex Mastery"), "HM")
	assert_eq(scene._node_initials("Mind Detonation"), "MD")
	assert_eq(scene._node_initials("Lucidity"), "LU")


func test_pips_track_level_after_buy() -> void:
	var scene := await _make_scene()
	var dom_core: NodeData = scene._node_by_id_map["dom_core"]
	var pips: Array = scene._node_pips[dom_core]
	assert_eq((pips[0] as ColorRect).color, scene.PIP_EMPTY,
		"unbought node shows an empty first pip")
	assert_true(PlayerProgression.can_upgrade(dom_core), "dom_core L1 is affordable at reset")
	PlayerProgression.upgrade(dom_core)
	scene._refresh()
	assert_eq((pips[0] as ColorRect).color, scene._branch_color(dom_core),
		"first pip lights in the branch colour after buying L1")


func _left_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func test_clicking_token_opens_panel() -> void:
	var scene := await _make_scene()
	var hex: NodeData = scene._node_by_id_map["hex_mastery"]
	assert_false(scene._detail_panel.is_open(), "panel starts closed")
	scene._on_card_clicked(_left_click(), hex)
	assert_true(scene._detail_panel.is_open(), "left-click opens the panel")
	assert_eq(scene._detail_panel._title.text, "Hex Mastery")
	# The full level ladder is rendered (hex_mastery has 2 levels + base description).
	assert_gt(scene._detail_panel._body.get_child_count(), 2, "panel body is populated")


func test_panel_buy_upgrades_and_signals() -> void:
	var scene := await _make_scene()
	var dom_core: NodeData = scene._node_by_id_map["dom_core"]
	scene._detail_panel.open(dom_core, "core", scene._branch_color(dom_core))
	watch_signals(scene._detail_panel)
	var before := PlayerProgression.get_level(dom_core)
	scene._detail_panel._on_buy()
	assert_eq(PlayerProgression.get_level(dom_core), before + 1, "buy raised the level")
	assert_signal_emitted(scene._detail_panel, "bought")


func test_panel_closes() -> void:
	var scene := await _make_scene()
	var node: NodeData = scene._node_by_id_map["dom_stamina"]
	scene._detail_panel.open(node, "dominion", scene._branch_color(node))
	assert_true(scene._detail_panel.is_open())
	scene._detail_panel.close()
	assert_false(scene._detail_panel.is_open(), "close() hides the panel")
