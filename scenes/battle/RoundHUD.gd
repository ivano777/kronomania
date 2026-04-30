# RoundHUD — round counter, phase label, cascading action panel, and scrollable combat log.
# Action UI is a three-layer cascade: Intent → Tool → Execution, all built in code inside ActionPanel.
class_name RoundHUD
extends VBoxContainer

signal strike_confirmed(pool: String, brutal_trade: bool)
signal cantrip_selected(spell: SpellData)
signal spell_selected(spell: SpellData)
signal wound_degrade_chosen(use_charge: bool)

@onready var _round_label:  Label         = $RoundLabel
@onready var _phase_label:  Label         = $PhaseLabel
@onready var _action_panel: VBoxContainer = $ActionPanel
@onready var _log_text:     RichTextLabel = $LogScroll/LogText
@onready var _debug_adv = $DebugAdvantageControl if has_node("DebugAdvantageControl") else null

# Magic availability cached from player_magic_available signal.
var _can_cantrip: bool    = false
var _can_cast_spell: bool = false

# Back-navigation state.
var _last_intents: Array[String] = []
var _current_intent: String      = ""
var _tool_was_collapsed: bool    = false

# Brutal Trade toggle — lives in execution panel; kept as field for get_brutal_trade().
var _brutal_toggle: CheckButton = null

# Meat for the Grinder prompt overlay (appended to this VBox, below the log).
var _massive_overlay: PanelContainer
var _massive_spend_btn: Button


func _ready() -> void:
	_massive_overlay = PanelContainer.new()
	_massive_overlay.visible = false
	var overlay_vbox := VBoxContainer.new()
	var overlay_label := Label.new()
	overlay_label.text = "Massive Wound incoming!"
	overlay_vbox.add_child(overlay_label)
	_massive_spend_btn = Button.new()
	_massive_spend_btn.pressed.connect(func() -> void: _on_massive_choice(true))
	overlay_vbox.add_child(_massive_spend_btn)
	var accept_btn := Button.new()
	accept_btn.text = "Accept Massive Wound"
	accept_btn.pressed.connect(func() -> void: _on_massive_choice(false))
	overlay_vbox.add_child(accept_btn)
	_massive_overlay.add_child(overlay_vbox)
	add_child(_massive_overlay)


# ── Public API called by BattleScene ─────────────────────────────────────────

func set_round(n: int) -> void:
	_round_label.text = "Round %d" % n


func set_phase(text: String) -> void:
	_phase_label.text = text


## Cache magic availability; execution panel reads these when building the magic list.
func enable_magic(can_cantrip: bool, can_cast_spell: bool) -> void:
	_can_cantrip    = can_cantrip
	_can_cast_spell = can_cast_spell


## Build and show the Intent row. Called each round via player_intents_available.
func show_intents(intents: Array[String]) -> void:
	_last_intents   = intents.duplicate()
	_current_intent = ""
	_brutal_toggle  = null
	_clear_action_panel()
	for intent in intents:
		var btn := Button.new()
		match intent:
			"attack":
				btn.text = "⚔  Attack"
				btn.pressed.connect(_on_intent_attack)
			"magic":
				btn.text = "✦  Magic"
				btn.pressed.connect(_on_intent_magic)
			"item":
				btn.text = "⊕  Item  (coming soon)"
				btn.disabled = true
		_action_panel.add_child(btn)


## Clear the action panel. Called when combat resolution begins.
func disable_actions() -> void:
	_brutal_toggle = null
	_clear_action_panel()


func get_net_advantage() -> int:
	return _debug_adv.get_net_advantage() if _debug_adv else 0


func get_brutal_trade() -> bool:
	return _brutal_toggle.button_pressed if is_instance_valid(_brutal_toggle) else false


## Show the Meat for the Grinder decision prompt; clears the action panel first.
func show_massive_prompt(charges_left: int) -> void:
	_brutal_toggle = null
	_clear_action_panel()
	_massive_spend_btn.text = "Meat for the Grinder — spend charge (%d left)" % charges_left
	_massive_overlay.visible = true


func add_log(text: String) -> void:
	_log_text.append_text(text + "\n")


func clear_log() -> void:
	_log_text.clear()


# ── Private — panel management ────────────────────────────────────────────────

func _clear_action_panel() -> void:
	for child in _action_panel.get_children():
		child.queue_free()


