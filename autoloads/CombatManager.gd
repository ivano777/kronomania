# CombatManager — combat state machine for 1vN duels.
#
# Flow per round:
#   _begin_round  →  (player presses Strike / Cantrip / Spell)  →  _resolve_round_*
#   _resolve_round_* rolls the player attack once, then resolves three phases:
#     Phase 1 — enemies the player is SLOW against attack first (per-enemy VT check).
#     Phase 2 — player attacks the chosen target.
#     Phase 3 — enemies the player is FAST against attack last.
#   After each phase, defeat conditions are checked and the loop restarts.
#
# All game-state signals are emitted here; UI nodes listen and update.
extends Node


# ── Constants ─────────────────────────────────────────────────────────────────

## Canonical pool names used as keys throughout the combat system.
const POOL_NAMES: Array = ["stance", "resolve", "stamina"]

## Fervor escalation track — die face values in order.
const FERVOR_TRACK: Array[int] = [4, 6, 8, 10]


# ── Signals ───────────────────────────────────────────────────────────────────

## A line ready to display in the combat log.
signal log_message(text: String)

## Emitted at the start of each new round.
signal round_started(round_num: int)

## Emitted whenever the active phase changes (for the phase label).
signal phase_changed(phase_name: String)

## Emitted after wounds are applied.
## is_player: true = player was hit; false = enemy was hit.
## enemy_index: index into the enemy array (-1 when is_player is true).
signal wounds_changed(is_player: bool, enemy_index: int, current: int, max_wounds: int)

## Emitted after a defender's guard pool changes (roll, consumption, or reset).
## is_player: true = player's guard; false = enemy's guard.
## enemy_index: index into the enemy array (-1 when is_player is true).
## pool: "stance" | "resolve" | "stamina"
signal guard_changed(is_player: bool, enemy_index: int, pool: String, guard_value: int)

## Emitted once combat ends.
signal combat_ended(winner_name: String)

## Emitted when the player must choose their action.
signal player_action_required()

## Emitted before player_action_required to inform the UI which magic actions are available.
signal player_magic_available(can_cantrip: bool, can_cast_spell: bool)

## Emitted before player_action_required listing available intent keys ("attack", "magic", "item").
signal player_intents_available(intents: Array[String])

## Emitted whenever the player's Fervor state changes (initial emit at combat start).
signal fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool)

## Emitted when a Massive Wound against the player can be degraded (charges_left > 0).
signal player_massive_incoming(charges_left: int)
## Internal coroutine gate: resolved when the player decides whether to spend a charge.
signal _massive_decision_gate(use_charge: bool)

## Emitted when an enemy attack is about to resolve; DEF Observe mode only.
signal player_defense_incoming(attacker_name: String, attack_total: int, target_pool: String)
## Internal coroutine gate: resolved when the player acknowledges the incoming defense.
signal _defense_acknowledged()

## Emitted when the player must choose which item to use for their defense roll.
## options: Array of { item_name: String, mod: ActionModifier } Dictionaries.
signal player_defense_item_choice(options: Array)
## Internal coroutine gate: resolved when the player selects a defense item.
signal _defense_item_chosen(mod: ActionModifier)

## Emitted when an imminent Burnout can be cancelled by a Lucidity L2 charge.
signal player_burnout_imminent(charges_left: int)
## Internal gate awaited by _try_prevent_burnout; resolved when player decides.
signal _burnout_decision_gate(use_charge: bool)


# ── Runtime state ─────────────────────────────────────────────────────────────

class CombatantState:
	var data: CombatantData
	var current_wounds: int = 0
	var max_wounds: int     = 3
	var is_defeated: bool   = false
	var weapon_override: EquipmentData = null      # main-hand override; null = use data.equipped_weapon
	var off_hand_override: EquipmentData = null    # off-hand override; null = no off-hand equipped
	var node_levels: Dictionary = {}           # NodeData → int; runtime copy from PlayerProgression for player
	var tier_override: int = 0                 # when > 0, overrides data.tier (used for player Tier from Constellation)
	# Per-pool guard state (Stance / Resolve / Stamina).
	var stance_guard: int   = 0
	var resolve_guard: int  = 0
	var stamina_guard: int  = 0
	var stance_rolled: bool  = false
	var resolve_rolled: bool = false
	var stamina_rolled: bool = false
	# Magic state — player only; resets to base each combat.
	var fervor_size: int    = 4     # current Fervor die face (4/6/8/10); starts at d4
	var is_burned_out: bool = false # blocks true spells when true
	var has_minor_studies: bool = false  # derived from unlocked_nodes in start_combat()
	var has_spellcasting: bool  = false  # derived from unlocked_nodes in start_combat()
	var known_spells: Array   = []  # Array[SpellData] — non-cantrip spells, player only
	var known_cantrips: Array = []  # Array[SpellData] — cantrip spells, player only
	var space_domination_active: bool = false  # Melee L2: Advantage on first Stamina guard roll each combat
	var item_action_charges: Dictionary = {}   # action_key → remaining uses (from ActionModifier.uses_per_rest)
	var active_statuses: Array[CombatStatus] = []
	var interrupt_handlers: Array[InterruptHandler] = []
	## Single-use debuffs queued by SpellOutcomeEffect; consumed on the next guard roll
	## for the matching pool. { "<pool>": { "flat": int, "keep": int } }
	var pending_guard_debuffs: Dictionary = {}

	func init(d: CombatantData) -> void:
		data = d
		current_wounds = 0
		max_wounds = d.max_wounds + (d.equipped_weapon.max_wounds_bonus if d.equipped_weapon else 0)
		is_defeated = false
		node_levels.clear()
		for n in d.starting_nodes:
			if n is NodeData:
				node_levels[n as NodeData] = 1
		fervor_size = 4
		is_burned_out = false
		has_minor_studies = false
		has_spellcasting = false
		space_domination_active = false
		active_statuses = []
		interrupt_handlers = []
		pending_guard_debuffs = {}
		reset_guard()

	func reset_guard() -> void:
		stance_guard = 0;  resolve_guard = 0;  stamina_guard = 0
		stance_rolled = false; resolve_rolled = false; stamina_rolled = false

	func get_guard(pool: String) -> int:
		match pool:
			"stance":  return stance_guard
			"resolve": return resolve_guard
			"stamina": return stamina_guard
		return 0

	func set_guard_val(pool: String, value: int) -> void:
		match pool:
			"stance":  stance_guard  = value
			"resolve": resolve_guard = value
			"stamina": stamina_guard = value

	func is_pool_rolled(pool: String) -> bool:
		match pool:
			"stance":  return stance_rolled
			"resolve": return resolve_rolled
			"stamina": return stamina_rolled
		return false

	func set_pool_rolled(pool: String, value: bool) -> void:
		match pool:
			"stance":  stance_rolled  = value
			"resolve": resolve_rolled = value
			"stamina": stamina_rolled = value


var _player: CombatantState
var _enemies: Array  # Array[CombatantState]
var _round:  int = 0
var _debug_immortal: bool = false
var _debug_lethal: bool = false

## True only while awaiting the player's action input.
var _waiting_for_player: bool = false
## Weapon the player explicitly chose this round; null = use default main-hand resolution.
var _player_strike_weapon: EquipmentData = null
## Round-scoped: which defense pools the player has breached this round (any attack/spell).
## Reset each _begin_round(). Used by SpellOutcomeEffect conditions.
var _current_round_player_breaches: Dictionary = {
	"stance": false, "resolve": false, "stamina": false
}


# ── Public API ────────────────────────────────────────────────────────────────

## Call from BattleScene._ready() to initialise and begin combat.
## enemies_data: Array[CombatantData] — one entry per enemy (parallel if >1).
func start_combat(player_data: CombatantData, enemies_data: Array) -> void:
	_player = CombatantState.new()
	_player.init(player_data)
	if PlayerProgression.main_hand != null:
		var old_fort: int = player_data.equipped_weapon.max_wounds_bonus if player_data.equipped_weapon else 0
		_player.max_wounds += PlayerProgression.main_hand.max_wounds_bonus - old_fort
		_player.weapon_override = PlayerProgression.main_hand
	if PlayerProgression.off_hand != null:
		_player.off_hand_override = PlayerProgression.off_hand
	_player.node_levels = PlayerProgression.node_levels.duplicate()
	_player.tier_override = PlayerProgression.get_tier()
	_player.max_wounds += _tier_wound_bonus(_player.tier_override)
	_player.max_wounds += _wounds_node_bonus(_player)
	var meat_grinder_charges := _meat_grinder_charges(_player)
	if meat_grinder_charges > 0:
		var mftg_handler := InterruptHandler.new()
		mftg_handler.handler_id = "meat_for_the_grinder"
		mftg_handler.trigger = "on_massive_wound"
		mftg_handler.target = "self"
		mftg_handler.charges = meat_grinder_charges
		mftg_handler.priority = 20
		mftg_handler.source_node_id = "dom_meat_grinder"
		_register_interrupt(_player, mftg_handler)
	# Lucidity L2: reactive anti-Burnout interrupt (1 charge per combat).
	if PlayerProgression.get_node_level_by_id("lucidity") >= 2:
		var lucidity_handler := InterruptHandler.new()
		lucidity_handler.handler_id = "lucidity_prevent_burnout"
		lucidity_handler.trigger = "on_burnout"
		lucidity_handler.target = "self"
		lucidity_handler.charges = 1
		lucidity_handler.priority = 10
		lucidity_handler.source_node_id = "lucidity"
		_register_interrupt(_player, lucidity_handler)
	_player.space_domination_active = _has_effect_type(_player, "space_domination")
	_player.current_wounds = mini(PlayerProgression.saved_wounds, _player.max_wounds)
	wounds_changed.emit(true, -1, _player.current_wounds, _player.max_wounds)
	_player.has_minor_studies = _has_effect_type(_player, "minor_studies")
	_player.has_spellcasting  = _has_effect_type(_player, "spellcasting")
	_player.fervor_size = PlayerProgression.saved_fervor_size
	_player.is_burned_out = PlayerProgression.saved_is_burned_out
	_player.known_spells   = PlayerProgression.get_known_spells()
	_player.known_cantrips = PlayerProgression.get_known_cantrips()

	_enemies.clear()
	for i in enemies_data.size():
		var ed: CombatantData = enemies_data[i] as CombatantData
		var state := CombatantState.new()
		state.init(ed)
		_enemies.append(state)
		wounds_changed.emit(false, i, 0, state.max_wounds)

	# Initialise per-combat item charges for all combatants.
	for state in ([_player] as Array) + _enemies:
		for mod in _get_all_action_modifiers(state):
			if mod.rest_type == "combat" and mod.uses_per_rest > 0:
				state.item_action_charges[mod.action_key] = mod.uses_per_rest

	_round = 0
	_waiting_for_player = false

	log_message.emit("[b]Combat begins![/b]")
	var player_line := "  %s: off d%d | Stance d%d / Resolve d%d / Stamina d%d" % [
		player_data.combatant_name,
		_stat_size(_player, "dominion"), _stat_size(_player, "negation"),
		_stat_size(_player, "ingenuity"), _stat_size(_player, "dominion"),
	]
	var enemy_lines := ""
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		enemy_lines += "\n  %s [VT %d]: off d%d | Stance d%d / Resolve d%d / Stamina d%d" % [
			e.data.combatant_name, e.data.velocity_threshold,
			_stat_size(e, "dominion"), _stat_size(e, "negation"),
			_stat_size(e, "ingenuity"), _stat_size(e, "dominion"),
		]
	log_message.emit(player_line + enemy_lines)

	# Emit initial Fervor state so HUD is initialised before round 1.
	fervor_changed.emit(true, _player.fervor_size, _stat_size(_player, "ingenuity"), _player.is_burned_out)

	_begin_round()


