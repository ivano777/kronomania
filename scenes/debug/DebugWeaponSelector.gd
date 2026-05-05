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

var _slot: String = "main"  # "main" or "off"

@onready var _toggle:        Button        = $ToggleButton
@onready var _panel:         VBoxContainer = $Panel
@onready var _status:        Label         = $Panel/StatusLabel
@onready var _main_slot_btn: Button        = $Panel/SlotRow/MainSlotBtn
@onready var _off_slot_btn:  Button        = $Panel/SlotRow/OffSlotBtn


func _ready() -> void:
	_panel.hide()
	_toggle.pressed.connect(_on_toggle)
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)

	_main_slot_btn.pressed.connect(func() -> void: _set_slot("main"))
	_off_slot_btn.pressed.connect(func() -> void: _set_slot("off"))

	for preset in PRESETS:
		var pname: String = preset[0]
		var pot:   int    = preset[1]
		var atk:   int    = preset[2]
		var def:   int    = preset[3]
		var pool:  int    = preset[4]
		var btn := Button.new()
		btn.text = _label(pname, pot, atk, def, pool)
		btn.pressed.connect(_apply.bind(pname, pot, atk, def, pool))
		$Panel/Buttons.add_child(btn)

	_refresh_ui()


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "⚔ Weapon ▾" if _panel.visible else "⚔ Weapon ▸"


func _set_slot(slot: String) -> void:
	_slot = slot
	_refresh_ui()


func _apply(pname: String, pot: int, atk: int, def: int, pool: int) -> void:
	var w := EquipmentData.new()
	w.item_name = pname
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

	if _slot == "main":
		PlayerProgression.equip_main_hand(w)
		CombatManager.debug_set_player_weapon(w)
	else:
		PlayerProgression.equip_off_hand(w)
		CombatManager.debug_set_player_off_hand(w)

	_refresh_ui()


func _refresh_ui() -> void:
	var mh: EquipmentData = PlayerProgression.main_hand
	var oh: EquipmentData = PlayerProgression.off_hand
	var mh_two_handed: bool = mh != null and mh.get_hands_required() == 2

	# Highlight the active slot button.
	_main_slot_btn.text = "▶ Main" if _slot == "main" else "  Main"
	_off_slot_btn.text  = "▶ Off"  if _slot == "off"  else "  Off"

	# Gray out Off button when a two-handed weapon occupies both hand slots.
	_off_slot_btn.disabled = mh_two_handed

	var mh_name := mh.item_name if mh else "(empty)"
	var oh_name := oh.item_name if oh else "(empty)"
	if mh_two_handed:
		oh_name = "—— (2H)"
	_status.text = "MH: %s  |  OH: %s" % [mh_name, oh_name]


func _label(pname: String, pot: int, atk: int, def: int, pool: int) -> String:
	var parts := ["P%d" % pot]
	if atk  != 0: parts.append("+%d atk" % atk)
	if def  != 0: parts.append("+%d def" % def)
	if pool != 0: parts.append("%+d pool" % pool)
	return "%s  [%s]" % [pname, "  ".join(parts)]
