extends VBoxContainer

# Start-screen dev entry — F12 (global DebugManager toggle) reveals a single
# button that jumps to the dedicated DevHubScene, keeping all sandbox tooling
# and its context out of the player-facing menu.

@onready var _open_btn: Button = $OpenButton


func _ready() -> void:
	_open_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/debug/DevHubScene.tscn"))
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)
	# MainMenu builds its UI in code after .tscn children instantiate — jump to
	# the front so the full-rect background/scroll neither covers nor steals input.
	move_to_front.call_deferred()
