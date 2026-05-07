extends VBoxContainer

@onready var _toggle:       Button        = $ToggleButton
@onready var _panel:        VBoxContainer = $Panel
@onready var _immortal_btn: Button        = $Panel/ImmortalBtn
@onready var _lethal_btn:   Button        = $Panel/LethalBtn

var _immortal: bool = false
var _lethal:   bool = false


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	$Panel/RefillHPBtn.pressed.connect(_on_refill_hp)
	_immortal_btn.pressed.connect(_on_toggle_immortal)
	_lethal_btn.pressed.connect(_on_toggle_lethal)

	_immortal = CombatManager._debug_immortal
	_lethal   = CombatManager._debug_lethal
	_immortal_btn.text = "Immortal: ON" if _immortal else "Immortal: OFF"
	_lethal_btn.text   = "Lethal: ON"   if _lethal   else "Lethal: OFF"

	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "💀 Combat ▾" if _panel.visible else "💀 Combat ▸"


func _on_refill_hp() -> void:
	CombatManager.debug_refill_hp()


func _on_toggle_immortal() -> void:
	_immortal = not _immortal
	CombatManager.debug_set_immortal(_immortal)
	_immortal_btn.text = "Immortal: ON" if _immortal else "Immortal: OFF"


func _on_toggle_lethal() -> void:
	_lethal = not _lethal
	CombatManager.debug_set_lethal(_lethal)
	_lethal_btn.text = "Lethal: ON" if _lethal else "Lethal: OFF"
