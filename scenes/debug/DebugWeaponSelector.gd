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
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)
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

	var strike_mod := ActionModifier.new()
	strike_mod.action_key = "strike"
	strike_mod.action_name = "Strike"
	strike_mod.tier_cap = pot
	strike_mod.flat_bonus = atk
	strike_mod.pool_bonus = pool

	var defend_mod := ActionModifier.new()
	defend_mod.action_key = "defend"
	defend_mod.action_name = "Defend"
	defend_mod.tier_cap = pot
	defend_mod.flat_bonus = def

	w.action_modifiers = [strike_mod, defend_mod]
	CombatManager.debug_set_player_weapon(w)
	_status.text = "Active: %s" % _label(name, pot, atk, def, pool)


func _label(name: String, pot: int, atk: int, def: int, pool: int) -> String:
	var parts := ["P%d" % pot]
	if atk  != 0: parts.append("+%d atk" % atk)
	if def  != 0: parts.append("+%d def" % def)
	if pool != 0: parts.append("%+d pool" % pool)
	return "%s  [%s]" % [name, "  ".join(parts)]
