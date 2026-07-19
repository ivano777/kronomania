extends GutTest
# UI bounds regression — scene UIs must fit the 640x360 design viewport.
# Guards against content taller/wider than the window (Campfire overflow bug).
# ScrollContainers and clip_contents controls are checked as a whole but not
# descended into — overflow inside them is scrolled/cropped by design.

const VIEW := Vector2(640, 360)

const DEBUG_WIDGET_SCENES := [
	"res://scenes/debug/DebugAttackFX.tscn",
	"res://scenes/debug/DebugCombatControl.tscn",
	"res://scenes/debug/DebugDevMenu.tscn",
	"res://scenes/debug/DevHubScene.tscn",
	"res://scenes/debug/DebugEquipmentDisplay.tscn",
	"res://scenes/debug/DebugFervorDisplay.tscn",
	"res://scenes/debug/DebugProgressionControl.tscn",
	"res://scenes/debug/DebugWeaponSelector.tscn",
]


func _assert_scene_fits(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	var inst: Control = packed.instantiate() as Control
	add_child_autofree(inst)
	await wait_frames(3)
	var bad: Array[String] = []
	_walk(inst, bad)
	assert_eq(bad.size(), 0, "%s controls outside 640x360:\n%s" % [scene_path, "\n".join(bad)])


func _walk(node: Node, bad: Array[String]) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var r: Rect2 = (node as Control).get_global_rect()
		# 1px tolerance for style borders.
		if r.position.x < -1.0 or r.position.y < -1.0 \
				or r.end.x > VIEW.x + 1.0 or r.end.y > VIEW.y + 1.0:
			bad.append("%s  rect=%s" % [node.get_path(), r])
	if node is ScrollContainer:
		return
	if node is Control and (node as Control).clip_contents:
		return
	for child in node.get_children():
		_walk(child, bad)


func before_each() -> void:
	SaveManager.active_slot = 0  # keep scene _ready from writing save files


func test_campfire_fits() -> void:
	await _assert_scene_fits("res://scenes/campfire/CampfireScene.tscn")


func test_main_menu_fits() -> void:
	await _assert_scene_fits("res://scenes/main_menu/MainMenuScene.tscn")


func test_equipment_fits() -> void:
	await _assert_scene_fits("res://scenes/equipment/EquipmentScene.tscn")


func test_constellation_fits() -> void:
	PlayerProgression.reset()
	await _assert_scene_fits("res://scenes/constellation/ConstellationScene.tscn")


func test_debug_widgets_fit() -> void:
	# Debug widgets are corner overlays with their own anchors; mount each in
	# a full-rect host like the scenes do, force it visible (DebugManager gate
	# hides them by default) and expand its Panel — worst-case footprint.
	for path in DEBUG_WIDGET_SCENES:
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child_autofree(host)
		var widget: Control = (load(path) as PackedScene).instantiate() as Control
		host.add_child(widget)
		widget.visible = true
		if widget.has_node("Panel"):
			widget.get_node("Panel").visible = true
		await wait_frames(2)
		var bad: Array[String] = []
		_walk(widget, bad)
		assert_eq(bad.size(), 0, "%s controls outside 640x360:\n%s" % [path, "\n".join(bad)])
		host.visible = false  # keep finished widgets out of later checks
