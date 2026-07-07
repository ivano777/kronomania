extends GutTest
# UI bounds regression — scene UIs must fit the 640x360 design viewport.
# Guards against content taller/wider than the window (Campfire overflow bug).
# ScrollContainers are checked as a whole but not descended into — overflow
# inside them is scrollable by design.

const VIEW := Vector2(640, 360)


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
	for child in node.get_children():
		_walk(child, bad)


func before_each() -> void:
	SaveManager.active_slot = 0  # keep scene _ready from writing save files


func test_campfire_fits() -> void:
	await _assert_scene_fits("res://scenes/campfire/CampfireScene.tscn")


func test_main_menu_fits() -> void:
	await _assert_scene_fits("res://scenes/main_menu/MainMenuScene.tscn")
