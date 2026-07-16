extends GutTest

# Regression: the node detail panel must render while the Traits tab is
# active — flavor/background cards live there, and a panel parented under the
# Skills tab is hidden by the TabContainer, making flavors unbuyable.


func test_detail_panel_visible_from_traits_tab() -> void:
	PlayerProgression.reset()
	var scene := (load("res://scenes/constellation/ConstellationScene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame

	var tabs: TabContainer = scene.get_node("Main/TabContainer")
	tabs.current_tab = 1  # "Background / Traits"

	var flavor: NodeData = null
	for n in PlayerProgression.ALL_NODES:
		if (n as NodeData).category == "Flavor":
			flavor = n
			break
	assert_not_null(flavor, "at least one Flavor node exists in ALL_NODES")
	if flavor == null:
		return

	var panel: NodeDetailPanel = scene._detail_panel
	panel.open(flavor, "flavor", Color.WHITE)
	await get_tree().process_frame
	assert_true(panel.is_visible_in_tree(),
		"detail panel (and its Buy button) must overlay the Traits tab")


func test_initial_view_frames_triangle() -> void:
	PlayerProgression.reset()
	var scene := (load("res://scenes/constellation/ConstellationScene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	# _ready awaits one frame before centering; give layout + centering time.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var skills: Control = scene.get_node("Main/TabContainer/Skills")
	var panel_rect: Rect2 = skills.get_global_rect()
	for nid in ["dom_core", "ing_core", "neg_core", "dom_stamina", "neg_stance", "ing_resolve"]:
		var card: Control = _card_for(scene, nid)
		assert_not_null(card, "card exists for %s" % nid)
		if card == null:
			continue
		assert_true(panel_rect.encloses(card.get_global_rect()),
			"%s card fully inside skills viewport after initial centering (card %s, panel %s)" % [
				nid, card.get_global_rect(), panel_rect
			])


func test_click_second_node_switches_panel_in_one_click() -> void:
	PlayerProgression.reset()
	# Headless quirks: the window defaults to 64x64 (GUI picks outside it are
	# dropped) and GUT's runner GUI otherwise sits above the test scene in pick
	# order. Size the window to the canvas and parent the scene to the root as
	# the last child so mouse picking reaches the node cards.
	var win := get_tree().root
	var old_win_size: Vector2i = win.size
	win.size = Vector2i(640, 360)
	var scene := (load("res://scenes/constellation/ConstellationScene.tscn") as PackedScene).instantiate()
	win.add_child(scene)
	autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var node_a: NodeData = scene._node_by_id_map.get("dom_stamina")
	var node_b: NodeData = scene._node_by_id_map.get("ing_resolve")
	assert_not_null(node_a, "dom_stamina node exists")
	assert_not_null(node_b, "ing_resolve node exists")
	if node_a == null or node_b == null:
		return

	var panel: NodeDetailPanel = scene._detail_panel
	panel.open(node_a, "dominion", Color.WHITE)
	assert_true(panel.is_open(), "panel open for first node")

	# Real click on the second node's card, routed through the whole input
	# pipeline so the scene's _input (empty-space close) runs before the card's
	# gui_input — regression: the close used to consume the event, forcing a
	# second click. ing_resolve is leftmost, safely clear of the right-edge panel.
	var card_b: Control = _card_for(scene, "ing_resolve")
	var pos: Vector2 = card_b.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await get_tree().process_frame

	# GUT's runner GUI sits on a CanvasLayer, which always wins mouse picking
	# over the plain scene tree — hide it while the synthetic click flies.
	var gut_gui: Control = null
	var hovered := scene.get_viewport().gui_get_hovered_control()
	if hovered != null and not scene.is_ancestor_of(hovered):
		gut_gui = hovered
		while gut_gui.get_parent() is Control:
			gut_gui = gut_gui.get_parent()
		gut_gui.visible = false
		Input.parse_input_event(motion.duplicate())
		await get_tree().process_frame

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)
	await get_tree().process_frame
	if gut_gui != null:
		gut_gui.visible = true
	win.size = old_win_size

	assert_true(panel.is_open(), "panel still open after clicking second node")
	assert_eq(panel._node, node_b, "panel switched to the clicked node in one click")


func _card_for(scene: Node, node_id: String) -> Control:
	var nd: NodeData = scene._node_by_id_map.get(node_id)
	if nd == null:
		return null
	return scene._node_cards.get(nd)


func test_flavor_node_purchasable_with_points() -> void:
	PlayerProgression.reset()
	PlayerProgression.grant_points(1)
	var flavor: NodeData = null
	for n in PlayerProgression.ALL_NODES:
		if (n as NodeData).category == "Flavor":
			flavor = n
			break
	if flavor == null:
		return
	assert_true(PlayerProgression.can_upgrade(flavor), "flavor buyable with 1 point at Tier 1")
	PlayerProgression.upgrade(flavor)
	assert_eq(PlayerProgression.get_level(flavor), 1, "flavor purchased")
	assert_eq(PlayerProgression.tier_flavor_spent, 1, "flavor budget consumed")