func _make_back_btn(on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = "← Back"
	btn.pressed.connect(on_press)
	return btn


# ── Intent layer ──────────────────────────────────────────────────────────────

func _on_intent_attack() -> void:
	_current_intent = "attack"
	_show_tool_panel("attack")


func _on_intent_magic() -> void:
	_current_intent = "magic"
	_show_tool_panel("magic")


# ── Tool layer ────────────────────────────────────────────────────────────────

func _show_tool_panel(intent: String) -> void:
	var entries: Array = _build_tool_entries(intent)
	if entries.size() == 1:
		_tool_was_collapsed = true
		_on_tool_selected(intent, entries[0]["data"])
		return
	_tool_was_collapsed = false
	_clear_action_panel()
	_action_panel.add_child(_make_back_btn(func() -> void: show_intents(_last_intents)))
	for entry in entries:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = entry["name"] as String
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var summary: String = entry["summary"] as String
		if summary != "":
			var sum_lbl := Label.new()
			sum_lbl.text = summary
			row.add_child(sum_lbl)
		var sel_btn := Button.new()
		sel_btn.text = "Select"
		var _intent := intent
		var _data   = entry["data"]
		sel_btn.pressed.connect(func() -> void: _on_tool_selected(_intent, _data))
		row.add_child(sel_btn)
		_action_panel.add_child(row)


func _build_tool_entries(intent: String) -> Array:
	var entries: Array = []
	match intent:
		"attack":
			var w: EquipmentData = PlayerProgression.equipped_weapon
			if w:
				for mod: ActionModifier in w.action_modifiers:
					if mod.action_key == "strike":
						entries.append({"name": w.item_name, "summary": _format_modifier_summary(mod), "data": mod})
			if entries.is_empty():
				entries.append({"name": "Bare Hands", "summary": "", "data": null})
		"magic":
			entries.append({"name": "[Arcane Arts]", "summary": "Stat: Ingenuity", "data": null})
	return entries


func _format_modifier_summary(mod: ActionModifier) -> String:
	var parts: Array[String] = []
	if mod.flat_bonus != 0:
		parts.append("Flat %+d" % mod.flat_bonus)
	if mod.tier_cap > 0:
		parts.append("Tier ≤ %d" % mod.tier_cap)
	return "  ".join(parts)


func _on_tool_selected(intent: String, _data) -> void:
	match intent:
		"attack": _show_execution_strike()
		"magic":  _show_execution_magic()


# ── Execution layer ───────────────────────────────────────────────────────────

func _show_execution_strike() -> void:
	_clear_action_panel()
	var preview: int = CombatManager.get_player_attack_preview()
	if _tool_was_collapsed:
		_action_panel.add_child(_make_back_btn(func() -> void: show_intents(_last_intents)))
	else:
		_action_panel.add_child(_make_back_btn(func() -> void: _show_tool_panel(_current_intent)))
	for pool_name: String in ["stance", "resolve", "stamina"]:
		var row := HBoxContainer.new()
		var pool_btn := Button.new()
		pool_btn.text = pool_name.capitalize()
		pool_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _p: String = pool_name
		pool_btn.pressed.connect(func() -> void: _confirm_strike(_p))
		row.add_child(pool_btn)
		var preview_lbl := Label.new()
		preview_lbl.text = "~%d avg" % preview
		row.add_child(preview_lbl)
		var pin_btn := Button.new()
		pin_btn.text = "★"
		pin_btn.custom_minimum_size = Vector2(32, 0)
		var _pp: String = pool_name
		var _pin: Button = pin_btn
		pin_btn.pressed.connect(func() -> void: _pin_strike_pool(_pp, _pin))
		row.add_child(pin_btn)
		_action_panel.add_child(row)
	if PlayerProgression.get_node_level_by_id("dom_brutal") >= 1:
		_brutal_toggle = CheckButton.new()
		_brutal_toggle.text = "Brutal Trade  (VT −5 / Flat +5)"
		_action_panel.add_child(_brutal_toggle)


func _show_execution_magic() -> void:
	var cantrips: Array = PlayerProgression.get_known_cantrips()
	var spells: Array   = PlayerProgression.get_known_spells()
	# Auto-fire: only one option total — skip panel entirely.
	if _can_cantrip and not _can_cast_spell and cantrips.size() == 1:
		disable_actions()
		cantrip_selected.emit(cantrips[0] as SpellData)
		return
	if _can_cast_spell and not _can_cantrip and spells.size() == 1:
		disable_actions()
		spell_selected.emit(spells[0] as SpellData)
		return
	_clear_action_panel()
	if _tool_was_collapsed:
		_action_panel.add_child(_make_back_btn(func() -> void: show_intents(_last_intents)))
	else:
		_action_panel.add_child(_make_back_btn(func() -> void: _show_tool_panel(_current_intent)))
	if _can_cantrip and cantrips.size() > 0:
		var lbl := Label.new()
		lbl.text = "— Cantrips —"
		_action_panel.add_child(lbl)
		for sp_data in cantrips:
			var sp := sp_data as SpellData
			var btn := Button.new()
			btn.text = sp.spell_name
			btn.tooltip_text = sp.description
			btn.pressed.connect(func() -> void:
				disable_actions()
				cantrip_selected.emit(sp)
			)
			_action_panel.add_child(btn)
	if _can_cast_spell and spells.size() > 0:
		var lbl := Label.new()
		lbl.text = "— Spells —"
		_action_panel.add_child(lbl)
		for sp_data in spells:
			var sp := sp_data as SpellData
			var btn := Button.new()
			btn.text = sp.spell_name
			btn.tooltip_text = sp.description
			btn.pressed.connect(func() -> void:
				disable_actions()
				spell_selected.emit(sp)
			)
			_action_panel.add_child(btn)


func _confirm_strike(pool: String) -> void:
	var bt: bool = get_brutal_trade()
	disable_actions()
	strike_confirmed.emit(pool, bt)


func _pin_strike_pool(pool: String, btn: Button) -> void:
	PlayerProgression.combat_prefs.defaults["attack.strike.pool"] = pool
	btn.text = "✓"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(btn):
		btn.text = "★"


func _on_massive_choice(use_charge: bool) -> void:
	_massive_overlay.visible = false
	wound_degrade_chosen.emit(use_charge)
