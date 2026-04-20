extends VBoxContainer

const PRESETS := [
	["Iron Sword  (+1 atk)",        1, 0, 0],
	["Sharp Blade (+2 atk)",        2, 0, 0],
	["Guard Shield (+2 def)",       0, 2, 0],
	["Surge Axe (+1 atk +1 pool)",  1, 0, 1],
	["Crude Club  (none)",          0, 0, 0],
]

@onready var _toggle: Button       = $ToggleButton
@onready var _panel:  VBoxContainer = $Panel
@onready var _status: Label        = $Panel/StatusLabel


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	for preset in PRESETS:
		var btn := Button.new()
		btn.text = preset[0] as String
		btn.pressed.connect(_apply.bind(
			preset[0] as String, preset[1] as int,
			preset[2] as int, preset[3] as int))
		$Panel/Buttons.add_child(btn)


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "⚔ Weapon ▾" if _panel.visible else "⚔ Weapon ▸"


func _apply(name: String, atk: int, def: int, pool: int) -> void:
	var w := EquipmentData.new()
	w.item_name = name
	w.potency = 1
	w.flat_attack_bonus = atk
	w.flat_guard_bonus = def
	w.pool_bonus = pool
	CombatManager.debug_set_player_weapon(w)
	_status.text = "Active: %s" % name