## Called by BattleScene when the player presses Strike.
## net_advantage  : positive = Advantage dice, negative = Disadvantage dice.
## target_pool    : which defense pool the attack pressures ("stance" | "resolve" | "stamina").
## brutal_trade   : if true, VT −5 and Flat +5 (requires dom_brutal L1).
## target_index   : which enemy to attack (index into _enemies array).
func player_chose_strike(net_advantage: int = 0, target_pool: String = "stance", brutal_trade: bool = false, target_index: int = 0, source_weapon: EquipmentData = null) -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
	_player_strike_weapon = source_weapon
	_resolve_round(net_advantage, target_pool, brutal_trade, target_index)


## Called by BattleScene when the player selects a cantrip spell.
## Ingenuity-based attack; no Fervor cost; available during Burnout.
func player_chose_cantrip(spell: SpellData, target_index: int = 0) -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
	_resolve_round_cantrip(spell, target_index)


## Called by BattleScene when the player selects a true spell.
## Ingenuity-based attack with a real Fervor die; blocked during Burnout.
func player_chose_spell(spell: SpellData, target_index: int = 0) -> void:
	if not _waiting_for_player:
		return
	if _player.is_burned_out:
		log_message.emit("[color=orange]Burnout! True spells are blocked — choose Strike or Cantrip.[/color]")
		_emit_player_intents()
		player_magic_available.emit(_player.known_cantrips.size() > 0, false)
		player_action_required.emit()
		return
	_waiting_for_player = false
	_resolve_round_spell(spell, target_index)


## Called by RoundHUD (via BattleScene) when the player resolves a Meat for the Grinder prompt.
func player_chose_degrade_wound(use_charge: bool) -> void:
	_massive_decision_gate.emit(use_charge)


## Called by RoundHUD (via BattleScene) when the player responds to the Lucidity L2 Burnout prompt.
func player_chose_prevent_burnout(use_charge: bool) -> void:
	_burnout_decision_gate.emit(use_charge)


## Called by RoundHUD when the player clicks OK on the DEF Observe overlay.
func player_acknowledged_defense() -> void:
	_defense_acknowledged.emit()


## Called by RoundHUD when the player selects a defense item from the choice panel.
func player_chose_defense_item(mod: ActionModifier) -> void:
	_defense_item_chosen.emit(mod)


## Player chose the Lucidity action: lower Fervor by 1 step and end the round.
func player_chose_lucidity() -> void:
	if not _waiting_for_player:
		return
	if not _can_use_lucidity():
		push_warning("player_chose_lucidity called when not usable")
		return
	_waiting_for_player = false
	log_message.emit("[color=cyan]Lucidity: you steady your mind and cool the Fervor.[/color]")
	await _escalate_fervor(_player, -1)
	await _end_of_round()
	if _all_enemies_defeated():
		return  # _end_combat already called inside _end_of_round (echo kill)
	_begin_round()


## Debug only — override Fervor state at runtime.
func debug_set_fervor(new_fervor_size: int, burned_out: bool) -> void:
	if _player:
		_player.fervor_size = new_fervor_size
		_player.is_burned_out = burned_out
		fervor_changed.emit(true, _player.fervor_size, _stat_size(_player, "ingenuity"), burned_out)


## Debug only — restore player wounds to 0 mid-combat.
func debug_refill_hp() -> void:
	if _player:
		_player.current_wounds = 0
		wounds_changed.emit(true, -1, 0, _player.max_wounds)


## Debug only — toggle player immortality (wounds can't trigger defeat).
func debug_set_immortal(enabled: bool) -> void:
	_debug_immortal = enabled


## Debug only — toggle lethal attacks (player breaches instantly kill enemies).
func debug_set_lethal(enabled: bool) -> void:
	_debug_lethal = enabled


# ── Private — round flow ──────────────────────────────────────────────────────

func _emit_player_intents() -> void:
	var intents: Array[String] = ["attack"]
	if _player.has_minor_studies or _player.has_spellcasting:
		intents.append("magic")
	if _can_use_lucidity():
		intents.append("lucidity")
	intents.append("item")
	player_intents_available.emit(intents)


func _can_use_lucidity() -> bool:
	# Available only if Lucidity L1 is purchased AND Fervor is above the minimum.
	# Lowering from d4 is a no-op — hide the intent to prevent wasting a turn.
	if not _has_effect_type(_player, "lucidity_lower_fervor"):
		return false
	return _player.fervor_size > FERVOR_TRACK[0]


func _begin_round() -> void:
	_round += 1
	_current_round_player_breaches = {"stance": false, "resolve": false, "stamina": false}

	# Start-of-round status hooks (guards are already 0 from _end_of_round).
	_process_statuses_hook("start_of_round", _player)
	for enemy_state in _enemies:
		_process_statuses_hook("start_of_round", enemy_state)

	_tick_statuses(_player)
	for enemy_state in _enemies:
		_tick_statuses(enemy_state)

	round_started.emit(_round)
	log_message.emit("")
	log_message.emit("[b]═══ Round %d ═══[/b]" % _round)
	phase_changed.emit("Choose your action")

	_waiting_for_player = true
	_emit_player_intents()
	player_magic_available.emit(
		_player.known_cantrips.size() > 0,
		_player.known_spells.size() > 0 and not _player.is_burned_out
	)
	player_action_required.emit()


## Called by BattleScene when the player clicks the Attack intent in ATK Auto mode.
## Skips the tool and execution panels: resolves weapon/action from saved defaults or heuristic.
func player_auto_execute_attack(target_index: int = 0, net_advantage: int = 0) -> void:
	if not _waiting_for_player:
		return
	var defaults: Dictionary = PlayerProgression.combat_prefs.defaults
	var weapon_name: String = defaults.get("attack_weapon", "")
	var action_key: String  = defaults.get("attack_action", "")
	if weapon_name != "" and action_key != "":
		# Use weapon_override only (not data.equipped_weapon) so "bare_hands" matches correctly.
		var main_w: EquipmentData = _player.weapon_override
		var main_name: String     = main_w.item_name if main_w else "bare_hands"
		var off_w: EquipmentData  = _player.off_hand_override
		var off_name: String      = off_w.item_name if off_w else ""

		var found_match := false
		var matched_w: EquipmentData = null
		if weapon_name == main_name:
			found_match = true
			matched_w   = main_w        # null when bare hands — intentional
		elif off_w != null and weapon_name == off_name:
			found_match = true
			matched_w   = off_w

		if found_match:
			var mod: ActionModifier = null
			if matched_w != null:
				for m in matched_w.action_modifiers:
					if m.action_key == action_key:
						mod = m
						break
			if mod == null:
				mod = _player.data.get_bare_hands_modifier(action_key)
			if mod != null:
				var brutal := bool(defaults.get("brutal_trade", false)) and \
						(PlayerProgression.get_node_level_by_id("dom_brutal") >= 1)
				var tp    := mod.target_pool if mod.target_pool != "" else "stance"
				var label := mod.action_name if mod.action_name != "" else action_key.capitalize()
				log_message.emit("[color=gray][Auto] %s → %s (default)[/color]" % [label, tp.capitalize()])
				player_chose_strike(net_advantage, tp, brutal, target_index, matched_w)
				return
	var best := _auto_best_action()
	if not best.is_empty():
		var tp    := best["target_pool"] as String
		var score := best["score"] as float
		log_message.emit("[color=gray][Auto-Best] Strike → %s (score: %.1f)[/color]" % [tp.capitalize(), score])
		player_chose_strike(net_advantage, tp, false, target_index)


func _auto_best_action() -> Dictionary:
	var mod := _get_action_modifier(_player, "strike")
	if mod == null:
		return {}
	var tier := _effective_tier(_player, mod)
	var die_size := _stat_size(_player, "dominion")
	var flat := _attack_flat(_player)
	var score: float = tier * (1.0 + die_size) / 2.0 + flat
	var tp: String = mod.target_pool if mod.target_pool != "" else "stance"
	return {"target_pool": tp, "score": score}


