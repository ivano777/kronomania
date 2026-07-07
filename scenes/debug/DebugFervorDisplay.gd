extends VBoxContainer

var _current_fervor: int = 4
var _current_burned_out: bool = false
var _current_cap: int = 6

@onready var _toggle:      Button        = $ToggleButton
@onready var _panel:       VBoxContainer = $Panel
@onready var _status:      Label         = $Panel/StatusLabel
@onready var _escalate:    Button        = $Panel/EscalateButton
@onready var _burnout_btn: Button        = $Panel/BurnoutButton


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	_escalate.pressed.connect(_on_escalate)
	_burnout_btn.pressed.connect(_on_toggle_burnout)
	CombatManager.fervor_changed.connect(_on_fervor_changed)
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "♦ Fervor ▼" if _panel.visible else "♦ Fervor ▶"


func _on_fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool) -> void:
	if not is_player:
		return
	_current_fervor = fervor_size
	_current_cap = fervor_cap
	_current_burned_out = is_burned_out
	var burnout_str := "  [BURNOUT]" if is_burned_out else ""
	_status.text = "Fervor: d%d / d%d%s" % [fervor_size, fervor_cap, burnout_str]
	_escalate.disabled = fervor_size >= fervor_cap
	_burnout_btn.text = "Clear Burnout" if is_burned_out else "Force Burnout"


func _on_escalate() -> void:
	const TRACK: Array[int] = [4, 6, 8, 10]
	var idx := TRACK.find(_current_fervor)
	if idx == -1:
		idx = 0
	var next: int = TRACK[mini(idx + 1, TRACK.size() - 1)]
	CombatManager.debug_set_fervor(next, _current_burned_out)


func _on_toggle_burnout() -> void:
	CombatManager.debug_set_fervor(_current_fervor, not _current_burned_out)
