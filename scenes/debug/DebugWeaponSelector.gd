extends VBoxContainer

# [name, potency, flat_atk, flat_def, pool_bonus]
const PRESETS := [
	["Crude Club",    1, 0, 0,  0],
	["Iron Sword",    2, 1, 0,  0],
	["Steel Sword",   3, 2, 0,  0],
	["Guard Shield",  2, 0, 2,  0],
	["Surge Axe",     3, 1, 0,  1],
	["Master Blade",  4, 3, 0,  0],
]

@onready var _toggle: Button       = $ToggleButton
@onready var _panel:  VBoxContainer = $Panel
@onready var _status: Label        = $Panel/StatusLabel


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	for preset in PRESETS:
		var name: String  = preset[0]
		var pot:  int     = preset[1]
		var atk:  int     = preset[2]
		var def:  int     = preset[3]
		var pool: int     = preset[4]
		var btn := Button.new()
		btn.text = _label(name, pot, atk, def, pool)
		btn.pressed.connect(_apply.bind(name, pot, atk, def, pool))
		$Panel/Buttons.add_child(btn)


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "⚔ Weapon ▾" if _panel.visible else "⚔ Weapon ▸"


func _apply(name: String, pot: int, atk: int, def: int, pool: int) -> void:
	var w := EquipmentData.new()
	w.item_name = name
	w.potency = pot
	w.flat_attack_bonus = atk
	w.flat_guard_bonus = def
	w.pool_bonus = pool
	CombatManager.debug_set_player_weapon(w)
	_status.text = "Active: %s" % _label(name, pot, atk, def, pool)


func _label(name: String, pot: int, atk: int, def: int, pool: int) -> String:
	var parts := ["P%d" % pot]
	if atk  != 0: parts.append("+%d atk" % atk)
	if def  != 0: parts.append("+%d def" % def)
	if pool != 0: parts.append("%+d pool" % pool)
	return "%s  [%s]" % [name, "  ".join(parts)]