# Coroutine: physical Strike — resolves one full round then loops back.
func _resolve_round(net_advantage: int = 0, target_pool: String = "stance", brutal_trade: bool = false, target_index: int = 0) -> void:
	phase_changed.emit("Resolving…")
	var target: CombatantState = _enemies[target_index]
	log_message.emit("Both combatants declare Strike. Targeting: %s." % target.data.combatant_name)

	if brutal_trade:
		log_message.emit("  [color=yellow]Brutal Trade: VT −5, Flat +5.[/color]")

	# ── Roll player attack pool ────────────────────────────────────────────
	var chosen_weapon := _player_strike_weapon
	_player_strike_weapon = null
	var _strike_mod: ActionModifier
	if chosen_weapon != null:
		for m in chosen_weapon.action_modifiers:
			if m.action_key == "strike":
				_strike_mod = m
				break
		if _strike_mod == null:
			_strike_mod = _player.data.get_bare_hands_modifier("strike")
	else:
		_strike_mod = _get_action_modifier(_player, "strike")
	var keep_grade := _physical_keep_grade(_player) + _node_weapon_bonus_sum(_player, "weapon_keep") + _strike_mod.keep_bonus
	var brutal_flat := 5 if brutal_trade else 0

	var earthshatter_size := 0
	if target_pool == "stance" and _node_effect_max(_player, "earthshatter") > 0:
		earthshatter_size = _stat_size(_player, "dominion")
		log_message.emit("  [color=cyan]Earthshatter![/color] Post-keep Dominion d%d added." % earthshatter_size)

	var p_atk := RollEngine.resolve(
		_effective_tier(_player, _strike_mod), _stat_size(_player, "dominion"), keep_grade,
		_attack_flat(_player) + brutal_flat,
		net_advantage + _pool_bonus(_player),
		0, 0, 0, earthshatter_size
	)
	var _atk_weapon_name := chosen_weapon.item_name if chosen_weapon else _attacker_weapon_name(_player)
	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk, _atk_weapon_name))
	if (p_atk.post_keep_bonus_roll as int) > 0:
		log_message.emit("  [color=cyan]Earthshatter roll: %d[/color]" % (p_atk.post_keep_bonus_roll as int))

	var p_total: int = p_atk.total as int
	var target_vt: int = target.data.velocity_threshold - (5 if brutal_trade else 0)
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_total, target_vt,
		RollEngine.is_fast(p_total, target_vt)))

	# ── Phase 1: Slow enemies attack first ────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		var e_vt: int = e.data.velocity_threshold - (5 if brutal_trade and i == target_index else 0)
		if not RollEngine.is_fast(p_total, e_vt):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk, _attacker_weapon_name(e)))
			var e_pool := target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	if not target.is_defeated:
		await _resolve_attack(true, target_index, p_atk, target_pool)

	# Phase 2.1 — post player-attack: detonate any primed mind-bomb if Stance was breached.
	if not target.is_defeated:
		await _check_mind_detonation(target, target_index)

	if _all_enemies_defeated():
		_end_combat()
		return

	# ── Phase 3: Fast enemies attack last ─────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		var e_vt: int = e.data.velocity_threshold - (5 if brutal_trade and i == target_index else 0)
		if RollEngine.is_fast(p_total, e_vt):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk, _attacker_weapon_name(e)))
			var e_pool := target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Next round ─────────────────────────────────────────────────────────
	await _end_of_round()
	if _all_enemies_defeated():
		return  # _end_combat already called inside _end_of_round (echo kill)
	_begin_round()


# Coroutine: Cantrip — Ingenuity-based attack, no Fervor die, available during Burnout.
func _resolve_round_cantrip(spell: SpellData, target_index: int = 0) -> void:
	phase_changed.emit("Resolving…")
	var target: CombatantState = _enemies[target_index]
	log_message.emit("%s channels %s (Ingenuity d%d, no Fervor). Targeting: %s." % [
		_player.data.combatant_name, spell.spell_name, _stat_size(_player, "ingenuity"),
		target.data.combatant_name
	])

	var p_atk := RollEngine.resolve(
		_effective_tier(_player, _get_action_modifier(_player, "strike")), _stat_size(_player, "ingenuity"), _training_keep_grade(_player),
		spell.flat_bonus, _pool_bonus(_player)
	)
	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk) + " [cantrip]")

	var p_total: int = p_atk.total as int
	var target_vt: int = target.data.velocity_threshold
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_total, target_vt, RollEngine.is_fast(p_total, target_vt)))

	# ── Phase 1: Slow enemies attack first ────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		if not RollEngine.is_fast(p_total, e.data.velocity_threshold):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	var _pool_breached_before_c := _current_round_player_breaches.get(spell.target_pool, false) as bool
	if not target.is_defeated:
		await _resolve_attack(true, target_index, p_atk, spell.target_pool)
	# "breach" = this spell caused the round's FIRST breach on its target_pool.
	# A spell that breaches an already-breached pool sets this to false.
	# Group B mechanics that need pure per-spell breach detection should read
	# _resolve_attack's local breach flag instead — deferred to Group B.
	var _spell_first_breach_this_round_c := (not _pool_breached_before_c) and \
		(_current_round_player_breaches.get(spell.target_pool, false) as bool)
	if not target.is_defeated:
		_apply_spell_outcome_effects(spell, _player, target, {
			"hit": _spell_first_breach_this_round_c,
			"breach": _spell_first_breach_this_round_c,
			"attack_total": p_atk.total as int,
			"target_pool": spell.target_pool,
			"round_breaches": _current_round_player_breaches.duplicate()
		})

	# Phase 2.1 — post player-attack: detonate any primed mind-bomb if Stance was breached.
	if not target.is_defeated:
		await _check_mind_detonation(target, target_index)

	if _all_enemies_defeated():
		_end_combat()
		return

	# ── Phase 3: Fast enemies attack last ─────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		if RollEngine.is_fast(p_total, e.data.velocity_threshold):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	await _end_of_round()
	if _all_enemies_defeated():
		return  # _end_combat already called inside _end_of_round (echo kill)
	_begin_round()


