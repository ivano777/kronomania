extends Node

signal debug_mode_changed(enabled: bool)

var enabled: bool = false

# Set by DebugDevMenu before switching into a dev-tool scene (held editor):
# the tool returns here on exit instead of quitting. Empty = standalone run.
var return_scene: String = ""

# Battle-debug toggle for procedural weapon smear frames (SmearGen). ON by
# default — production behaviour; the debug dock widget can switch it off to
# compare swings with the raw held art.
var smears_enabled: bool = true

# True once DevHubScene initialised its persistent dev sandbox (999pt
# progression, run_active, active_slot 0). Scene jumps keep state while set.
# Cleared by MainMenu when real play starts (New Game / Load).
var sandbox_active: bool = false


## Sandbox navigation collapse: while the sandbox is active, every back/exit
## navigation lands on the DevHub instead of its normal target, keeping the
## dev environment fully closed. Forward navigation (e.g. campfire → battle)
## must NOT route through this. Release builds never set sandbox_active, so
## this always returns default_path there.
func nav_target(default_path: String) -> String:
	return "res://scenes/debug/DevHubScene.tscn" if sandbox_active else default_path

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
