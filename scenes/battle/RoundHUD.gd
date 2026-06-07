# RoundHUD — round counter, phase label, cascading action panel, and scrollable combat log.
# Action UI is a three-layer cascade: Intent → Weapon → Action, all built in code inside ActionPanel.
class_name RoundHUD
extends VBoxContainer

signal strike_confirmed(pool: String, brutal_trade: bool, source_weapon: EquipmentData)
signal cantrip_selected(spell: SpellData, source_weapon: EquipmentData)
signal spell_selected(spell: SpellData, source_weapon: EquipmentData)
signal wound_degrade_chosen(use_charge: bool)
signal burnout_prevent_chosen(use_charge: bool)
signal auto_attack_requested()

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
var _current_weapon_item         = null   # EquipmentData or null for bare hands
var _action_was_collapsed: bool  = false

# Brutal Trade toggle — lives in execution panel; kept as field for get_brutal_trade().
var _brutal_toggle: CheckButton = null

# ATK/DEF mode toggle buttons — persistent strip above the action panel.
var _atk_mode_btn: Button = null
var _def_mode_btn: Button = null

# Meat for the Grinder prompt overlay (appended to this VBox, below the log).
var _massive_overlay: PanelContainer
var _massive_spend_btn: Button

# Lucidity L2 Burnout prompt overlay (appended to this VBox, below the log).
var _burnout_overlay: PanelContainer
var _burnout_spend_btn: Button


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
	# Lucidity L2 Burnout prompt overlay — mirrors massive overlay pattern.
	_burnout_overlay = PanelContainer.new()
	_burnout_overlay.visible = false
	var burnout_vbox := VBoxContainer.new()
	var burnout_label := Label.new()
	burnout_label.text = "BURNOUT IMMINENT!"
	burnout_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	burnout_vbox.add_child(burnout_label)
	var burnout_desc := Label.new()
	burnout_desc.text = "Spend Lucidity charge to avert it?\n(Fervor stays at the edge.)"
	burnout_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	burnout_vbox.add_child(burnout_desc)
	_burnout_spend_btn = Button.new()
	_burnout_spend_btn.pressed.connect(func() -> void: _on_burnout_choice(true))
	burnout_vbox.add_child(_burnout_spend_btn)
	var burnout_accept_btn := Button.new()
	burnout_accept_btn.text = "Let it burn"
	burnout_accept_btn.pressed.connect(func() -> void: _on_burnout_choice(false))
	burnout_vbox.add_child(burnout_accept_btn)
	_burnout_overlay.add_child(burnout_vbox)
	add_child(_burnout_overlay)
	# Mode strip — insert before ActionPanel so it renders between PhaseLabel and the action area.
	var mode_strip := HBoxContainer.new()
	_atk_mode_btn = Button.new()
	_atk_mode_btn.text = "ATK: %s" % PlayerProgression.combat_prefs.atk_mode.capitalize()
	_atk_mode_btn.pressed.connect(_toggle_atk_mode)
	mode_strip.add_child(_atk_mode_btn)
	_def_mode_btn = Button.new()
	_def_mode_btn.text = "DEF: %s" % PlayerProgression.combat_prefs.def_mode.capitalize()
	_def_mode_btn.pressed.connect(_toggle_def_mode)
	mode_strip.add_child(_def_mode_btn)
	add_child(mode_strip)
	move_child(mode_strip, _action_panel.get_index())


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
	_last_intents         = intents.duplicate()
	_current_intent       = ""
	_brutal_toggle        = null
	_current_weapon_item  = null
	_action_was_collapsed = false
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
			"lucidity":
				btn.text = "🧘  Lucidity (cool Fervor)"
				btn.pressed.connect(_on_intent_lucidity)
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


## Show the DEF Observe overlay before the enemy's defense roll; cleared on OK.
func show_defense_overlay(attacker_name: String, attack_total: int, target_pool: String) -> void:
	_clear_action_panel()
	var lbl := Label.new()
	lbl.text = "%s attacks for %d\nPool: %s — defense will roll automatically." % [
		attacker_name, attack_total, target_pool.capitalize()
	]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_action_panel.add_child(lbl)
	var ok_btn := Button.new()
	ok_btn.text = "OK — Roll Defense"
	ok_btn.pressed.connect(func() -> void:
		_clear_action_panel()
		CombatManager.player_acknowledged_defense()
	)
	_action_panel.add_child(ok_btn)


