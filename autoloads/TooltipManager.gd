extends Node

const _TOOLTIP_SCENE := preload("res://scenes/ui/CustomTooltip.tscn")

var _canvas: CanvasLayer
var _tooltip  # CustomTooltip instance
var _active_control: Control = null


func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 50
	add_child(_canvas)

	_tooltip = _TOOLTIP_SCENE.instantiate()
	_tooltip.hide()
	_canvas.add_child(_tooltip)


func _input(event: InputEvent) -> void:
	if not _tooltip.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			hide()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			hide()


# ── Public API ─────────────────────────────────────────────────────────────────

func show_for(resource: Resource, screen_pos: Vector2, source: Control = null) -> void:
	_active_control = source
	_tooltip.populate(resource)
	_tooltip.size = Vector2(150, 320)
	_tooltip.modulate.a = 0.0
	_tooltip.show()
	await get_tree().process_frame
	if _active_control != source:
		return
	_tooltip.modulate.a = 1.0
	_tooltip.reset_size()
	_position_tooltip(screen_pos)


func show_delta(node: NodeData, screen_pos: Vector2, source: Control = null) -> void:
	_active_control = source
	_tooltip.populate_delta(node)
	_tooltip.size = Vector2(150, 320)
	_tooltip.modulate.a = 0.0
	_tooltip.show()
	await get_tree().process_frame
	if _active_control != source:
		return
	_tooltip.modulate.a = 1.0
	_tooltip.reset_size()
	_position_tooltip(screen_pos)


func hide() -> void:
	_active_control = null
	_tooltip.hide()


# Wire right-click on a Control to show a full tooltip for a resource.
func attach(control: Control, resource: Resource) -> void:
	control.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if not (mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT):
			return
		get_viewport().set_input_as_handled()
		if _active_control == control and _tooltip.visible:
			hide()
		else:
			show_for(resource, control.get_screen_position() + mb.position, control)
	)


# Wire hover on a Control to show a full tooltip for a resource; hides on mouse exit.
# Also hides if the control leaves the tree while its tooltip is up (rebuilt icon rows).
func attach_hover(control: Control, resource: Resource) -> void:
	control.mouse_entered.connect(func() -> void:
		show_for(resource, control.get_screen_position() + Vector2(0.0, control.size.y), control)
	)
	control.mouse_exited.connect(func() -> void:
		if _active_control == control:
			hide()
	)
	control.tree_exiting.connect(func() -> void:
		if _active_control == control:
			hide()
	)


# Wire right-click on a Control to show a delta (upgrade preview) tooltip for a NodeData.
func attach_delta(control: Control, node: NodeData) -> void:
	control.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if not (mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT):
			return
		get_viewport().set_input_as_handled()
		if _active_control == control and _tooltip.visible:
			hide()
		else:
			show_delta(node, control.get_screen_position() + mb.position, control)
	)


# ── Positioning ────────────────────────────────────────────────────────────────

func _position_tooltip(screen_pos: Vector2) -> void:
	var offset := Vector2(8, 8)
	var viewport_size := get_viewport().get_visible_rect().size
	var tip_size: Vector2 = _tooltip.get_minimum_size()
	if tip_size == Vector2.ZERO:
		tip_size = Vector2(140, 70)
	var pos := screen_pos + offset
	if pos.x + tip_size.x > viewport_size.x:
		pos.x = screen_pos.x - tip_size.x - offset.x
	if pos.y + tip_size.y > viewport_size.y:
		pos.y = screen_pos.y - tip_size.y - offset.y
	pos.x = clampf(pos.x, 0.0, viewport_size.x - tip_size.x)
	pos.y = clampf(pos.y, 0.0, viewport_size.y - tip_size.y)
	_tooltip.position = pos
