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
## is_initial: true for display-sync emissions (combat start, debug refill) —
## no real attack happened, so listeners must not play hit/death reactions.
signal wounds_changed(is_player: bool, enemy_index: int, current: int, max_wounds: int, is_initial: bool)

## Emitted after a defender's guard pool changes (roll, consumption, or reset).
## is_player: true = player's guard; false = enemy's guard.
## enemy_index: index into the enemy array (-1 when is_player is true).
## pool: "stance" | "resolve" | "stamina"
signal guard_changed(is_player: bool, enemy_index: int, pool: String, guard_value: int)

## Emitted when a combatant's attack is about to resolve — drives attack
## animations on the battle visuals. enemy_index: the enemy participant
## (the attacker when is_player is false, the TARGET when is_player is true).
signal combatant_attacking(is_player: bool, enemy_index: int)

## Emitted once at the end of every _resolve_attack pass (all attack paths: strike,
## auto, cantrip, spell, enemy, echo, mind-detonation). Drives impact presentation.
## enemy_index: the enemy participant (target when attacker_is_player, else attacker).
## wounds_dealt is 0 when the guard held (did_breach false → "Blocked").
signal attack_resolved(attacker_is_player: bool, enemy_index: int, target_pool: String,
		did_breach: bool, is_massive: bool, wounds_dealt: int, defender_defeated: bool)

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

## Emitted when a player guard would break and a Magic Shield charge can reinforce it
## (ing_resolve L2+). dice_count/die_size preview the reinforcement roll.
signal player_shield_opportunity(charges_left: int, incoming: int, guard: int, dice_count: int, die_size: int)
## Internal gate awaited by _try_magic_shield; resolved when player decides.
signal _shield_decision_gate(use_charge: bool)


# ── Runtime state ─────────────────────────────────────────────────────────────

# CombatantState (per-combat mutable state) lives in combat/CombatantState.gd as a global
# class_name (extracted in Phase 1 of the CombatManager refactor). All references below
# resolve to that class.


var _player: CombatantState
var _enemies: Array  # Array[CombatantState]
var _round:  int = 0
var _debug_immortal: bool = false
var _debug_lethal: bool = false

## Seconds to pause after each resolved attack so the scene's presentation can play out.
## 0.0 (default) = no pause — headless runs and tests are unaffected. BattleScene sets it.
var attack_pacing_s: float = 0.0

## True only while awaiting the player's action input.
var _waiting_for_player: bool = false
## Weapon the player explicitly chose this round; null = use default main-hand resolution.
var _player_strike_weapon: EquipmentData = null
## Presentation support: weapon the player's current strike visually resolves with
## (main-hand fallback applied; null = bare hands). Read by BattleScene at
## combatant_attacking time for per-action FX — needed for Auto attacks, where
## the scene never learns which weapon the auto-picker chose.
var player_strike_weapon_resolved: EquipmentData = null
## Presentation support: FX intensity facts for the attack about to resolve —
## the attacker's governing stat die size (dominion for strikes, ingenuity for
## casts; status overrides included) and the governing node level (0 = none,
## enemies always 0). Set right before every combatant_attacking emission.
var fx_attack_die_size: int = 6
var fx_attack_node_level: int = 0
## Casting tool the player chose this round; null = Bare Hands (uncapped, full Tier).
var _player_cast_weapon: EquipmentData = null
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
	# Magic Shield (ing_resolve L2+): guard-shaped interrupt; dice fed by the node level.
	var shield_charges := CombatMath.magic_shield_charges(_player)
	if shield_charges > 0:
		var shield_handler := InterruptHandler.new()
		shield_handler.handler_id = "magic_shield"
		shield_handler.trigger = "on_guard_break"
		shield_handler.target = "self"
		shield_handler.charges = shield_charges
		shield_handler.priority = 10
		shield_handler.source_node_id = "ing_resolve"
		_register_interrupt(_player, shield_handler)
	_player.space_domination_active = _has_effect_type(_player, "space_domination")
	_player.current_wounds = mini(PlayerProgression.saved_wounds, _player.max_wounds)
	wounds_changed.emit(true, -1, _player.current_wounds, _player.max_wounds, true)
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
		wounds_changed.emit(false, i, 0, state.max_wounds, true)

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
func player_chose_cantrip(spell: SpellData, target_index: int = 0, source_weapon: EquipmentData = null) -> void:
	if not _waiting_for_player:
		return
	if not CombatMath.can_channel_cantrips(_player):
		log_message.emit("[color=orange]No conduit! Cantrips need empty hands or an equipped Magic Focus.[/color]")
		_emit_player_intents()
		player_magic_available.emit(false,
			_player.known_spells.size() > 0 and not _player.is_burned_out
				and CombatMath.can_channel_spells(_player))
		player_action_required.emit()
		return
	_waiting_for_player = false
	_player_cast_weapon = source_weapon
	_resolve_round_cantrip(spell, target_index)