# Coroutine: True Spell — Ingenuity (+ optional aspect dice) + real Fervor die.
# Escalation = count of Ingenuity-tagged dice that maxed + 1 if Fervor die maxed.
func _resolve_round_spell(spell: SpellData, target_index: int = 0) -> void:
	phase_changed.emit("Resolving…")
	var target: CombatantState = _enemies[target_index]

	var aspect_stat_size: int = 0
	if spell.aspect_stat == "dominion":
		aspect_stat_size = _stat_size(_player, "dominion")
	elif spell.aspect_stat == "negation":
		aspect_stat_size = _stat_size(_player, "negation")

	var aspect_label := ""
	if spell.aspect_dice > 0 and spell.aspect_stat != "":
		aspect_label = " [%s d%d × %d + Ingenuity d%d]" % [
			spell.aspect_stat.capitalize(), aspect_stat_size,
			spell.aspect_dice, _stat_size(_player, "ingenuity")
		]
	else:
		aspect_label = " [Ingenuity d%d]" % _stat_size(_player, "ingenuity")
	log_message.emit("%s casts %s%s + Fervor d%d. Targeting: %s." % [
		_player.data.combatant_name, spell.spell_name, aspect_label, _player.fervor_size,
		target.data.combatant_name
	])

	# Mind Detonation placement scratch: 1 Ingenuity die, no SpellBonusEffect bonuses.
	# Bonuses (+pool, +keep) are reserved for the explosion built in _detonate_mind_bomb.
	# All other spells: collect school bonuses via _collect_spell_bonuses and apply to roll.
	var p_atk: Dictionary
	if spell.spell_name == "Mind Detonation":
		p_atk = RollEngine.resolve(
			1,
			_stat_size(_player, "ingenuity"),
			_training_keep_grade(_player),
			0, _pool_bonus(_player), _player.fervor_size, 0, 0
		)
	else:
		var bonuses := _collect_spell_bonuses(spell)
		var spell_pool_bonus: int = bonuses["pool"] as int
		var spell_keep_bonus: int = bonuses["keep"] as int
		var spell_flat_bonus: int = bonuses["flat"] as int
		if spell_pool_bonus > 0 or spell_keep_bonus > 0 or spell_flat_bonus > 0:
			var parts: Array = []
			if spell_pool_bonus > 0:
				parts.append("+%d pool" % spell_pool_bonus)
			if spell_keep_bonus > 0:
				parts.append("+%d keep" % spell_keep_bonus)
			if spell_flat_bonus > 0:
				parts.append("+%d flat" % spell_flat_bonus)
			log_message.emit("  [color=yellow]School bonus: %s[/color]" % ", ".join(parts))
		p_atk = RollEngine.resolve(
			_effective_tier(_player, _get_action_modifier(_player, "strike")) + spell_pool_bonus,
			_stat_size(_player, "ingenuity"),
			_training_keep_grade(_player) + spell_keep_bonus,
			spell.flat_bonus + spell_flat_bonus, _pool_bonus(_player), _player.fervor_size,
			aspect_stat_size, spell.aspect_dice
		)
	log_message.emit(_fmt_spell_attack(_player.data.combatant_name, p_atk))

	var p_total: int = p_atk.total as int
	var target_vt: int = target.data.velocity_threshold
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_total, target_vt, RollEngine.is_fast(p_total, target_vt)))

	# ── Phase 1: Slow enemies attack first ────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		if not RollEngine.is_fast(p_total, e.data.velocity_threshold):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	var _pool_breached_before := _current_round_player_breaches.get(spell.target_pool, false) as bool
	if not target.is_defeated:
		if spell.spell_name == "Mind Rend":
			await _cast_mind_rend(target, target_index, p_atk)
		elif spell.spell_name == "Time Lock":
			await _cast_time_lock(target, target_index, p_atk)
		else:
			await _resolve_attack(true, target_index, p_atk, spell.target_pool)
	# "breach" = this spell caused the round's FIRST breach on its target_pool.
	# A spell that breaches an already-breached pool sets this to false.
	# Group B mechanics that need pure per-spell breach detection should read
	# _resolve_attack's local breach flag instead — deferred to Group B.
	var _spell_first_breach_this_round := (not _pool_breached_before) and \
		(_current_round_player_breaches.get(spell.target_pool, false) as bool)
	if not target.is_defeated:
		_apply_spell_outcome_effects(spell, _player, target, {
			"hit": _spell_first_breach_this_round,
			"breach": _spell_first_breach_this_round,
			"attack_total": p_atk.total as int,
			"target_pool": spell.target_pool,
			"round_breaches": _current_round_player_breaches.duplicate()
		})

	# Mind Detonation: freeze params into the primed status right after the placement scratch.
	if spell.spell_name == "Mind Detonation" and not target.is_defeated:
		var bomb := CombatStatus.new()
		bomb.status_id = "mind_detonation_primed"
		bomb.duration_rounds = 3
		bomb.source_node_id = "mind_detonation"
		bomb.stat_overrides = {
			"fervor_at_prime": _player.fervor_size,
			"md_level": PlayerProgression.get_node_level_by_id("mind_detonation"),
		}
		_add_status(target, bomb)
		log_message.emit("[color=purple]A psychic charge is set in %s's mind...[/color]" % target.data.combatant_name)

	# Phase 2.1 — post player-attack: detonate any primed mind-bomb if Stance was breached.
	if not target.is_defeated:
		await _check_mind_detonation(target, target_index)

	# Echoing Mind: arm echo if the spell has "echo" tag and target is still alive.
	# "current_kept_dice" starts at (cast_kept − 1); if that is 0, no echo is created.
	# New cast overwrites any existing echo train (latest cast wins — known simplification).
	if "echo" in spell.tags and PlayerProgression.get_node_level_by_id("echoing_mind") > 0 and not target.is_defeated:
		var _echo_bonuses := _collect_spell_bonuses(spell)
		var _cast_kept_dice: int = _training_keep_grade(_player) + (_echo_bonuses["keep"] as int)
		var _initial_echo_kept: int = _cast_kept_dice - 1
		if _initial_echo_kept >= 1:
			if _has_status(_player, "echoing_spell"):
				_remove_status(_player, "echoing_spell")
				log_message.emit("[color=cyan]The previous echo is cut off as a new spell begins to resound.[/color]")
			var echo_status := CombatStatus.new()
			echo_status.status_id = "echoing_spell"
			echo_status.duration_rounds = 20  # safety bound; real termination via current_kept_dice < 1
			echo_status.source_node_id = "echoing_mind"
			echo_status.stat_overrides = {
				"spell_path": spell.resource_path,
				"target_index": target_index,
				"frozen_fervor": _player.fervor_size,
				"current_kept_dice": _initial_echo_kept,
				"em_level": PlayerProgression.get_node_level_by_id("echoing_mind"),
			}
			_add_status(_player, echo_status)
			log_message.emit("[color=cyan]The spell begins to echo — it will resound for %d more turn(s).[/color]" % _initial_echo_kept)

	if _all_enemies_defeated():
		_end_combat()
		return

	# ── Phase 3: Fast enemies attack last ─────────────────────────────────
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		if RollEngine.is_fast(p_total, e.data.velocity_threshold):
			var e_atk := RollEngine.resolve(
				_effective_tier(e, _get_action_modifier(e, "strike")), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# Post-resolution: Fervor escalation (rules: magic/fervor.md).
	# Steps = count of Ingenuity-tagged dice that rolled max + 1 if Fervor die maxed.
	var fervor_maxed: bool = p_atk.fervor_maxed as bool
	var escalation_steps: int = (p_atk.primary_dice_maxed_count as int) + (1 if fervor_maxed else 0)
	if escalation_steps > 0:
		await _escalate_fervor(_player, escalation_steps)

	await _end_of_round()
	if _all_enemies_defeated():
		return  # _end_combat already called inside _end_of_round (echo kill)
	_begin_round()


# Resolves a single attack against the specified defense pool.
# attacker_is_player : who is swinging
# enemy_index        : index of the enemy involved (attacker if !attacker_is_player, defender if attacker_is_player)
# attack_result      : Dictionary from RollEngine.resolve()
# target_pool        : which pool the defender uses ("stance" | "resolve" | "stamina")
func _resolve_attack(attacker_is_player: bool, enemy_index: int, attack_result: Dictionary, target_pool: String = "stance") -> void:
	var attacker: CombatantState = _player if attacker_is_player else _enemies[enemy_index]
	var defender: CombatantState = _enemies[enemy_index] if attacker_is_player else _player
	var defender_is_player := not attacker_is_player
	var defender_ei := enemy_index if attacker_is_player else -1
	var pool_label := target_pool.capitalize()
	var defensive_size: int = _get_pool_size(defender, target_pool)

	log_message.emit(
		"  [b]%s → %s[/b]  [%s]  (attack total: %d)" % [
			attacker.data.combatant_name,
			defender.data.combatant_name,
			pool_label,
			attack_result.total as int,
		]
	)

	# Each pool may only be rolled once per round (rules: defense-and-guard.md).
	# If already rolled, reuse the existing Guard value.
	var _pool_fresh := not defender.is_pool_rolled(target_pool)
	if not attacker_is_player and PlayerProgression.combat_prefs.def_mode == "observe" and _pool_fresh:
		player_defense_incoming.emit(attacker.data.combatant_name, attack_result.total as int, target_pool)
		await _defense_acknowledged
	if _pool_fresh:
		# Resolve which item the defender uses — player gets a choice when both slots have "defend".
		var defend_entry: Dictionary
		if defender_is_player:
			defend_entry = await _get_player_defense_modifier()
		else:
			var _dm := _get_action_modifier(defender, "defend")
			var _ew := defender.weapon_override if defender.weapon_override else defender.data.equipped_weapon
			defend_entry = {"item_name": _ew.item_name if _ew else "Bare Hands", "mod": _dm}
		var defend_mod: ActionModifier = defend_entry["mod"] as ActionModifier
		var weapon_name: String = defend_entry["item_name"]
		var cap_str := "uncapped" if defend_mod.tier_cap == 0 else "cap %d" % defend_mod.tier_cap
		var base_tier := defender.tier_override if defender.tier_override > 0 else defender.data.tier
		log_message.emit("  %s defends with [i]%s[/i] (%s, Tier %d → %d dice)" % [
			defender.data.combatant_name, weapon_name, cap_str,
			base_tier, _effective_tier(defender, defend_mod)
		])
		var sd_adv := 0
		if defender_is_player and target_pool == "stamina" and _player.space_domination_active:
			sd_adv = 1
			_player.space_domination_active = false
			log_message.emit("  [color=cyan]Space Domination: Advantage on Stamina guard![/color]")
		# Consume any pending outcome debuffs for this pool (single-use, Group A4).
		var flat_debuff := 0
		var keep_debuff := 0
		var _pending_debuff = defender.pending_guard_debuffs.get(target_pool, null)
		if _pending_debuff != null:
			flat_debuff = (_pending_debuff as Dictionary).get("flat", 0) as int
			keep_debuff = (_pending_debuff as Dictionary).get("keep", 0) as int
			defender.pending_guard_debuffs.erase(target_pool)
			if flat_debuff != 0 or keep_debuff != 0:
				log_message.emit("  [color=purple][Outcome debuff] flat %+d, keep grade %+d on %s %s guard.[/color]" % [
					flat_debuff, keep_debuff, defender.data.combatant_name, pool_label
				])
		var def_result := RollEngine.resolve(
				_effective_tier(defender, defend_mod), defensive_size,
				maxi(1, _defense_keep_grade(defender, target_pool) + keep_debuff), defend_mod.flat_bonus,
				sd_adv
			)
		var guard_val: int = (def_result.total as int) + flat_debuff
		defender.set_guard_val(target_pool, guard_val)
		defender.set_pool_rolled(target_pool, true)
		guard_changed.emit(defender_is_player, defender_ei, target_pool, guard_val)
		log_message.emit(_fmt_defense(defender.data.combatant_name, def_result, pool_label))
	else:
		var existing: int = defender.get_guard(target_pool)
		log_message.emit(
			"  %s %s already active — Guard [b]%d[/b] absorbs pressure." % [
				defender.data.combatant_name, pool_label, existing
			]
		)

	# Breach check: attack_total >= guard (guard reaches 0 or below).
	var current_guard: int = defender.get_guard(target_pool)
	var force_breach := _debug_lethal and attacker_is_player and not defender_is_player
	var did_breach := false
	if (attack_result.total as int) >= current_guard or force_breach:
		did_breach = true
		_process_statuses_hook("on_breach", defender, {
			"pool": target_pool,
			"attacker": attacker
		})
		if attacker_is_player:
			_current_round_player_breaches[target_pool] = true
		var massive := RollEngine.is_massive(
			attack_result.total as int, current_guard, defensive_size
		)
		var wounds_pending := 2 if massive else 1
		# Hex Mastery: player breach on a hexed enemy deals +1 wound.
		if attacker_is_player and not defender_is_player and _has_status(defender, "hex_marked"):
			wounds_pending += 1
			log_message.emit("  [color=purple]The hex flares — the wound cuts deeper (+1)![/color]")
		if massive and not attacker_is_player and defender_is_player:
			var interrupts := _find_interrupts(defender, "on_massive_wound")
			for handler in interrupts:
				var context := {
					"wounds_pending": wounds_pending,
					"attacker_state": attacker
				}
				var result: Dictionary = await _resolve_interrupt(handler, defender, context)
				if result["resolved"]:
					wounds_pending = result["wounds_modified"] as int
		var wounds := wounds_pending
		defender.current_wounds += wounds
		if _debug_lethal and attacker_is_player and not defender_is_player:
			defender.current_wounds = defender.max_wounds
		if _debug_immortal and defender_is_player and defender.current_wounds >= defender.max_wounds:
			defender.current_wounds = defender.max_wounds - 1

		if massive:
			log_message.emit(
				"  [color=orange][b]MASSIVE![/b][/color] Overflow %d > d%d. %s suffers [b]2 Wounds[/b]!" % [
					(attack_result.total as int) - current_guard,
					defensive_size,
					defender.data.combatant_name,
				]
			)
		else:
			log_message.emit(
				"  Guard broken! %s suffers [b]1 Wound[/b]. (%d/%d)" % [
					defender.data.combatant_name,
					defender.current_wounds,
					defender.max_wounds,
				]
			)

		wounds_changed.emit(defender_is_player, defender_ei, defender.current_wounds, defender.max_wounds)

		if defender.current_wounds >= defender.max_wounds:
			defender.is_defeated = true
			log_message.emit(
				"  [color=red][b]%s is DEFEATED![/b][/color]" % defender.data.combatant_name
			)
	else:
		var remaining: int = current_guard - (attack_result.total as int)
		defender.set_guard_val(target_pool, remaining)
		log_message.emit(
			"  Guard holds. %d absorbed, %d remaining." % [
				attack_result.total as int, remaining
			]
		)

	# Publish final guard value after consumption.
	guard_changed.emit(defender_is_player, defender_ei, target_pool, defender.get_guard(target_pool))

	# Chrono-Tinkering: armed→frozen transition fires after ANY player attack on this enemy.
	# Echoes and explosions also route through _resolve_attack with attacker_is_player=true — intended.
	# Time Lock's own Resolve attack uses _cast_time_lock (bypasses this path); status is armed
	# after that function returns, so the transition cannot self-trigger from the casting attack.
	if attacker_is_player and not defender_is_player and _has_status(defender, "time_locked"):
		var tl := _get_status(defender, "time_locked")
		if tl != null:
			var phase := tl.stat_overrides.get("phase", "") as String
			var post_val: int = 0 if did_breach else defender.get_guard(target_pool)
			if phase == "armed":
				var chrono_level: int = PlayerProgression.get_node_level_by_id("chrono_tinkering")
				tl.stat_overrides["phase"] = "frozen"
				tl.stat_overrides["locked_pool"] = target_pool
				tl.stat_overrides["skip_resets"] = chrono_level
				tl.stat_overrides["frozen_value"] = post_val
				log_message.emit("[color=cyan]Time frozen! %s's %s guard is locked at %d — it will not renew for %d round(s).[/color]" % [
					defender.data.combatant_name, target_pool, post_val, chrono_level
				])
			elif phase == "frozen" and (tl.stat_overrides.get("locked_pool", "") as String) == target_pool:
				tl.stat_overrides["frozen_value"] = post_val


func _end_combat() -> void:
	var winner: String
	if _player.is_defeated:
		winner = ""
		for e in _enemies:
			if not e.is_defeated:
				winner = e.data.combatant_name
				break
		if winner == "":
			winner = _enemies[0].data.combatant_name if _enemies.size() > 0 else "Enemy"
		log_message.emit("")
		log_message.emit("[color=red][b]DEFEAT — %s wins.[/b][/color]" % winner)
	else:
		winner = _player.data.combatant_name
		log_message.emit("")
		log_message.emit("[color=lime][b]VICTORY — %s wins![/b][/color]" % winner)

	PlayerProgression.saved_fervor_size = _player.fervor_size
	PlayerProgression.saved_is_burned_out = _player.is_burned_out
	PlayerProgression.saved_wounds = _player.current_wounds
	phase_changed.emit("Combat Over")
	combat_ended.emit(winner)


## Returns true when every enemy in this encounter has been defeated.
func _all_enemies_defeated() -> bool:
	for e in _enemies:
		if not e.is_defeated:
			return false
	return true


# ── Helpers ───────────────────────────────────────────────────────────────────

# --- Status system helpers (Group A) ---

func _add_status(state: CombatantState, status: CombatStatus) -> void:
	_remove_status(state, status.status_id)
	state.active_statuses.append(status)

func _remove_status(state: CombatantState, status_id: String) -> void:
	state.active_statuses = state.active_statuses.filter(
		func(s): return s.status_id != status_id
	)

func _has_status(state: CombatantState, status_id: String) -> bool:
	return state.active_statuses.any(
		func(s): return s.status_id == status_id
	)

func _get_status(state: CombatantState, status_id: String) -> CombatStatus:
	for s in state.active_statuses:
		if s.status_id == status_id:
			return s
	return null

func _tick_statuses(state: CombatantState) -> void:
	var expired: Array[CombatStatus] = []
	for s in state.active_statuses:
		if s.duration_rounds == -1:
			continue
		s.duration_rounds -= 1
		if s.duration_rounds <= 0:
			expired.append(s)
	for s in expired:
		state.active_statuses.erase(s)
		if s.status_id == "mind_detonation_primed":
			log_message.emit("[color=purple]The mind-bomb goes inert. Stance was never broken.[/color]")
		elif s.status_id == "hex_marked":
			log_message.emit("[color=purple]The hex fades from %s — the brand has run its course.[/color]" % state.data.combatant_name)
		elif s.status_id == "echoing_spell":
			log_message.emit("[color=red][debug] echoing_spell expired via duration_rounds — should have self-terminated. Investigate.[/color]")
		elif s.status_id == "time_locked":
			var ph := s.stat_overrides.get("phase", "") as String
			if ph == "armed":
				log_message.emit("[color=cyan]The armed Time Lock dissipates — the moment slips away, unfrozen.[/color]")
			# frozen expiry via duration_rounds is a safety net; real removal is in _end_of_round

# --- End status system helpers ---

# --- Interrupt system helpers (Group A3) ---

func _register_interrupt(state: CombatantState, handler: InterruptHandler) -> void:
	# No deduplication — two distinct handlers with the same trigger may coexist.
	state.interrupt_handlers.append(handler)


func _find_interrupts(state: CombatantState, trigger: String) -> Array[InterruptHandler]:
	# Returns all matching handlers that still have charges, sorted by priority ascending.
	var matches: Array[InterruptHandler] = []
	for h in state.interrupt_handlers:
		if h.trigger == trigger and (h.charges > 0 or h.charges == -1):
			matches.append(h)
	matches.sort_custom(func(a, b): return a.priority < b.priority)
	return matches


func _consume_interrupt_charge(handler: InterruptHandler) -> void:
	if handler.charges > 0:
		handler.charges -= 1


func _resolve_interrupt(
		handler: InterruptHandler,
		state: CombatantState,
		context: Dictionary
) -> Dictionary:
	## Dispatcher for interrupt handlers. Returns { "wounds_modified": int, "resolved": bool }.
	## resolved=false means the player declined and the original outcome stands.
	match handler.handler_id:
		"meat_for_the_grinder":
			return await _resolve_meat_for_the_grinder(handler, state, context)
		_:
			push_warning("Unknown interrupt handler_id: " + handler.handler_id)
			return { "wounds_modified": context["wounds_pending"], "resolved": false }


func _resolve_meat_for_the_grinder(
		handler: InterruptHandler,
		_state: CombatantState,
		_context: Dictionary
) -> Dictionary:
	## Migrated from the previous hardcoded path. Signal/await contract is identical to pre-A3.
	player_massive_incoming.emit(handler.charges)
	var use_charge: bool = await _massive_decision_gate
	if use_charge:
		_consume_interrupt_charge(handler)
		log_message.emit("  [color=lime]Meat for the Grinder! Massive Wound degraded to 1 Wound.[/color]")
		return { "wounds_modified": 1, "resolved": true }
	return { "wounds_modified": 2, "resolved": true }


## Lucidity L2 anti-Burnout interrupt. Returns true if Burnout was prevented.
## Separate from _resolve_interrupt (which is wounds-shaped, for _resolve_attack);
## this fires inside _escalate_fervor and concerns a bool, not wound counts.
## Only the player can have Lucidity; enemies never trigger this path.
func _try_prevent_burnout(state: CombatantState) -> bool:
	if state != _player:
		return false
	var handlers := _find_interrupts(state, "on_burnout")
	if handlers.is_empty():
		return false
	var handler := handlers[0]  # priority-sorted; only one anti-Burnout handler exists
	player_burnout_imminent.emit(handler.charges)
	var use_charge: bool = await _burnout_decision_gate
	if use_charge:
		_consume_interrupt_charge(handler)
		log_message.emit("  [color=cyan]Lucidity holds! You wrench your mind back from the brink — Burnout averted (Fervor stays at the edge).[/color]")
		return true
	return false

# --- End interrupt system helpers ---

# --- Spell outcome effect helpers (Group A4) ---

func _apply_spell_outcome_effects(
		spell: SpellData,
		caster_state: CombatantState,
		target_state: CombatantState,
		outcome: Dictionary
) -> void:
	## Collects SpellOutcomeEffect entries from all purchased node levels that match
	## the resolved spell, then filters by trigger and condition before dispatching.
	##
	## outcome contents:
	##   { "hit": bool, "breach": bool, "attack_total": int,
	##     "target_pool": String, "round_breaches": Dictionary }
	## round_breaches tracks which pools the player has breached this round across
	## all attacks (not just this spell).
	var effects: Array[SpellOutcomeEffect] = []
	for node in PlayerProgression.node_levels:
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var level := PlayerProgression.node_levels[node] as int
		for i in range(mini(level, nd.levels_data.size())):
			for effect in nd.levels_data[i].outcome_effects:
				if _spell_outcome_matches(effect, spell):
					effects.append(effect)

	for effect in effects:
		if not _spell_outcome_trigger_fires(effect, outcome):
			continue
		if not _spell_outcome_condition_holds(effect, caster_state, target_state, outcome):
			continue
		_dispatch_spell_outcome_effect(effect, caster_state, target_state, outcome)


func _spell_outcome_matches(effect: SpellOutcomeEffect, spell: SpellData) -> bool:
	if effect.spell_id == "":
		return true
	return effect.spell_id == spell.spell_name


func _spell_outcome_trigger_fires(effect: SpellOutcomeEffect, outcome: Dictionary) -> bool:
	match effect.trigger:
		"on_cast":
			return true
		"on_hit", "on_breach":
			return outcome.get("breach", false) as bool
		_:
			push_warning("Unknown SpellOutcomeEffect.trigger: " + effect.trigger)
			return false


func _spell_outcome_condition_holds(
		effect: SpellOutcomeEffect,
		caster_state: CombatantState,
		_target_state: CombatantState,
		outcome: Dictionary
) -> bool:
	if effect.condition == "":
		return true
	var round_breaches: Dictionary = outcome.get("round_breaches", {})
	match effect.condition:
		"if_stance_breached_this_round":
			return round_breaches.get("stance", false) as bool
		"if_resolve_breached_this_round":
			return round_breaches.get("resolve", false) as bool
		"if_stamina_breached_this_round":
			return round_breaches.get("stamina", false) as bool
		"if_fervor_at_cap":
			return caster_state.fervor_size >= _stat_size(caster_state, "ingenuity_size")
		_:
			push_warning("Unknown SpellOutcomeEffect.condition: " + effect.condition)
			return false


func _dispatch_spell_outcome_effect(
		effect: SpellOutcomeEffect,
		caster_state: CombatantState,
		target_state: CombatantState,
		_outcome: Dictionary
) -> void:
	var receiver: CombatantState = caster_state if effect.target == "self" else target_state
	match effect.effect_type:
		"debuff_flat":
			_add_pending_guard_debuff(receiver, effect.target_pool, "flat", effect.value)
		"debuff_keep":
			_add_pending_guard_debuff(receiver, effect.target_pool, "keep", effect.value)
		"apply_status":
			if effect.status_to_apply != null:
				# Duplicate so each application is an independent instance.
				var st: CombatStatus = effect.status_to_apply.duplicate()
				_add_status(receiver, st)
		"bonus_keep", "bonus_flat":
			# Reserved for outcome-conditional bonuses (e.g. Group D Mind Detonation).
			# These effect_types are NOT for flat roll upgrades — use SpellBonusEffect instead.
			push_warning("bonus_keep/bonus_flat in outcome_effects not dispatched at A4; use SpellBonusEffect instead")
		_:
			push_warning("Unknown SpellOutcomeEffect.effect_type: " + effect.effect_type)


func _add_pending_guard_debuff(state: CombatantState, pool: String, kind: String, value: int) -> void:
	if not state.pending_guard_debuffs.has(pool):
		state.pending_guard_debuffs[pool] = {"flat": 0, "keep": 0}
	var entry := state.pending_guard_debuffs[pool] as Dictionary
	entry[kind] = (entry.get(kind, 0) as int) + value
	state.pending_guard_debuffs[pool] = entry

# --- End spell outcome effect helpers ---

# --- Mind Detonation helpers (Group C1) ---

## Collects pool/keep/flat SpellBonusEffect bonuses for a spell across all purchased nodes.
## Shared by _resolve_round_spell (cast path) and _detonate_mind_bomb (explosion path).
func _collect_spell_bonuses(spell: SpellData) -> Dictionary:
	var pool_bonus := 0
	var keep_bonus := 0
	var flat_bonus := 0
	for node in PlayerProgression.node_levels:
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = PlayerProgression.node_levels[node] as int
		for i in range(mini(lvl, nd.levels_data.size())):
			for be in nd.levels_data[i].bonus_effects:
				var matches: bool
				if be.spell_id != "":
					matches = be.spell_id == spell.spell_name
				else:
					matches = spell.tags.has(be.tag)
				if matches:
					match be.bonus_type:
						"pool": pool_bonus += be.value
						"keep": keep_bonus += be.value
						"flat": flat_bonus += be.value
	return {"pool": pool_bonus, "keep": keep_bonus, "flat": flat_bonus}


## Phase 2.1 check: fires if the enemy carries mind_detonation_primed and their Stance
## was breached this round. Called after the player's Phase 2 attack in all round types.
## KNOWN SIMPLIFICATION: uses global _current_round_player_breaches["stance"], not per-enemy.
## If multiple enemies are primed, any Stance breach in the round triggers all primed bombs.
func _check_mind_detonation(enemy: CombatantState, enemy_index: int) -> void:
	if not _has_status(enemy, "mind_detonation_primed"):
		return
	if not _current_round_player_breaches.get("stance", false):
		return
	await _detonate_mind_bomb(enemy, enemy_index)


## Detonates a primed mind-bomb: builds explosion roll, routes through _resolve_attack vs Resolve.
## Status removed BEFORE _resolve_attack — prevents re-trigger via on_breach (MD keys on Stance,
## explosion breaches Resolve; different pools, so no re-trigger even without the guard).
## No Fervor escalation: explosion is a delayed payoff, not a fresh cast.
func _detonate_mind_bomb(enemy: CombatantState, enemy_index: int) -> void:
	var status := _get_status(enemy, "mind_detonation_primed")
	if status == null:
		return
	var frozen_fervor: int = status.stat_overrides.get("fervor_at_prime", 0) as int
	_remove_status(enemy, "mind_detonation_primed")

	var md_spell: SpellData = preload("res://resources/data/spells/mind_detonation.tres")
	var bonuses := _collect_spell_bonuses(md_spell)
	var pool: int = _effective_tier(_player, _get_action_modifier(_player, "strike")) + (bonuses["pool"] as int)
	var keep: int = _training_keep_grade(_player) + (bonuses["keep"] as int)
	var die: int  = _stat_size(_player, "ingenuity")
	var flat: int = bonuses["flat"] as int

	log_message.emit("[color=magenta][b]MIND DETONATION![/b] The charge erupts against %s's Resolve![/color]" % enemy.data.combatant_name)

	var explosion_result := RollEngine.resolve(pool, die, keep, flat, 0, frozen_fervor)
	log_message.emit(_fmt_spell_attack("[Mind Detonation]", explosion_result))

	await _resolve_attack(true, enemy_index, explosion_result, "resolve")
	# _resolve_attack handles guard roll, Massive logic, wound signals, and defeat detection.
	# No _escalate_fervor call: explosion is not a cast.


## Mind Rend: attacks enemy Resolve. On breach, suppresses the wound and applies hex_marked.
## If Resolve holds, nothing happens (no mark, no wound).
## Does NOT route through _resolve_attack — that path always deals the breach wound.
## Mark applied AFTER on_breach hook so Mind Rend's own breach is never self-amplified
## (wound is suppressed anyway, but ordering is kept correct for future consistency).
func _cast_mind_rend(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	if enemy == null or enemy.is_defeated:
		return
	var attack_total: int = attack_result.total as int
	var defensive_size: int = _get_pool_size(enemy, "resolve")

	# Guard roll — mirrors _resolve_attack's enemy-defender subset for the "resolve" pool.
	var _pool_fresh := not enemy.is_pool_rolled("resolve")
	if _pool_fresh:
		var defend_mod: ActionModifier = _get_action_modifier(enemy, "defend")
		var _ew := enemy.weapon_override if enemy.weapon_override else enemy.data.equipped_weapon
		var cap_str := "uncapped" if defend_mod.tier_cap == 0 else "cap %d" % defend_mod.tier_cap
		log_message.emit("  %s defends with [i]%s[/i] (%s, Tier %d → %d dice)" % [
			enemy.data.combatant_name,
			_ew.item_name if _ew else "Bare Hands",
			cap_str,
			enemy.data.tier,
			_effective_tier(enemy, defend_mod),
		])
		var flat_debuff: int = 0
		var keep_debuff: int = 0
		var _pending: Variant = enemy.pending_guard_debuffs.get("resolve", null)
		if _pending != null:
			flat_debuff = (_pending as Dictionary).get("flat", 0) as int
			keep_debuff = (_pending as Dictionary).get("keep", 0) as int
			enemy.pending_guard_debuffs.erase("resolve")
			if flat_debuff != 0 or keep_debuff != 0:
				log_message.emit("  [color=purple][Outcome debuff] flat %+d, keep grade %+d on %s Resolve guard.[/color]" % [
					flat_debuff, keep_debuff, enemy.data.combatant_name
				])
		var def_result := RollEngine.resolve(
			_effective_tier(enemy, defend_mod), defensive_size,
			maxi(1, _defense_keep_grade(enemy, "resolve") + keep_debuff),
			defend_mod.flat_bonus, 0
		)
		var guard_val: int = (def_result.total as int) + flat_debuff
		enemy.set_guard_val("resolve", guard_val)
		enemy.set_pool_rolled("resolve", true)
		guard_changed.emit(false, enemy_index, "resolve", guard_val)
		log_message.emit(_fmt_defense(enemy.data.combatant_name, def_result, "Resolve"))
	else:
		log_message.emit("  %s Resolve already active — Guard [b]%d[/b] absorbs pressure." % [
			enemy.data.combatant_name, enemy.get_guard("resolve")
		])

	# Breach check: attack_total >= guard.
	var current_guard: int = enemy.get_guard("resolve")
	if attack_total >= current_guard:
		# Fire on_breach hook BEFORE applying the mark. Intentional: mark not yet present,
		# so Mind Rend's own breach cannot interact with its own hex. Wound is suppressed
		# regardless — the mark is the payoff, not the breach.
		_process_statuses_hook("on_breach", enemy, {"pool": "resolve", "attacker": _player})
		_current_round_player_breaches["resolve"] = true
		# Apply mark after the hook for ordering correctness.
		var hex_level: int = PlayerProgression.get_node_level_by_id("hex_mastery")
		var dur: int = 3 if hex_level < 2 else 7
		var hex := CombatStatus.new()
		hex.status_id = "hex_marked"
		hex.duration_rounds = dur
		hex.source_node_id = "hex_mastery"
		_add_status(enemy, hex)
		var perceived_turns: int = 2 if hex_level < 2 else 4
		log_message.emit("[color=purple]Mind Rend tears through! %s's mind is BRANDED — no wound, but the hex takes hold (%d turns).[/color]" % [
			enemy.data.combatant_name, perceived_turns
		])
	else:
		# Resolve holds: no mark, no wound.
		var remaining: int = current_guard - attack_total
		enemy.set_guard_val("resolve", remaining)
		log_message.emit("  %s's Resolve holds (%d remaining). No brand takes hold." % [
			enemy.data.combatant_name, remaining
		])

	# Publish final guard value.
	guard_changed.emit(false, enemy_index, "resolve", enemy.get_guard("resolve"))

# --- End Hex Mastery helpers ---

# --- Chrono-Tinkering helpers (Group C4) ---

## Time Lock: attacks enemy Resolve. On breach, suppresses the wound and applies
## the "time_locked" status (armed phase). On hold, nothing happens.
## Mirrors _cast_mind_rend's structure — dedicated helper to suppress the breach wound.
func _cast_time_lock(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	if enemy == null or enemy.is_defeated:
		return
	var attack_total: int = attack_result.total as int
	var defensive_size: int = _get_pool_size(enemy, "resolve")

	# Guard roll — mirrors _cast_mind_rend's enemy-defender subset for the "resolve" pool.
	var _pool_fresh := not enemy.is_pool_rolled("resolve")
	if _pool_fresh:
		var defend_mod: ActionModifier = _get_action_modifier(enemy, "defend")
		var _ew := enemy.weapon_override if enemy.weapon_override else enemy.data.equipped_weapon
		var cap_str := "uncapped" if defend_mod.tier_cap == 0 else "cap %d" % defend_mod.tier_cap
		log_message.emit("  %s defends with [i]%s[/i] (%s, Tier %d → %d dice)" % [
			enemy.data.combatant_name,
			_ew.item_name if _ew else "Bare Hands",
			cap_str,
			enemy.data.tier,
			_effective_tier(enemy, defend_mod),
		])
		var flat_debuff: int = 0
		var keep_debuff: int = 0
		var _pending: Variant = enemy.pending_guard_debuffs.get("resolve", null)
		if _pending != null:
			flat_debuff = (_pending as Dictionary).get("flat", 0) as int
			keep_debuff = (_pending as Dictionary).get("keep", 0) as int
			enemy.pending_guard_debuffs.erase("resolve")
			if flat_debuff != 0 or keep_debuff != 0:
				log_message.emit("  [color=purple][Outcome debuff] flat %+d, keep grade %+d on %s Resolve guard.[/color]" % [
					flat_debuff, keep_debuff, enemy.data.combatant_name
				])
		var def_result := RollEngine.resolve(
			_effective_tier(enemy, defend_mod), defensive_size,
			maxi(1, _defense_keep_grade(enemy, "resolve") + keep_debuff),
			defend_mod.flat_bonus, 0
		)
		var guard_val: int = (def_result.total as int) + flat_debuff
		enemy.set_guard_val("resolve", guard_val)
		enemy.set_pool_rolled("resolve", true)
		guard_changed.emit(false, enemy_index, "resolve", guard_val)
		log_message.emit(_fmt_defense(enemy.data.combatant_name, def_result, "Resolve"))
	else:
		log_message.emit("  %s Resolve already active — Guard [b]%d[/b] absorbs pressure." % [
			enemy.data.combatant_name, enemy.get_guard("resolve")
		])

	# Breach check: attack_total >= guard.
	var current_guard: int = enemy.get_guard("resolve")
	if attack_total >= current_guard:
		# Fire on_breach hook BEFORE applying the status. Intentional: same ordering as
		# _cast_mind_rend. Time Lock's own breach cannot trigger the armed→frozen transition
		# because the status is applied AFTER this hook, and the transition fires in _resolve_attack
		# (which this function bypasses). Wound is suppressed — the freeze is the payoff.
		_process_statuses_hook("on_breach", enemy, {"pool": "resolve", "attacker": _player})
		_current_round_player_breaches["resolve"] = true
		var tl := CombatStatus.new()
		tl.status_id = "time_locked"
		tl.duration_rounds = 20  # safety bound; real lifecycle driven by phase + skip_resets
		tl.source_node_id = "chrono_tinkering"
		tl.stat_overrides = {"phase": "armed", "locked_pool": "", "skip_resets": 0, "frozen_value": 0}
		_add_status(enemy, tl)
		log_message.emit("[color=cyan]Time Lock takes hold — the next guard you strike will be frozen.[/color]")
	else:
		# Resolve holds: no status, no wound.
		var remaining: int = current_guard - attack_total
		enemy.set_guard_val("resolve", remaining)
		log_message.emit("  %s's Resolve holds (%d remaining). The time-snare fails to catch." % [
			enemy.data.combatant_name, remaining
		])

	# Publish final guard value.
	guard_changed.emit(false, enemy_index, "resolve", enemy.get_guard("resolve"))

# --- End Chrono-Tinkering helpers ---

# --- Echoing Mind helpers (Group C3) ---

## Resolves one end_of_round echo of an echoing spell. Called from the player's
## end_of_round hook in _process_statuses_hook.
## Decrements current_kept_dice for the next round; removes the status when no more echoes remain.
## Uses frozen Fervor from the status payload — echo is a delayed payoff, not a fresh cast.
## Does NOT call _escalate_fervor (intentional — frozen Fervor + no escalation is the design).
## Pool tier uses _effective_tier with the strike mod, matching the original cast exactly.
func _resolve_spell_echo(status: CombatStatus, state: CombatantState) -> void:
	var spell_path: String = status.stat_overrides.get("spell_path", "") as String
	var target_index: int  = status.stat_overrides.get("target_index", -1) as int
	var frozen_fervor: int = status.stat_overrides.get("frozen_fervor", 0) as int
	var current_kept: int  = status.stat_overrides.get("current_kept_dice", 0) as int
	var em_level: int      = status.stat_overrides.get("em_level", 1) as int

	if spell_path == "" or target_index < 0 or target_index >= _enemies.size():
		_remove_status(state, "echoing_spell")
		return
	var spell: SpellData = load(spell_path) as SpellData
	if spell == null:
		_remove_status(state, "echoing_spell")
		return
	var target: CombatantState = _enemies[target_index]
	if target == null or target.is_defeated:
		log_message.emit("[color=cyan]The echo fades — no one left to hear it.[/color]")
		_remove_status(state, "echoing_spell")
		return

	var bonuses := _collect_spell_bonuses(spell)
	var pool: int      = _effective_tier(_player, _get_action_modifier(_player, "strike")) + (bonuses["pool"] as int)
	var keep_grade: int = current_kept  # keep_grade IS the kept-dice count (post-refactor naming)
	var die: int       = _stat_size(_player, "ingenuity")
	var base_flat: int = spell.flat_bonus + (bonuses["flat"] as int)
	var echo_flat: int = current_kept if em_level >= 2 else 0  # L2: flat = kept dice for this echo
	var total_flat: int = base_flat + echo_flat

	var flat_note: String = (" (+%d flat from Echoing Mind L2)" % echo_flat) if em_level >= 2 else ""
	log_message.emit("[color=cyan][b]ECHO![/b] %s resounds — keeping %d die(s)%s.[/color]" % [
		spell.spell_name, current_kept, flat_note
	])

	var echo_result := RollEngine.resolve(pool, die, keep_grade, total_flat, 0, frozen_fervor)
	log_message.emit(_fmt_spell_attack("[Echo: %s]" % spell.spell_name, echo_result))

	# Route through _resolve_attack: Hex amplification and on_breach hooks fire normally.
	# No _escalate_fervor: echo is not a cast; Fervor stays frozen.
	await _resolve_attack(true, target_index, echo_result, spell.target_pool)

	# Phase 2.1 equivalent: echo Stance breach can detonate primed mind-bombs.
	if not target.is_defeated:
		await _check_mind_detonation(target, target_index)

	# Decrement kept dice; remove status when next echo would keep 0 dice.
	var next_kept: int = current_kept - 1
	if next_kept < 1:
		_remove_status(state, "echoing_spell")
		log_message.emit("[color=cyan]The echo dies away.[/color]")
	else:
		status.stat_overrides["current_kept_dice"] = next_kept

# --- End Echoing Mind helpers ---

func _process_statuses_hook(
		hook: String,
		state: CombatantState,
		context: Dictionary = {}
) -> void:
	## Dispatches status effects for the given hook and combatant.
	## HARD RULE: logic lives here via match on status_id, NEVER inside CombatStatus itself.
	## .duplicate() prevents mutation of the array if a future case adds/removes statuses mid-loop.
	for status in state.active_statuses.duplicate():
		match status.status_id:
			"mind_detonation_primed":
				pass  # Breach-driven via _check_mind_detonation at Phase 2.1 (post player-attack);
				      # not hook-driven. The bomb does nothing on start_of_round / end_of_round hooks.
			"hex_marked":
				pass  # Amplification is breach-driven via _resolve_attack; not hook-driven.
			"time_locked":
				pass  # Two-phase mechanic (armed→frozen). Transition fires in _resolve_attack;
				      # freeze preservation fires in _end_of_round. No hook-driven work.
			"echoing_spell":
				if hook == "end_of_round":
					await _resolve_spell_echo(status, state)
			_:
				pass


func _end_of_round() -> void:
	await _process_statuses_hook("end_of_round", _player)
	for enemy_state in _enemies:
		await _process_statuses_hook("end_of_round", enemy_state)

	# An end_of_round echo may have killed enemies; end combat before continuing.
	if _all_enemies_defeated():
		_end_combat()
		return

	_tick_statuses(_player)
	for enemy_state in _enemies:
		_tick_statuses(enemy_state)

	# Guard reset: moved here from _begin_round so guards are already 0 when start_of_round hooks fire.
	_player.reset_guard()
	for pool in POOL_NAMES:
		guard_changed.emit(true, -1, pool, 0)
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		# Chrono-Tinkering: read frozen_value stored at transition time (breach-aware).
		# Capture BEFORE reset so it survives reset_guard(). Echoes may have updated
		# frozen_value via _resolve_attack in the end_of_round hooks above — correct.
		var frozen_pool := ""
		var frozen_val := 0
		var ct_status := _get_status(e, "time_locked")
		if ct_status != null \
				and (ct_status.stat_overrides.get("phase", "") as String) == "frozen" \
				and (ct_status.stat_overrides.get("skip_resets", 0) as int) > 0:
			frozen_pool = ct_status.stat_overrides.get("locked_pool", "") as String
			frozen_val = ct_status.stat_overrides.get("frozen_value", 0) as int
		e.reset_guard()
		for pool in POOL_NAMES:
			guard_changed.emit(false, i, pool, 0)
		# Restore frozen pool after reset; mark it rolled so it won't re-roll next round.
		if frozen_pool != "":
			e.set_guard_val(frozen_pool, frozen_val)
			e.set_pool_rolled(frozen_pool, true)
			guard_changed.emit(false, i, frozen_pool, frozen_val)
			ct_status.stat_overrides["skip_resets"] = (ct_status.stat_overrides["skip_resets"] as int) - 1
			log_message.emit("[color=cyan]%s's %s remains frozen at %d (%d round(s) left).[/color]" % [
				e.data.combatant_name, frozen_pool, frozen_val,
				ct_status.stat_overrides["skip_resets"] as int
			])
			if (ct_status.stat_overrides["skip_resets"] as int) <= 0:
				_remove_status(e, "time_locked")
				log_message.emit("[color=cyan]The time-freeze on %s's %s expires.[/color]" % [
					e.data.combatant_name, frozen_pool
				])

	await get_tree().create_timer(0.8).timeout


## Passive Max Wounds bonus from Tier: +1 at Tier 2, +1 again at Tier 4 (cumulative +2).
func _tier_wound_bonus(tier: int) -> int:
	return (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)


## Sums max_wounds bonuses from Wounds Training nodes (effect_type="training_wounds").
func _wounds_node_bonus(state: CombatantState) -> int:
	return _node_effect_sum(state, "training_wounds")


## Returns the effective physical keep grade: max of training_keep or physical_keep nodes.
func _physical_keep_grade(state: CombatantState) -> int:
	return maxi(_training_keep_grade(state), _node_effect_max(state, "physical_keep"))


## Returns the max uses_per_combat across all purchased meat_grinder NodeLevelData entries.
func _meat_grinder_charges(state: CombatantState) -> int:
	var best := 0
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == "meat_grinder":
				best = maxi(best, ld.uses_per_combat)
	return best


## Returns the die size for the given defense pool on a combatant.
## Stance = Negation, Resolve = Ingenuity, Stamina = Dominion (defensive expression).
func _get_pool_size(state: CombatantState, pool: String) -> int:
	match pool:
		"stance":  return _stat_size(state, "negation")
		"resolve": return _stat_size(state, "ingenuity")
		"stamina": return _stat_size(state, "dominion")
	return _stat_size(state, "negation")


## Effective Tier: tier_override if set, else data.tier, capped by ActionModifier.tier_cap.
## Pass the relevant ActionModifier (strike or defend); null or tier_cap=0 means uncapped.
func _effective_tier(state: CombatantState, mod: ActionModifier = null) -> int:
	var base := state.tier_override if state.tier_override > 0 else state.data.tier
	if mod == null or mod.tier_cap == 0:
		return base
	return mini(base, mod.tier_cap)


## Flat bonus applied to attack rolls: strike ActionModifier flat + weapon_flat node bonuses.
func _attack_flat(state: CombatantState) -> int:
	return _get_action_modifier(state, "strike").flat_bonus + _node_weapon_bonus_sum(state, "weapon_flat")


## Returns {item_name, mod} for the player's defense roll.
## If both main-hand and off-hand carry a "defend" modifier, emits player_defense_item_choice
## and awaits the player's selection; otherwise auto-selects the sole available option.
func _get_player_defense_modifier() -> Dictionary:
	var options: Array = []
	var main_w: EquipmentData = _player.weapon_override if _player.weapon_override else _player.data.equipped_weapon
	if main_w:
		for mod in main_w.action_modifiers:
			if mod.action_key == "defend":
				options.append({"item_name": main_w.item_name, "mod": mod})
				break
	if _player.off_hand_override:
		for m in _player.off_hand_override.action_modifiers:
			if m.action_key == "defend":
				options.append({"item_name": _player.off_hand_override.item_name, "mod": m})
				break
	if options.size() >= 2:
		if PlayerProgression.combat_prefs.def_mode == "observe":
			player_defense_item_choice.emit(options)
			var chosen_mod: ActionModifier = await _defense_item_chosen
			for opt in options:
				if opt["mod"] == chosen_mod:
					return opt
			return options[0]
		else:
			# Auto mode: honour saved default, fall back to main-hand.
			var saved: String = PlayerProgression.combat_prefs.defaults.get("defend_weapon", "")
			if saved != "":
				for opt in options:
					if opt["item_name"] == saved:
						log_message.emit("[color=gray][Auto] Defend with %s (default)[/color]" % saved)
						return opt
			return options[0]
	if options.size() >= 1:
		return options[0]
	return {"item_name": "Bare Hands", "mod": _player.data.get_bare_hands_modifier("defend")}


## Flat bonus applied to defense rolls: defend ActionModifier flat.
func _guard_flat(state: CombatantState) -> int:
	return _get_action_modifier(state, "defend").flat_bonus


## Pool size modifier from the ActionModifier for the given action key.
func _pool_bonus(state: CombatantState, action_key: String = "strike") -> int:
	return _get_action_modifier(state, action_key).pool_bonus


## Looks up the ActionModifier for action_key: weapon first, then bare_hands (always present).
## For the player, weapon_override == null means bare hands (PlayerProgression.main_hand not set).
## For enemies, weapon_override == null falls back to data.equipped_weapon (their fixed weapon).
func _get_action_modifier(state: CombatantState, action_key: String) -> ActionModifier:
	var w: EquipmentData
	if state == _player:
		w = state.weapon_override
	else:
		w = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	if w:
		for mod in w.action_modifiers:
			if mod.action_key == action_key:
				return mod
	return state.data.get_bare_hands_modifier(action_key)


## Architecture stub: applies derivation_ratio to parent's bonuses (floor). No derived actions yet.
func _derived_modifier(mod: ActionModifier, parent: ActionModifier) -> ActionModifier:
	var derived := mod.duplicate() as ActionModifier
	if mod.parent_action_key != "" and mod.derivation_ratio > 0.0:
		derived.flat_bonus  = floori(parent.flat_bonus  * mod.derivation_ratio)
		derived.keep_bonus  = floori(parent.keep_bonus  * mod.derivation_ratio)
		derived.pool_bonus  = floori(parent.pool_bonus  * mod.derivation_ratio)
	return derived


## Returns all ActionModifiers for a state: main-hand + off-hand + bare_hands (always present).
func _get_all_action_modifiers(state: CombatantState) -> Array:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	var result: Array = []
	if w:
		result.append_array(w.action_modifiers)
	if state.off_hand_override:
		result.append_array(state.off_hand_override.action_modifiers)
	if not state.data.bare_hands_actions.is_empty():
		result.append_array(state.data.bare_hands_actions)
	else:
		result.append(state.data.get_bare_hands_modifier("strike"))
		result.append(state.data.get_bare_hands_modifier("defend"))
	return result


## Returns the max effect_value across all purchased NodeLevelData entries matching the given key.
func _node_effect_max(state: CombatantState, key: String) -> int:
	var best := 0
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == key:
				best = maxi(best, ld.effect_value)
	return best


## Returns the sum of effect_value across all purchased NodeLevelData entries matching the given key.
func _node_effect_sum(state: CombatantState, key: String) -> int:
	var total := 0
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == key:
				total += ld.effect_value
	return total


## Returns the sum of effect_value for entries matching key where all weapon_tags match the equipped weapon.
func _node_weapon_bonus_sum(state: CombatantState, key: String) -> int:
	var total := 0
	var weapon: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type != key:
				continue
			if ld.weapon_tags.is_empty():
				total += ld.effect_value
			elif weapon != null:
				var all_match := true
				for tag in ld.weapon_tags:
					if not weapon.tags.has(tag):
						all_match = false
						break
				if all_match:
					total += ld.effect_value
	return total


## Returns true if any purchased NodeLevelData entry has the given effect_type.
func _has_effect_type(state: CombatantState, key: String) -> bool:
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			if nd.levels_data[i].effect_type == key:
				return true
	return false


## Returns the effective die size for a stat, upgraded by any unlocked Core nodes.
func _stat_size(state: CombatantState, stat: String) -> int:
	# Status overrides take priority over all other sources.
	for status in state.active_statuses:
		if status.stat_overrides.has(stat):
			return status.stat_overrides[stat] as int
	var base: int
	match stat:
		"dominion":  base = state.data.dominion_size
		"negation":  base = state.data.negation_size
		"ingenuity": base = state.data.ingenuity_size
		_: base = 6
	return maxi(base, _node_effect_max(state, "stat_size_" + stat))


## Returns the effective keep grade for a combatant: highest Training node value,
## or data.keep_grade as fallback when no Training node is present.
func _training_keep_grade(state: CombatantState) -> int:
	return maxi(state.data.keep_grade, _node_effect_max(state, "training_keep"))


## Returns the effective defensive keep grade for the given pool: max of
## _training_keep_grade and pool-specific *_keep nodes (mirrors _physical_keep_grade architecture).
func _defense_keep_grade(state: CombatantState, pool: String) -> int:
	return maxi(_training_keep_grade(state), _node_effect_max(state, pool + "_keep"))


## Steps Fervor by `steps` track positions (positive = escalate, negative = cool).
## Burnout fires only on escalation (positive steps) when raw_new_idx exceeds cap_idx.
## Negative steps (Lucidity L1 cooling) never trigger Burnout and skip the cap clamp.
func _escalate_fervor(state: CombatantState, steps: int) -> void:
	var cap: int = _stat_size(state, "ingenuity")
	var cap_idx: int = FERVOR_TRACK.find(cap)
	if cap_idx == -1:
		cap_idx = FERVOR_TRACK.size() - 1
	var idx: int = FERVOR_TRACK.find(state.fervor_size)
	if idx == -1:
		idx = 0
	var prev_size: int = FERVOR_TRACK[idx]
	var raw_new_idx: int = idx + steps
	# Negative steps are floored at index 0; positive steps are ceilinged at FERVOR_TRACK.size()-1.
	var clamped_idx: int = clampi(raw_new_idx, 0, FERVOR_TRACK.size() - 1)
	var new_size: int = FERVOR_TRACK[clamped_idx]
	if steps < 0 and new_size < prev_size:
		log_message.emit("  [color=cyan]Fervor cooled: d%d → d%d. Safer, but next casts are weaker.[/color]" % [prev_size, new_size])
	elif new_size != prev_size:
		log_message.emit("  [color=magenta]Fervor escalates: d%d → d%d[/color]" % [prev_size, new_size])
	else:
		log_message.emit("  [color=magenta]Fervor at maximum track position (d%d).[/color]" % new_size)
	# Burnout only on escalation: cooling never triggers it regardless of the current position.
	# Lucidity L2: offer the player a chance to cancel the imminent Burnout.
	if steps > 0 and raw_new_idx > cap_idx and not state.is_burned_out:
		var prevented := await _try_prevent_burnout(state)
		if not prevented:
			state.is_burned_out = true
			log_message.emit("[color=orange][b]BURNOUT![/b] Fervor surged beyond control. True spells blocked until next combat.[/color]")
	# Escalation caps Fervor at the ingenuity die; cooling uses the raw track position.
	state.fervor_size = mini(new_size, cap) if steps > 0 else new_size
	fervor_changed.emit(state == _player, state.fervor_size, cap, state.is_burned_out)


## Resets item action charges for all active combatants matching the given rest_type.
## Called by DungeonManager on short/long rest. No-op when no combat is running.
func reset_item_charges(rest_type: String) -> void:
	var all_states: Array = []
	if _player != null:
		all_states.append(_player)
	all_states.append_array(_enemies)
	for state in all_states:
		for mod in _get_all_action_modifiers(state):
			if mod.rest_type == rest_type and mod.uses_per_rest > 0:
				state.item_action_charges[mod.action_key] = mod.uses_per_rest


## Debug only — swap the player's main-hand weapon at runtime without restarting combat.
func debug_set_player_weapon(weapon: EquipmentData) -> void:
	if _player:
		_player.weapon_override = weapon


## Debug only — swap the player's off-hand weapon at runtime without restarting combat.
func debug_set_player_off_hand(weapon: EquipmentData) -> void:
	if _player:
		_player.off_hand_override = weapon


## Returns the player's bare-hands ActionModifier for action_key, or null if unavailable.
## Used by RoundHUD to build pinnable bare-hands tool entries.
func get_player_bare_hands_modifier(action_key: String) -> ActionModifier:
	if not _player:
		return null
	return _player.data.get_bare_hands_modifier(action_key)


## Returns an approximate expected attack total for the player's current strike.
## Formula: tier × (die_size + 1) / 2 + flat. Pool-independent — pool affects enemy guard only.
func get_player_attack_preview() -> int:
	if not _player:
		return 0
	var mod := _get_action_modifier(_player, "strike")
	var tier := _effective_tier(_player, mod)
	var die_size := _stat_size(_player, "dominion")
	var flat := _attack_flat(_player)
	return int(tier * (die_size + 1) / 2.0) + flat


# ── Formatting helpers ────────────────────────────────────────────────────────

func _attacker_weapon_name(state: CombatantState) -> String:
	var w: EquipmentData
	if state == _player:
		w = state.weapon_override
	else:
		w = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.item_name if w else "Bare Hands"


func _fmt_attack(name: String, r: Dictionary, weapon_name: String = "") -> String:
	var desperation: bool = r.desperation
	var prefix := "[b][DESPERATION][/b] " if desperation else ""
	var flat: int = r.flat as int
	var flat_part := " + %d flat" % flat if flat != 0 else ""
	var with_part := " with [i]%s[/i]" % weapon_name if weapon_name != "" else ""
	return "  %s%s attacks%s: rolled %s, kept %s%s → [b]%d[/b]" % [
		prefix, name, with_part, _arr(r.dice as Array), _arr(r.kept as Array), flat_part, r.total as int
	]


func _fmt_spell_attack(name: String, r: Dictionary) -> String:
	var desperation: bool = r.desperation
	var prefix := "[b][DESPERATION][/b] " if desperation else ""
	var fervor_roll: int = r.fervor_roll as int
	var fervor_part := " + [color=magenta]Fervor %d[/color]" % fervor_roll if fervor_roll > 0 else ""
	var maxed_note := " [color=magenta][b][MAX][/b][/color]" if (r.fervor_maxed as bool) else ""
	return "  %s%s casts: rolled %s, kept %s%s → [b]%d[/b]%s" % [
		prefix, name, _arr(r.dice as Array), _arr(r.kept as Array),
		fervor_part, r.total as int, maxed_note
	]


func _fmt_speed(name: String, total: int, vt: int, fast: bool) -> String:
	var tag := "[color=cyan]FAST[/color]" if fast else "[color=gray]slow[/color]"
	return "  %s: %d vs VT %d → %s" % [name, total, vt, tag]


func _fmt_defense(name: String, r: Dictionary, pool_label: String) -> String:
	var flat: int = r.flat as int
	var flat_part := " + %d flat" % flat if flat != 0 else ""
	return "  %s rolls %s: %s → kept %s%s → Guard [b]%d[/b]" % [
		name, pool_label, _arr(r.dice as Array), _arr(r.kept as Array), flat_part, r.total as int
	]


func _arr(a: Array) -> String:
	return "[" + ", ".join(a.map(func(v): return str(v))) + "]"
