extends VBoxContainer

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

	for w: EquipmentData in PlayerProgression.AVAILABLE_WEAPONS:
		var btn := Button.new()
		btn.text = _label(w)
		btn.pressed.connect(_apply_weapon.bind(w))
		$Panel/Buttons.add_child(btn)

	_refresh_ui()


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	_toggle.text = "⚔ Weapon ▾" if _panel.visible else "⚔ Weapon ▸"


func _set_slot(slot: String) -> void:
	_slot = slot
	_refresh_ui()


func _apply_weapon(w: EquipmentData) -> void:
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

	_main_slot_btn.text = "▶ Main" if _slot == "main" else "  Main"
	_off_slot_btn.text  = "▶ Off"  if _slot == "off"  else "  Off"

	_off_slot_btn.disabled = mh_two_handed

	var mh_name := mh.item_name if mh else "(empty)"
	var oh_name := oh.item_name if oh else "(empty)"
	if mh_two_handed:
		oh_name = "—— (2H)"
	_status.text = "MH: %s  |  OH: %s" % [mh_name, oh_name]


func _label(w: EquipmentData) -> String:
	var parts := ["P%d" % w.potency]
	for mod in w.action_modifiers:
		if mod.action_key == "strike":
			if mod.flat_bonus  != 0: parts.append("+%d atk" % mod.flat_bonus)
			if mod.pool_bonus  != 0: parts.append("%+d pool" % mod.pool_bonus)
		elif mod.action_key == "defend":
			if mod.flat_bonus  != 0: parts.append("+%d def" % mod.flat_bonus)
	if not w.tags.is_empty():
		parts.append("[%s]" % ", ".join(w.tags))
	return "%s  %s" % [w.item_name, "  ".join(parts)]