## Called by BattleScene when the player selects a true spell.
## Ingenuity-based attack with a real Fervor die; blocked during Burnout.
func player_chose_spell(spell: SpellData, target_index: int = 0, source_weapon: EquipmentData = null) -> void:
	if not _waiting_for_player:
		return
	if _player.is_burned_out:
		log_message.emit("[color=orange]Burnout! True spells are blocked — choose Strike or Cantrip.[/color]")
		_emit_player_intents()
		player_magic_available.emit(
			_player.known_cantrips.size() > 0 and CombatMath.can_channel_cantrips(_player), false)
		player_action_required.emit()
		return
	if not CombatMath.can_channel_spells(_player):
		log_message.emit("[color=orange]No focus! True spells require an equipped Magic Focus.[/color]")
		_emit_player_intents()
		player_magic_available.emit(
			_player.known_cantrips.size() > 0 and CombatMath.can_channel_cantrips(_player), false)
		player_action_required.emit()
		return
	_waiting_for_player = false
	_player_cast_weapon = source_weapon
	_resolve_round_spell(spell, target_index)


## Called by RoundHUD (via BattleScene) when the player resolves a Meat for the Grinder prompt.
func player_chose_degrade_wound(use_charge: bool) -> void:
	_massive_decision_gate.emit(use_charge)


## Called by RoundHUD (via BattleScene) when the player responds to the Lucidity L2 Burnout prompt.
func player_chose_prevent_burnout(use_charge: bool) -> void:
	_burnout_decision_gate.emit(use_charge)


