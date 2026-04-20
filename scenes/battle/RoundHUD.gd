# RoundHUD — round counter, phase label, Strike button, and scrollable combat log.
class_name RoundHUD
extends VBoxContainer

signal strike_pressed

@onready var _round_label:  Label         = $RoundLabel
@onready var _phase_label:  Label         = $PhaseLabel
@onready var _strike_btn:   Button        = $StrikeButton
@onready var _log_text:     RichTextLabel = $LogScroll/LogText
# Debug control — null when node is absent (removed for release).
@onready var _debug_adv = $DebugAdvantageControl if has_node("DebugAdvantageControl") else null


func _ready() -> void:
	_strike_btn.pressed.connect(_on_strike_pressed)
	_strike_btn.disabled = true


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


# Append one line to the combat log. Supports BBCode.
func add_log(text: String) -> void:
	_log_text.append_text(text + "\n")


func clear_log() -> void:
	_log_text.clear()


## Returns the current net advantage set by the debug control (0 if absent).
func get_net_advantage() -> int:
	return _debug_adv.get_net_advantage() if _debug_adv else 0


# ── Private ───────────────────────────────────────────────────────────────────

func _on_strike_pressed() -> void:
	disable_strike()
	strike_pressed.emit()