## Show item selection panel when the player must choose a defense item (DEF Observe mode).
## options: Array of { item_name: String, mod: ActionModifier } Dictionaries.
func show_defense_item_choice(options: Array) -> void:
	_clear_action_panel()
	var lbl := Label.new()
	lbl.text = "Choose defensive item:"
	_action_panel.add_child(lbl)
	var saved_wk: String = PlayerProgression.combat_prefs.defaults.get("defend_weapon", "")
	for opt in options:
		var row := HBoxContainer.new()
		var mod: ActionModifier = opt["mod"] as ActionModifier
		var item_name: String = opt["item_name"]
		var cap_str := "uncapped" if mod.tier_cap == 0 else "cap T%d" % mod.tier_cap
		var name_lbl := Label.new()
		name_lbl.text = "%s  (Flat %+d  %s)" % [item_name, mod.flat_bonus, cap_str]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		# Pin button — saves default defense item, mirroring ATK weapon pin.
		var _wk := item_name
		var pin_btn := Button.new()
		pin_btn.text = "✓" if _wk == saved_wk else "★"
		pin_btn.pressed.connect(func() -> void:
			PlayerProgression.combat_prefs.defaults["defend_weapon"] = _wk
			show_defense_item_choice(options)
		)
		row.add_child(pin_btn)
		var sel_btn := Button.new()
		sel_btn.text = "Select"
		var chosen_mod: ActionModifier = mod
		sel_btn.pressed.connect(func() -> void:
			_clear_action_panel()
			CombatManager.player_chose_defense_item(chosen_mod)
		)
		row.add_child(sel_btn)
		_action_panel.add_child(row)


## Show the Meat for the Grinder decision prompt; clears the action panel first.
func show_massive_prompt(charges_left: int) -> void:
	_brutal_toggle = null
	_clear_action_panel()
	_massive_spend_btn.text = "Meat for the Grinder — spend charge (%d left)" % charges_left
	_massive_overlay.visible = true


## Show the Lucidity L2 Burnout-aversion prompt; clears the action panel first.
## Fires mid-resolution (inside _escalate_fervor, during _resolve_round_spell),
## matching the same UI state as the massive prompt during _resolve_attack.
func show_burnout_prompt(charges_left: int) -> void:
	_brutal_toggle = null
	_clear_action_panel()
	_burnout_spend_btn.text = "Avert Burnout — spend Lucidity charge (%d left)" % charges_left
	_burnout_overlay.visible = true


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
	if PlayerProgression.combat_prefs.atk_mode == "auto":
		disable_actions()
		auto_attack_requested.emit()
		return
	_show_tool_panel("attack")


func _on_intent_magic() -> void:
	_current_intent = "magic"
	_show_tool_panel("magic")


func _on_intent_lucidity() -> void:
	disable_actions()
	CombatManager.player_chose_lucidity()


# ── Tool layer ────────────────────────────────────────────────────────────────

func _show_tool_panel(intent: String) -> void:
	var entries: Array = _build_tool_entries(intent)
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
		# Pin button — attack and magic tools; saves default weapon for Auto Mode.
		if entry.has("weapon_key") and (intent == "attack" or intent == "magic"):
			var pref_key := "attack_weapon" if intent == "attack" else "cast_weapon"
			var saved_wk: String = PlayerProgression.combat_prefs.defaults.get(pref_key, "")
			var _wk: String = entry["weapon_key"] as String
			var _intent_copy := intent
			var pin_btn := Button.new()
			pin_btn.text = "✓" if _wk == saved_wk else "★"
			pin_btn.pressed.connect(func() -> void:
				PlayerProgression.combat_prefs.defaults[pref_key] = _wk
				_show_tool_panel(_intent_copy)
			)
			row.add_child(pin_btn)
		var sel_btn := Button.new()
		sel_btn.text = "Select"
		var _intent := intent
		var _data   = entry.get("item", null)
		sel_btn.pressed.connect(func() -> void: _on_tool_selected(_intent, _data))
		row.add_child(sel_btn)
		_action_panel.add_child(row)


