extends Node

signal debug_mode_changed(enabled: bool)

var enabled: bool = false

var _indicator: Label


func _ready() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	_indicator = Label.new()
	_indicator.text = "[ DEBUG ]"
	_indicator.anchor_left   = 1.0
	_indicator.anchor_right  = 1.0
	_indicator.anchor_top    = 1.0
	_indicator.anchor_bottom = 1.0
	_indicator.offset_left   = -100.0
	_indicator.offset_right  = -8.0
	_indicator.offset_top    = -36.0
	_indicator.offset_bottom = -8.0
	_indicator.modulate      = Color(1.0, 1.0, 1.0, 0.22)
	_indicator.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_indicator.visible       = false
	root.add_child(_indicator)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			enabled = not enabled
			_indicator.visible = enabled
			debug_mode_changed.emit(enabled)
			get_viewport().set_input_as_handled()