## Called by RoundHUD (via BattleScene) when the player responds to the Magic Shield prompt.
func player_chose_magic_shield(use_charge: bool) -> void:
	_shield_decision_gate.emit(use_charge)


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
		wounds_changed.emit(true, -1, 0, _player.max_wounds, true)


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
	log_message.emit("[b]——— Round %d ———[/b]" % _round)
	phase_changed.emit("Choose your action")

	_waiting_for_player = true
	_emit_player_intents()
	player_magic_available.emit(
		_player.known_cantrips.size() > 0 and CombatMath.can_channel_cantrips(_player),
		_player.known_spells.size() > 0 and not _player.is_burned_out
			and CombatMath.can_channel_spells(_player)
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
	var tier := _effective_tier(_player)
	var die_size := _stat_size(_player, "dominion")
	var flat := _attack_flat(_player)
	var score: float = tier * (1.0 + die_size) / 2.0 + flat
	var tp: String = mod.target_pool if mod.target_pool != "" else "stance"
	return {"target_pool": tp, "score": score}


## Publishes the FX intensity facts for the attack about to resolve (see the
## fx_attack_* vars). Presentation only — call right before combatant_attacking.
func _set_attack_fx_facts(attacker: CombatantState, stat: String, node_id: String = "") -> void:
	fx_attack_die_size = _stat_size(attacker, stat)
	fx_attack_node_level = PlayerProgression.get_node_level_by_id(node_id) if node_id != "" else 0


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
	player_strike_weapon_resolved = chosen_weapon if chosen_weapon != null else _player.weapon_override
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
	var keep_grade := _physical_keep_grade(_player) + _node_weapon_bonus_sum(_player, "weapon_keep", chosen_weapon) + _strike_mod.keep_bonus
	var brutal_flat := 5 if brutal_trade else 0

	var earthshatter_size := 0
	if target_pool == "stance" and _node_effect_max(_player, "earthshatter") > 0:
		earthshatter_size = _stat_size(_player, "dominion")
		log_message.emit("  [color=cyan]Earthshatter![/color] Post-keep Dominion d%d added." % earthshatter_size)

	var p_atk := RollEngine.resolve(
		_effective_tier(_player), _stat_size(_player, "dominion"), keep_grade,
		_attack_flat(_player, _strike_mod, chosen_weapon) + brutal_flat,
		net_advantage + _pool_bonus(_player, "strike", _strike_mod),
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
	if await _run_enemy_attacks(true, p_total, target_pool, target_index, brutal_trade):
		_end_combat()
		return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	if not target.is_defeated:
		_set_attack_fx_facts(_player, "dominion", "dom_martial_arts")
		combatant_attacking.emit(true, target_index)
		await _resolve_attack(true, target_index, p_atk, target_pool)
		if attack_pacing_s > 0.0:
			await get_tree().create_timer(attack_pacing_s).timeout

	# Phase 2.1 — post player-attack: detonate any primed mind-bomb if Stance was breached.
	if not target.is_defeated:
		await _check_mind_detonation(target, target_index)

	if _all_enemies_defeated():
		_end_combat()
		return

	# ── Phase 3: Fast enemies attack last ─────────────────────────────────
	if await _run_enemy_attacks(false, p_total, target_pool, target_index, brutal_trade):
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

	var cast_mod := _get_cast_modifier(_player)
	_player_cast_weapon = null
	var p_atk := RollEngine.resolve(
		_effective_tier(_player) + cast_mod.pool_bonus,
		_stat_size(_player, "ingenuity"),
		_training_keep_grade(_player) + cast_mod.keep_bonus,
		spell.flat_bonus + cast_mod.flat_bonus, 0
	)
	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk) + " [cantrip]")

	var p_total: int = p_atk.total as int
	var target_vt: int = target.data.velocity_threshold
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_total, target_vt, RollEngine.is_fast(p_total, target_vt)))

	# ── Phase 1: Slow enemies attack first ────────────────────────────────
	if await _run_enemy_attacks(true, p_total, spell.target_pool, target_index):
		_end_combat()
		return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	var _pool_breached_before_c := _current_round_player_breaches.get(spell.target_pool, false) as bool
	if not target.is_defeated:
		_set_attack_fx_facts(_player, "ingenuity", "minor_studies")
		combatant_attacking.emit(true, target_index)
		await _resolve_attack(true, target_index, p_atk, spell.target_pool)
		if attack_pacing_s > 0.0:
			await get_tree().create_timer(attack_pacing_s).timeout
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
	if await _run_enemy_attacks(false, p_total, spell.target_pool, target_index):
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

	var cast_mod := _get_cast_modifier(_player)
	_player_cast_weapon = null

	# Mind Detonation placement scratch: 1 Ingenuity die, no SpellBonusEffect bonuses.
	# Bonuses (+pool, +keep) are reserved for the explosion built in Disciplines.detonate_mind_bomb.
	# All other spells: collect school bonuses via _collect_spell_bonuses and apply to roll.
	var p_atk: Dictionary
	if spell.placement_scratch:
		p_atk = RollEngine.resolve(
			1,
			_stat_size(_player, "ingenuity"),
			_training_keep_grade(_player),
			0, 0, _player.fervor_size, 0, 0
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
			_effective_tier(_player) + spell_pool_bonus + cast_mod.pool_bonus,
			_stat_size(_player, "ingenuity"),
			_training_keep_grade(_player) + spell_keep_bonus + cast_mod.keep_bonus,
			spell.flat_bonus + spell_flat_bonus + cast_mod.flat_bonus, 0, _player.fervor_size,
			aspect_stat_size, spell.aspect_dice
		)
	log_message.emit(_fmt_spell_attack(_player.data.combatant_name, p_atk))

	var p_total: int = p_atk.total as int
	var target_vt: int = target.data.velocity_threshold
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_total, target_vt, RollEngine.is_fast(p_total, target_vt)))

	# ── Phase 1: Slow enemies attack first ────────────────────────────────
	if await _run_enemy_attacks(true, p_total, spell.target_pool, target_index):
		_end_combat()
		return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	var _pool_breached_before := _current_round_player_breaches.get(spell.target_pool, false) as bool
	if not target.is_defeated:
		# Windup for every cast path; discipline handlers that bypass
		# _resolve_attack emit their own matching attack_resolved.
		_set_attack_fx_facts(_player, "ingenuity", "spellcasting")
		combatant_attacking.emit(true, target_index)
		match spell.cast_handler:
			"mind_rend":
				await _cast_mind_rend(target, target_index, p_atk)
			"time_lock":
				await _cast_time_lock(target, target_index, p_atk)
			_:
				await _resolve_attack(true, target_index, p_atk, spell.target_pool)
		if attack_pacing_s > 0.0:
			await get_tree().create_timer(attack_pacing_s).timeout
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

	# Prime a discipline status on the target (Mind Detonation). The payload build is MD-specific;
	# the flag just decides whether to prime, so no spell_name literal is needed.
	if spell.primes_status != "" and not target.is_defeated:
		var bomb := CombatStatus.new()
		bomb.status_id = spell.primes_status
		bomb.duration_rounds = 3
		bomb.source_node_id = "mind_detonation"
		var bomb_payload := MindBombPayload.new()
		bomb_payload.fervor_at_prime = _player.fervor_size
		bomb_payload.md_level = PlayerProgression.get_node_level_by_id("mind_detonation")
		bomb_payload.cast = CastSnapshot.from_mod(_effective_tier(_player), cast_mod)
		bomb_payload.to_status(bomb)
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
		# cast_mod.keep_bonus baked in here so the focus keep decays with the echo train.
		var _cast_kept_dice: int = _training_keep_grade(_player) + (_echo_bonuses["keep"] as int) + cast_mod.keep_bonus
		var _initial_echo_kept: int = _cast_kept_dice - 1
		if _initial_echo_kept >= 1:
			if _has_status(_player, "echoing_spell"):
				_remove_status(_player, "echoing_spell")
				log_message.emit("[color=cyan]The previous echo is cut off as a new spell begins to resound.[/color]")
			var echo_status := CombatStatus.new()
			echo_status.status_id = "echoing_spell"
			echo_status.duration_rounds = 20  # safety bound; real termination via current_kept_dice < 1
			echo_status.source_node_id = "echoing_mind"
			var echo_payload := EchoPayload.new()
			echo_payload.spell_path = spell.resource_path
			echo_payload.target_index = target_index
			echo_payload.frozen_fervor = _player.fervor_size
			echo_payload.current_kept_dice = _initial_echo_kept
			echo_payload.em_level = PlayerProgression.get_node_level_by_id("echoing_mind")
			echo_payload.cast = CastSnapshot.from_mod(_effective_tier(_player), cast_mod)
			echo_payload.to_status(echo_status)
			_add_status(_player, echo_status)
			log_message.emit("[color=cyan]The spell begins to echo — it will resound for %d more turn(s).[/color]" % _initial_echo_kept)

	if _all_enemies_defeated():
		_end_combat()
		return

	# ── Phase 3: Fast enemies attack last ─────────────────────────────────
	if await _run_enemy_attacks(false, p_total, spell.target_pool, target_index):
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
## Resolves enemy attacks for one timing phase against the player's action, shared by all three
## round coroutines. `slow_phase=true` runs enemies the player is SLOW against (they act before the
## player); false runs FAST enemies (after). `player_target_pool` is the pool the player's action
## pressures the targeted enemy — every other enemy pressures Stance. `brutal_trade` applies the
## strike round's −5 VT to the targeted enemy only. Returns true if the player was defeated (the
## caller must then `_end_combat()` and return).
func _run_enemy_attacks(slow_phase: bool, p_total: int, player_target_pool: String, target_index: int, brutal_trade: bool = false) -> bool:
	for i in _enemies.size():
		var e: CombatantState = _enemies[i]
		if e.is_defeated:
			continue
		if DungeonManager.training_mode and not DungeonManager.training_dummy_attacks:
			# Training room, dummy passive: whole enemy turn skipped — no roll,
			# no windup animation, no pacing pause.
			if slow_phase:
				log_message.emit("[color=gray]%s stands there, menacingly.[/color]" % e.data.combatant_name)
			continue
		var e_vt: int = e.data.velocity_threshold - (5 if brutal_trade and i == target_index else 0)
		# slow phase skips fast enemies; fast phase skips slow enemies.
		if RollEngine.is_fast(p_total, e_vt) == slow_phase:
			continue
		var e_atk := RollEngine.resolve(
			_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
		)
		log_message.emit(_fmt_attack(e.data.combatant_name, e_atk, _attacker_weapon_name(e)))
		_set_attack_fx_facts(e, "dominion")
		combatant_attacking.emit(false, i)
		var e_pool := player_target_pool if i == target_index else "stance"
		await _resolve_attack(false, i, e_atk, e_pool)
		if attack_pacing_s > 0.0:
			await get_tree().create_timer(attack_pacing_s).timeout
		if _player.is_defeated:
			return true
	return false


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
			var _dname: String = _ew.item_name if _ew else (_dm.action_name if _dm.action_name != "" else "Bare Hands")
			defend_entry = {"item_name": _dname, "mod": _dm}
		var defend_mod: ActionModifier = defend_entry["mod"] as ActionModifier
		var weapon_name: String = defend_entry["item_name"]
		log_message.emit("  %s defends with [i]%s[/i] (Tier %d)" % [
			defender.data.combatant_name, weapon_name, _effective_tier(defender)
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
		# Negation defense riders: stance_flat (Stance only) + guard_aspect_all
		# (+N Negation-size dice on every pool — added, so pool widens by N too).
		var guard_flat := CombatMath.guard_flat_bonus(defender, target_pool)
		var bonus_dice := CombatMath.guard_bonus_dice(defender)
		if guard_flat > 0:
			log_message.emit("  [color=cyan]Stance discipline: +%d Guard.[/color]" % guard_flat)
		if bonus_dice > 0:
			log_message.emit("  [color=cyan]Iron guard: +%d Negation die to the pool.[/color]" % bonus_dice)
		var def_result := RollEngine.resolve(
				_effective_tier(defender) + bonus_dice, defensive_size,
				maxi(1, _defense_keep_grade(defender, target_pool) + keep_debuff),
				defend_mod.flat_bonus + guard_flat,
				sd_adv, 0,
				_stat_size(defender, "negation") if bonus_dice > 0 else 0, bonus_dice
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
	# Magic Shield (guard-shaped interrupt, third dispatch path beside on_massive_wound /
	# on_burnout): fires only when the player's guard WOULD break, before the breach
	# commits. One prompt per attack; the shield may still fail (tension intended).
	# Direct-wound effects never pass through here, so they can't be shielded.
	if defender_is_player and (attack_result.total as int) >= current_guard:
		current_guard = await _try_magic_shield(
			defender, defender_ei, target_pool, attack_result.total as int, current_guard)
	var force_breach := _debug_lethal and attacker_is_player and not defender_is_player
	# Typed context for this attack pass; carries did_breach (Phase 1) and becomes the surface the
	# discipline effect handlers read/mutate in Phase 2.
	var ctx := AttackContext.new()
	ctx.attacker_state = attacker
	ctx.defender_state = defender
	ctx.defender_index = defender_ei
	ctx.attacker_is_player = attacker_is_player
	ctx.target_pool = target_pool
	ctx.attack_total = attack_result.total as int
	ctx.guard_value = current_guard
	var wounds_dealt := 0
	if (attack_result.total as int) >= current_guard or force_breach:
		ctx.did_breach = true
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
		ctx.is_massive = massive
		ctx.wounds_pending = wounds_pending
		# Discipline wound modifiers (e.g. Hex amplification). Player-on-enemy breaches only.
		if attacker_is_player and not defender_is_player:
			for st in defender.active_statuses.duplicate():
				var wh: CombatEffect = EffectRegistry.get_handler(st.status_id)
				if wh != null:
					wounds_pending += wh.on_wound_calc(st, ctx)
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
		wounds_dealt = wounds
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

		wounds_changed.emit(defender_is_player, defender_ei, defender.current_wounds, defender.max_wounds, false)

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

	# Discipline post-attack hooks (e.g. Time Lock armed→frozen). Player-on-enemy attacks only.
	# Echoes and MD explosions route here too (attacker_is_player=true) — intended.
	if attacker_is_player and not defender_is_player:
		for st in defender.active_statuses.duplicate():
			var ph: CombatEffect = EffectRegistry.get_handler(st.status_id)
			if ph != null:
				ph.on_player_attack_resolved(st, ctx)

	attack_resolved.emit(
		attacker_is_player, enemy_index, target_pool,
		ctx.did_breach, ctx.is_massive, wounds_dealt, defender.is_defeated
	)


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

# --- Status system helpers (Group A) — logic in combat/StatusOps.gd ---
# Thin wrappers preserve signatures + the contract-test surface. _tick_statuses emits the
# log lines StatusOps.tick returns. _process_statuses_hook (awaits the echo) stays below.

func _add_status(state: CombatantState, status: CombatStatus) -> void:
	StatusOps.add(state, status)

func _remove_status(state: CombatantState, status_id: String) -> void:
	StatusOps.remove(state, status_id)

func _has_status(state: CombatantState, status_id: String) -> bool:
	return StatusOps.has(state, status_id)

func _get_status(state: CombatantState, status_id: String) -> CombatStatus:
	return StatusOps.get_status(state, status_id)

func _tick_statuses(state: CombatantState) -> void:
	for msg in StatusOps.tick(state):
		log_message.emit(msg)

# --- End status system helpers ---

# --- Interrupt system helpers (Group A3) — logic in combat/InterruptOps.gd ---
# Awaited resolvers (_resolve_interrupt, _resolve_meat_for_the_grinder, _try_prevent_burnout)
# stay in CombatManager; only the pure bookkeeping is delegated.

func _register_interrupt(state: CombatantState, handler: InterruptHandler) -> void:
	InterruptOps.register(state, handler)


func _find_interrupts(state: CombatantState, trigger: String) -> Array[InterruptHandler]:
	return InterruptOps.find(state, trigger)


func _consume_interrupt_charge(handler: InterruptHandler) -> void:
	InterruptOps.consume_charge(handler)


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


## Magic Shield (ing_resolve L2+) guard-break interrupt. Awaited inside _resolve_attack
## when the player's guard would break. Guard-shaped: returns the (possibly reinforced)
## guard value — contrast _resolve_interrupt (wounds-shaped) and _try_prevent_burnout
## (bool-shaped). Only the player can hold a shield handler; enemies never reach this.
func _try_magic_shield(
		state: CombatantState, enemy_index: int, pool: String, incoming: int, guard: int
) -> int:
	var handlers := _find_interrupts(state, "on_guard_break")
	if handlers.is_empty():
		return guard
	var handler := handlers[0]  # priority-sorted; only the shield uses this trigger
	var dice_count := CombatMath.magic_shield_dice(state)
	if dice_count <= 0:
		return guard
	var die_size := _stat_size(state, "ingenuity")
	player_shield_opportunity.emit(handler.charges, incoming, guard, dice_count, die_size)
	var use_charge: bool = await _shield_decision_gate
	if not use_charge:
		return guard
	_consume_interrupt_charge(handler)
	var added := 0
	for d in RollEngine.roll_dice(dice_count, die_size):
		added += d as int
	var new_guard := guard + added
	state.set_guard_val(pool, new_guard)
	guard_changed.emit(state == _player, enemy_index, pool, new_guard)
	if new_guard > incoming:
		log_message.emit("  [color=cyan]Magic Shield! +%d Guard (%dd%d) — the wall holds.[/color]" % [
			added, dice_count, die_size])
	else:
		log_message.emit("  [color=cyan]Magic Shield! +%d Guard (%dd%d) — not enough![/color]" % [
			added, dice_count, die_size])
	return new_guard


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
	# Collection + filtering orchestration stays here (reads PlayerProgression.node_levels +
	# round-scoped breach state via `outcome`); the per-effect predicates and dispatch live in
	# combat/StatusOps.gd.
	var effects: Array[SpellOutcomeEffect] = []
	for node in PlayerProgression.node_levels:
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var level := PlayerProgression.node_levels[node] as int
		for i in range(mini(level, nd.levels_data.size())):
			for effect in nd.levels_data[i].outcome_effects:
				if StatusOps.outcome_matches(effect, spell):
					effects.append(effect)

	for effect in effects:
		if not StatusOps.outcome_trigger_fires(effect, outcome):
			continue
		if not StatusOps.outcome_condition_holds(effect, caster_state, target_state, outcome):
			continue
		StatusOps.dispatch_outcome_effect(effect, caster_state, target_state, outcome)

# --- End spell outcome effect helpers ---

# --- Mind Detonation helpers (Group C1) ---

## Collects pool/keep/flat SpellBonusEffect bonuses for a spell across all purchased nodes.
## Shared by _resolve_round_spell (cast path) and Disciplines.detonate_mind_bomb (explosion path).
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


# --- Discipline helpers — logic in combat/Disciplines.gd (Phase 4) ---
# Thin wrappers over the Disciplines module; round-loop call sites + contract tests unchanged.
# The Time Lock armed→frozen transition and frozen-guard restore are NOT inline in the spine:
# they live in TimeLockEffect (combat/effects/), fired via generic EffectRegistry dispatch from
# _resolve_attack (on_player_attack_resolved) and _end_of_round (on_guard_reset).

func _check_mind_detonation(enemy: CombatantState, enemy_index: int) -> void:
	await Disciplines.check_mind_detonation(enemy, enemy_index)


func _cast_mind_rend(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	Disciplines.cast_mind_rend(enemy, enemy_index, attack_result)


func _cast_time_lock(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	Disciplines.cast_time_lock(enemy, enemy_index, attack_result)


func _resolve_spell_echo(status: CombatStatus, state: CombatantState) -> void:
	await Disciplines.resolve_spell_echo(status, state)

func _process_statuses_hook(
		hook: String,
		state: CombatantState,
		context: Dictionary = {}
) -> void:
	## Dispatches status effects for the given hook via the EffectRegistry (Phase 2). Logic lives in
	## the CombatEffect handlers, never in CombatStatus. Only end_of_round currently drives async work
	## (Echo); start_of_round / on_breach have no handler methods, so they no-op as before.
	## .duplicate() guards against a handler adding/removing statuses mid-loop.
	for status in state.active_statuses.duplicate():
		var handler: CombatEffect = EffectRegistry.get_handler(status.status_id)
		if handler == null:
			continue
		if hook == "end_of_round":
			await handler.on_end_of_round(status, state)


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
		e.reset_guard()
		for pool in POOL_NAMES:
			guard_changed.emit(false, i, pool, 0)
		# Discipline guard-reset hooks (e.g. Time Lock frozen-pool restore). Fire after the reset;
		# a handler restores + marks-rolled any pool it wants preserved this round.
		for st in e.active_statuses.duplicate():
			var gh: CombatEffect = EffectRegistry.get_handler(st.status_id)
			if gh != null:
				gh.on_guard_reset(st, e, i)

	# Training room: the dummy is patched back to full between rounds.
	# is_initial=true on the emit = display sync only (no hurt/die reaction).
	if DungeonManager.training_mode:
		for i in _enemies.size():
			var e: CombatantState = _enemies[i]
			if not e.is_defeated and e.current_wounds > 0:
				e.current_wounds = 0
				wounds_changed.emit(false, i, 0, e.max_wounds, true)
				log_message.emit("[color=gray]%s creaks back into shape.[/color]" % e.data.combatant_name)

	await get_tree().create_timer(0.8).timeout


# The pure computations below live in combat/CombatMath.gd (Phase 2 of the refactor). These
# thin wrappers keep the original signatures/call sites and supply CombatManager context
# (player identity, chosen cast weapon). See CombatMath for the logic + doc comments.

func _tier_wound_bonus(tier: int) -> int:
	return CombatMath.tier_wound_bonus(tier)


func _wounds_node_bonus(state: CombatantState) -> int:
	return CombatMath.wounds_node_bonus(state)


func _physical_keep_grade(state: CombatantState) -> int:
	return CombatMath.physical_keep_grade(state)


func _meat_grinder_charges(state: CombatantState) -> int:
	return CombatMath.meat_grinder_charges(state)


func _get_pool_size(state: CombatantState, pool: String) -> int:
	return CombatMath.get_pool_size(state, pool)


func _effective_tier(state: CombatantState) -> int:
	return CombatMath.effective_tier(state)


func _attack_flat(state: CombatantState, strike_mod: ActionModifier = null, weapon: EquipmentData = null) -> int:
	return CombatMath.attack_flat(state, state == _player, strike_mod, weapon)


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


func _guard_flat(state: CombatantState) -> int:
	return CombatMath.guard_flat(state, state == _player)


func _pool_bonus(state: CombatantState, action_key: String = "strike", strike_mod: ActionModifier = null) -> int:
	return CombatMath.pool_bonus(state, state == _player, action_key, strike_mod)


func _get_action_modifier(state: CombatantState, action_key: String) -> ActionModifier:
	return CombatMath.get_action_modifier(state, action_key, state == _player)


func _get_cast_modifier(state: CombatantState) -> ActionModifier:
	return CombatMath.get_cast_modifier(state, _player_cast_weapon)


func _derived_modifier(mod: ActionModifier, parent: ActionModifier) -> ActionModifier:
	return CombatMath.derived_modifier(mod, parent)


func _get_all_action_modifiers(state: CombatantState) -> Array:
	return CombatMath.get_all_action_modifiers(state)


func _node_effect_max(state: CombatantState, key: String) -> int:
	return CombatMath.node_effect_max(state, key)


func _node_effect_sum(state: CombatantState, key: String) -> int:
	return CombatMath.node_effect_sum(state, key)


func _node_weapon_bonus_sum(state: CombatantState, key: String, weapon_override: EquipmentData = null) -> int:
	return CombatMath.node_weapon_bonus_sum(state, key, weapon_override)


func _has_effect_type(state: CombatantState, key: String) -> bool:
	return CombatMath.has_effect_type(state, key)


func _stat_size(state: CombatantState, stat: String) -> int:
	return CombatMath.stat_size(state, stat)


func _training_keep_grade(state: CombatantState) -> int:
	return CombatMath.training_keep_grade(state)


func _defense_keep_grade(state: CombatantState, pool: String) -> int:
	return CombatMath.defense_keep_grade(state, pool)


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
	var tier := _effective_tier(_player)
	var die_size := _stat_size(_player, "dominion")
	var flat := _attack_flat(_player)
	return int(tier * (die_size + 1) / 2.0) + flat


# ── Formatting helpers (logic in combat/CombatMath.gd) ────────────────────────

func _attacker_weapon_name(state: CombatantState) -> String:
	return CombatMath.attacker_weapon_name(state, state == _player)


func _fmt_attack(name: String, r: Dictionary, weapon_name: String = "") -> String:
	return CombatMath.fmt_attack(name, r, weapon_name)


func _fmt_spell_attack(name: String, r: Dictionary) -> String:
	return CombatMath.fmt_spell_attack(name, r)


func _fmt_speed(name: String, total: int, vt: int, fast: bool) -> String:
	return CombatMath.fmt_speed(name, total, vt, fast)


func _fmt_defense(name: String, r: Dictionary, pool_label: String) -> String:
	return CombatMath.fmt_defense(name, r, pool_label)


func _arr(a: Array) -> String:
	return CombatMath.arr(a)
