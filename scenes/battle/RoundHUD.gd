# RoundHUD — round counter, phase label, Strike/Cantrip/Spell buttons, and scrollable combat log.
class_name RoundHUD
extends VBoxContainer

signal strike_pressed
signal cantrip_pressed
signal spell_pressed

@onready var _round_label:  Label         = $RoundLabel
@onready var _phase_label:  Label         = $PhaseLabel
@onready var _strike_btn:   Button        = $StrikeButton
@onready var _cantrip_btn:  Button        = $CantripButton
@onready var _spell_btn:    Button        = $SpellButton
@onready var _log_text:     RichTextLabel = $LogScroll/LogText
# Debug controls — null when nodes are absent (removed for release).
@onready var _debug_adv  = $DebugAdvantageControl if has_node("DebugAdvantageControl") else null
@onready var _debug_pool = $DebugPoolSelector     if has_node("DebugPoolSelector")     else null


func _ready() -> void:
	_strike_btn.pressed.connect(_on_strike_pressed)
	_cantrip_btn.pressed.connect(_on_cantrip_pressed)
	_spell_btn.pressed.connect(_on_spell_pressed)
	_strike_btn.disabled = true
	_cantrip_btn.disabled = true
	_spell_btn.disabled = true


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
	disable_strike()
	disable_magic()
	cantrip_pressed.emit()


func _on_spell_pressed() -> void:
	disable_strike()
	disable_magic()
	spell_pressed.emit()