func _build_tool_entries(intent: String) -> Array:
	var entries: Array = []
	match intent:
		"attack":
			var added_any := false
			for slot_w: EquipmentData in [PlayerProgression.main_hand, PlayerProgression.off_hand]:
				if slot_w == null:
					continue
				for mod: ActionModifier in slot_w.action_modifiers:
					if mod.action_key == "strike":
						entries.append({"name": slot_w.item_name, "summary": "", "weapon_key": slot_w.item_name, "item": slot_w})
						added_any = true
						break
			if not added_any:
				entries.append({"name": "Bare Hands", "summary": "", "weapon_key": "bare_hands", "item": null})
		"magic":
			var added_any := false
			for slot_w: EquipmentData in [PlayerProgression.main_hand, PlayerProgression.off_hand]:
				if slot_w == null:
					continue
				for mod: ActionModifier in slot_w.action_modifiers:
					if mod.action_key == "cast":
						entries.append({"name": slot_w.item_name, "summary": _format_cast_summary(mod), "weapon_key": slot_w.item_name, "item": slot_w})
						added_any = true
						break
			if not added_any:
				entries.append({"name": "Bare Hands", "summary": "Full Tier", "weapon_key": "bare_hands", "item": null})
	return entries


func _format_cast_summary(mod: ActionModifier) -> String:
	var parts: Array[String] = []
	if mod.tier_cap > 0:
		parts.append("Tier ≤ %d" % mod.tier_cap)
	if mod.pool_bonus != 0:
		parts.append("Pool %+d" % mod.pool_bonus)
	if mod.keep_bonus != 0:
		parts.append("Keep %+d" % mod.keep_bonus)
	if mod.flat_bonus != 0:
		parts.append("Flat %+d" % mod.flat_bonus)
	return "  ".join(parts)


func _format_modifier_summary(mod: ActionModifier) -> String:
	var parts: Array[String] = []
	if mod.flat_bonus != 0:
		parts.append("Flat %+d" % mod.flat_bonus)
	if mod.tier_cap > 0:
		parts.append("Tier ≤ %d" % mod.tier_cap)
	return "  ".join(parts)


func _format_action_summary(mod: ActionModifier) -> String:
	var target_pool: String = mod.target_pool if mod.target_pool != "" else "stance"
	var parts: Array[String] = ["→ %s" % target_pool.capitalize()]
	if mod.flat_bonus != 0:
		parts.append("Flat %+d" % mod.flat_bonus)
	return "  ".join(parts)


func _on_tool_selected(intent: String, data) -> void:
	match intent:
		"attack": _show_action_panel(data)
		"magic":  _show_execution_magic(data as EquipmentData)


# ── Action layer ──────────────────────────────────────────────────────────────

func _show_action_panel(weapon_item) -> void:
	_current_weapon_item  = weapon_item
	_action_was_collapsed = false

	var actions: Array = []
	if weapon_item != null:
		for mod: ActionModifier in (weapon_item as EquipmentData).action_modifiers:
			if mod.action_key == "strike":
				actions.append(mod)
	if actions.is_empty():
		var bh_mod: ActionModifier = CombatManager.get_player_bare_hands_modifier("strike")
		if bh_mod:
			actions.append(bh_mod)

	_clear_action_panel()
	if _tool_was_collapsed:
		_action_panel.add_child(_make_back_btn(func() -> void: show_intents(_last_intents)))
	else:
		_action_panel.add_child(_make_back_btn(func() -> void: _show_tool_panel(_current_intent)))

	var saved_ak: String = PlayerProgression.combat_prefs.defaults.get("attack_action", "")
	for mod: ActionModifier in actions:
		var target_pool: String = mod.target_pool if mod.target_pool != "" else "stance"
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = mod.action_name if mod.action_name != "" else mod.action_key.capitalize()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var info_lbl := Label.new()
		info_lbl.text = _format_action_summary(mod)
		row.add_child(info_lbl)
		var pin_btn := Button.new()
		var _ak := mod.action_key
		pin_btn.text = "✓" if _ak == saved_ak else "★"
		pin_btn.pressed.connect(func() -> void:
			PlayerProgression.combat_prefs.defaults["attack_action"] = _ak
			_show_action_panel(_current_weapon_item)
		)
		row.add_child(pin_btn)
		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm"
		var _tp := target_pool
		confirm_btn.pressed.connect(func() -> void: _confirm_strike(_tp))
		row.add_child(confirm_btn)
		_action_panel.add_child(row)
	if PlayerProgression.get_node_level_by_id("dom_brutal") >= 1:
		_brutal_toggle = _make_persistent_toggle("Brutal Trade  (VT −5 / Flat +5)", "brutal_trade")
		_action_panel.add_child(_brutal_toggle)


