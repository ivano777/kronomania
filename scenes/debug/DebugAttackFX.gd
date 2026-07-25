# DebugAttackFX — replays the attack presentation with mock payloads.
# Debug-only widget (scenes/debug/), removable at release.
extends VBoxContainer

@onready var _toggle: Button        = $ToggleButton
@onready var _panel:  VBoxContainer = $Panel


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	$Panel/HitBtn.pressed.connect(func() -> void: _replay("hit"))
	$Panel/MassiveBtn.pressed.connect(func() -> void: _replay("massive"))
	$Panel/BlockedBtn.pressed.connect(func() -> void: _replay("blocked"))
	$Panel/KillBtn.pressed.connect(func() -> void: _replay("kill"))

	# Weapon-smear toggle: flips the global DebugManager flag so the next swing
	# frame draws the raw held art instead of the baked smear (A/B comparison).
	var smear_btn := $Panel/SmearBtn as Button
	smear_btn.button_pressed = DebugManager.smears_enabled
	smear_btn.toggled.connect(func(on: bool) -> void:
		DebugManager.smears_enabled = on
		smear_btn.text = "Smears: ON" if on else "Smears: OFF")
	smear_btn.text = "Smears: ON" if DebugManager.smears_enabled else "Smears: OFF"

	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "• AttackFX ▼" if _panel.visible else "• AttackFX ▶"


func _replay(kind: String) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("debug_replay_attack"):
		scene.debug_replay_attack(kind)
