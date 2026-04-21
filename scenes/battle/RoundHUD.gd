# RoundHUD — round counter, phase label, Strike/Cantrip/Spell buttons, and scrollable combat log.
# Spell and Cantrip buttons open an in-place popup listing known spells/cantrips.
class_name RoundHUD
extends VBoxContainer

signal strike_pressed
signal spell_selected(spell: SpellData)
signal cantrip_selected(spell: SpellData)

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


func _ready() -> void:
	_strike_btn.pressed.connect(_on_strike_pressed)
	_cantrip_btn.pressed.connect(_on_cantrip_pressed)
	_spell_btn.pressed.connect(_on_spell_pressed)
	_strike_btn.disabled = true
	_cantrip_btn.disabled = true
	_spell_btn.disabled = true

	# Build spell selection popup.
	_popup = PanelContainer.new()
	_popup.visible = false
	_popup_list = VBoxContainer.new()
	_popup.add_child(_popup_list)
	add_child(_popup)


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