func _show_execution_magic(cast_tool: EquipmentData = null) -> void:
	var cantrips: Array = PlayerProgression.get_known_cantrips()
	var spells: Array   = PlayerProgression.get_known_spells()
	# Auto-fire: only one option total — skip panel entirely.
	if _can_cantrip and not _can_cast_spell and cantrips.size() == 1:
		disable_actions()
		cantrip_selected.emit(cantrips[0] as SpellData, cast_tool)
		return
	if _can_cast_spell and not _can_cantrip and spells.size() == 1:
		disable_actions()
		spell_selected.emit(spells[0] as SpellData, cast_tool)
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
			var saved_spell: String = PlayerProgression.combat_prefs.defaults.get("magic", "")
			var row := HBoxContainer.new()
			var cast_btn := Button.new()
			cast_btn.text = ("● " if sp.spell_name == saved_spell else "") + sp.spell_name
			cast_btn.tooltip_text = sp.description
			cast_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cast_btn.pressed.connect(func() -> void:
				disable_actions()
				cantrip_selected.emit(sp, cast_tool)
			)
			row.add_child(cast_btn)
			var pin_btn := Button.new()
			pin_btn.text = "★"
			var _sn := sp.spell_name
			pin_btn.pressed.connect(func() -> void:
				PlayerProgression.combat_prefs.defaults["magic"] = _sn
				_show_execution_magic(cast_tool)
			)
			row.add_child(pin_btn)
			_action_panel.add_child(row)
	if _can_cast_spell and spells.size() > 0:
		var lbl := Label.new()
		lbl.text = "— Spells —"
		_action_panel.add_child(lbl)
		for sp_data in spells:
			var sp := sp_data as SpellData
			var saved_spell: String = PlayerProgression.combat_prefs.defaults.get("magic", "")
			var row := HBoxContainer.new()
			var cast_btn := Button.new()
			cast_btn.text = ("● " if sp.spell_name == saved_spell else "") + sp.spell_name
			cast_btn.tooltip_text = sp.description
			cast_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cast_btn.pressed.connect(func() -> void:
				disable_actions()
				spell_selected.emit(sp, cast_tool)
			)
			row.add_child(cast_btn)
			var pin_btn := Button.new()
			pin_btn.text = "★"
			var _sn := sp.spell_name
			pin_btn.pressed.connect(func() -> void:
				PlayerProgression.combat_prefs.defaults["magic"] = _sn
				_show_execution_magic(cast_tool)
			)
			row.add_child(pin_btn)
			_action_panel.add_child(row)


func _confirm_strike(pool: String) -> void:
	var bt: bool = get_brutal_trade()
	disable_actions()
	strike_confirmed.emit(pool, bt, _current_weapon_item)


func _on_massive_choice(use_charge: bool) -> void:
	_massive_overlay.visible = false
	wound_degrade_chosen.emit(use_charge)


func _on_burnout_choice(use_charge: bool) -> void:
	_burnout_overlay.visible = false
	burnout_prevent_chosen.emit(use_charge)


func _toggle_atk_mode() -> void:
	var prefs := PlayerProgression.combat_prefs
	prefs.atk_mode = "auto" if prefs.atk_mode == "manual" else "manual"
	_atk_mode_btn.text = "ATK: %s" % prefs.atk_mode.capitalize()


func _toggle_def_mode() -> void:
	var prefs := PlayerProgression.combat_prefs
	prefs.def_mode = "observe" if prefs.def_mode == "auto" else "auto"
	_def_mode_btn.text = "DEF: %s" % prefs.def_mode.capitalize()


## Creates a CheckButton whose state persists across rounds via combat_prefs.defaults[key].
func _make_persistent_toggle(label: String, key: String, default_val: bool = false) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = label
	btn.button_pressed = PlayerProgression.combat_prefs.defaults.get(key, default_val)
	btn.toggled.connect(func(on: bool) -> void:
		PlayerProgression.combat_prefs.defaults[key] = on
	)
	return btn
