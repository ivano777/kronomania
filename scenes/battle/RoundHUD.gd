# RoundHUD — round counter, phase label, Strike/Cantrip/Spell buttons, and scrollable combat log.
# Spell and Cantrip buttons open an in-place popup listing known spells/cantrips.
class_name RoundHUD
extends VBoxContainer

signal strike_pressed
signal spell_selected(spell: SpellData)
signal cantrip_selected(spell: SpellData)
signal wound_degrade_chosen(use_charge: bool)

@onready var _round_label:  Label         = $RoundLabel
@onready var _phase_label:  Label         = $PhaseLabel
@onready var _strike_btn:   Button        = $StrikeButton
@onready var _cantrip_btn:  Button        = $CantripButton
@onready var _spell_btn:    Button        = $SpellButton
@onready var _log_text:     RichTextLabel = $LogScroll/LogText
# Debug controls — null when nodes are absent (removed for release).
@onready var _debug_adv  = $DebugAdvantageControl if has_node("DebugAdvantageControl") else null
@onready var _debug_pool = $DebugPoolSelector     if has_node("DebugPoolSelector")     else null

var _known_spells: Array   = []  # Array[SpellData]
var _known_cantrips: Array = []  # Array[SpellData]

# Popup panel built in code — no .tscn edit required.
var _popup: PanelContainer
var _popup_list: VBoxContainer

# Brutal Trade toggle — visible only when dom_brutal >= 1.
var _brutal_toggle: CheckButton

# Meat for the Grinder prompt overlay.
var _massive_overlay: PanelContainer
var _massive_spend_btn: Button


func _ready() -> void:
	_strike_btn.pressed.connect(_on_strike_pressed)
	_cantrip_btn.pressed.connect(_on_cantrip_pressed)
	_spell_btn.pressed.connect(_on_spell_pressed)
	_strike_btn.disabled = true
	_cantrip_btn.disabled = true
	_spell_btn.disabled = true

	# Brutal Trade toggle (visible only when dom_brutal is purchased).
	_brutal_toggle = CheckButton.new()
	_brutal_toggle.text = "Brutal Trade  (VT −5 / Flat +5)"
	_brutal_toggle.visible = PlayerProgression.get_node_level_by_id("dom_brutal") >= 1
	add_child(_brutal_toggle)
	move_child(_brutal_toggle, _strike_btn.get_index() + 1)

	# Build spell selection popup.
	_popup = PanelContainer.new()
	_popup.visible = false
	_popup_list = VBoxContainer.new()
	_popup.add_child(_popup_list)
	add_child(_popup)

	# Meat for the Grinder decision overlay.
	_massive_overlay = PanelContainer.new()
	_massive_overlay.visible = false
	var _overlay_vbox := VBoxContainer.new()
	var _overlay_label := Label.new()
	_overlay_label.text = "Massive Wound incoming!"
	_overlay_vbox.add_child(_overlay_label)
	_massive_spend_btn = Button.new()
	_massive_spend_btn.pressed.connect(func() -> void: _on_massive_choice(true))
	_overlay_vbox.add_child(_massive_spend_btn)
	var _accept_btn := Button.new()
	_accept_btn.text = "Accept Massive Wound"
	_accept_btn.pressed.connect(func() -> void: _on_massive_choice(false))
	_overlay_vbox.add_child(_accept_btn)
	_massive_overlay.add_child(_overlay_vbox)
	add_child(_massive_overlay)


# ── Public API called by BattleScene ─────────────────────────────────────────

func set_round(n: int) -> void:
	_round_label.text = "Round %d" % n


func set_phase(text: String) -> void:
	_phase_label.text = text


func enable_strike() -> void:
	_strike_btn.disabled = false
	_strike_btn.grab_focus()


func disable_strike() -> void:
	_strike_btn.disabled = true


## Store the known spells/cantrips so the popup can be populated on demand.
func set_spell_lists(spells: Array, cantrips: Array) -> void:
	_known_spells   = spells
	_known_cantrips = cantrips


## Show and enable magic action buttons based on what is currently available.
## Called by BattleScene on player_magic_available signal.
func enable_magic(can_cantrip: bool, can_cast_spell: bool) -> void:
	_cantrip_btn.visible = can_cantrip
	_cantrip_btn.disabled = not can_cantrip
	_spell_btn.visible = can_cast_spell
	_spell_btn.disabled = not can_cast_spell


## Disable all magic buttons (called when resolution begins).
func disable_magic() -> void:
	_cantrip_btn.disabled = true
	_spell_btn.disabled = true


# Append one line to the combat log. Supports BBCode.
func add_log(text: String) -> void:
	_log_text.append_text(text + "\n")


func clear_log() -> void:
	_log_text.clear()


## Returns the current net advantage set by the debug control (0 if absent).
func get_net_advantage() -> int:
	return _debug_adv.get_net_advantage() if _debug_adv else 0


## Returns the target defense pool set by the debug control ("stance" if absent).
func get_target_pool() -> String:
	return _debug_pool.get_target_pool() if _debug_pool else "stance"


## Returns whether Brutal Trade is toggled on (false if toggle absent or not visible).
func get_brutal_trade() -> bool:
	return _brutal_toggle.button_pressed if (_brutal_toggle and _brutal_toggle.visible) else false


## Show the Meat for the Grinder decision overlay; disables normal action buttons.
func show_massive_prompt(charges_left: int) -> void:
	_strike_btn.disabled = true
	_cantrip_btn.disabled = true
	_spell_btn.disabled = true
	_massive_spend_btn.text = "Meat for the Grinder — spend charge (%d left)" % charges_left
	_massive_overlay.visible = true


# ── Private ───────────────────────────────────────────────────────────────────

func _on_strike_pressed() -> void:
	disable_strike()
	disable_magic()
	strike_pressed.emit()


func _on_cantrip_pressed() -> void:
	if _known_cantrips.size() == 1:
		disable_strike()
		disable_magic()
		cantrip_selected.emit(_known_cantrips[0] as SpellData)
	else:
		_show_popup(_known_cantrips, true)


func _on_spell_pressed() -> void:
	if _known_spells.size() == 1:
		disable_strike()
		disable_magic()
		spell_selected.emit(_known_spells[0] as SpellData)
	else:
		_show_popup(_known_spells, false)


func _on_massive_choice(use_charge: bool) -> void:
	_massive_overlay.visible = false
	wound_degrade_chosen.emit(use_charge)


func _show_popup(spells: Array, is_cantrip: bool) -> void:
	# Clear previous buttons.
	for child in _popup_list.get_children():
		child.queue_free()

	for spell_data in spells:
		var sp := spell_data as SpellData
		var btn := Button.new()
		btn.text = sp.spell_name
		btn.tooltip_text = sp.description
		btn.pressed.connect(func() -> void:
			_popup.visible = false
			disable_strike()
			disable_magic()
			if is_cantrip:
				cantrip_selected.emit(sp)
			else:
				spell_selected.emit(sp)
		)
		_popup_list.add_child(btn)

	_popup.visible = true
