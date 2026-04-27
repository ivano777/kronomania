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

## Emitted whenever the player's Fervor state changes (initial emit at combat start).
signal fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool)

## Emitted when a Massive Wound against the player can be degraded (charges_left > 0).
signal player_massive_incoming(charges_left: int)
## Internal coroutine gate: resolved when the player decides whether to spend a charge.
signal _massive_decision_gate(use_charge: bool)


# ── Runtime state ─────────────────────────────────────────────────────────────

class CombatantState:
	var data: CombatantData
	var current_wounds: int = 0
	var max_wounds: int     = 3
	var is_defeated: bool   = false
	var weapon_override: EquipmentData = null  # set by debug tools; null = use data.equipped_weapon
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
	var stamina_degrade_charges: int = 0  # Meat for the Grinder: charges to degrade Massive Wounds
	var space_domination_active: bool = false  # Melee L2: Advantage on first Stamina guard roll each combat

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
		stamina_degrade_charges = 0
		space_domination_active = false
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

## True only while awaiting the player's action input.
var _waiting_for_player: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

## Call from BattleScene._ready() to initialise and begin combat.
## enemies_data: Array[CombatantData] — one entry per enemy (parallel if >1).
func start_combat(player_data: CombatantData, enemies_data: Array) -> void:
	_player = CombatantState.new()
	_player.init(player_data)
	if PlayerProgression.equipped_weapon != null:
		var old_fort: int = player_data.equipped_weapon.max_wounds_bonus if player_data.equipped_weapon else 0
		_player.max_wounds += PlayerProgression.equipped_weapon.max_wounds_bonus - old_fort
		_player.weapon_override = PlayerProgression.equipped_weapon
	_player.node_levels = PlayerProgression.node_levels.duplicate()
	_player.tier_override = PlayerProgression.get_tier()
	_player.max_wounds += _tier_wound_bonus(_player.tier_override)
	_player.max_wounds += _wounds_node_bonus(_player)
	_player.stamina_degrade_charges = _meat_grinder_charges(_player)
	_player.space_domination_active = _has_effect_type(_player, "space_domination")
	if DungeonManager.was_last_fight_chained():
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
func player_chose_strike(net_advantage: int = 0, target_pool: String = "stance", brutal_trade: bool = false, target_index: int = 0) -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
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
		player_magic_available.emit(_player.known_cantrips.size() > 0, false)
		player_action_required.emit()
		return
	_waiting_for_player = false
	_resolve_round_spell(spell, target_index)


## Called by RoundHUD (via BattleScene) when the player resolves a Meat for the Grinder prompt.
func player_chose_degrade_wound(use_charge: bool) -> void:
	_massive_decision_gate.emit(use_charge)


## Debug only — override Fervor state at runtime.
func debug_set_fervor(new_fervor_size: int, burned_out: bool) -> void:
	if _player:
		_player.fervor_size = new_fervor_size
		_player.is_burned_out = burned_out
		fervor_changed.emit(true, _player.fervor_size, _stat_size(_player, "ingenuity"), burned_out)


# ── Private — round flow ──────────────────────────────────────────────────────

func _begin_round() -> void:
	_round += 1

	# All guard pools reset at the start of each new round (rules: defense-and-guard.md).
	_player.reset_guard()
	for pool in POOL_NAMES:
		guard_changed.emit(true, -1, pool, 0)
	for i in _enemies.size():
		_enemies[i].reset_guard()
		for pool in POOL_NAMES:
			guard_changed.emit(false, i, pool, 0)

	round_started.emit(_round)
	log_message.emit("")
	log_message.emit("[b]═══ Round %d ═══[/b]" % _round)
	phase_changed.emit("Choose your action")

	_waiting_for_player = true
	player_magic_available.emit(
		_player.known_cantrips.size() > 0,
		_player.known_spells.size() > 0 and not _player.is_burned_out
	)
	player_action_required.emit()


# Coroutine: physical Strike — resolves one full round then loops back.
func _resolve_round(net_advantage: int = 0, target_pool: String = "stance", brutal_trade: bool = false, target_index: int = 0) -> void:
	phase_changed.emit("Resolving…")
	var target: CombatantState = _enemies[target_index]
	log_message.emit("Both combatants declare Strike. Targeting: %s." % target.data.combatant_name)

	if brutal_trade:
		log_message.emit("  [color=yellow]Brutal Trade: VT −5, Flat +5.[/color]")

	# ── Roll player attack pool ────────────────────────────────────────────
	var keep_grade := _physical_keep_grade(_player) + _node_weapon_bonus_sum(_player, "weapon_keep")
	var brutal_flat := 5 if brutal_trade else 0

	var earthshatter_size := 0
	if target_pool == "stance" and _node_effect_max(_player, "earthshatter") > 0:
		earthshatter_size = _stat_size(_player, "dominion")
		log_message.emit("  [color=cyan]Earthshatter![/color] Post-keep Dominion d%d added." % earthshatter_size)

	var p_atk := RollEngine.resolve(
		_effective_tier(_player), _stat_size(_player, "dominion"), keep_grade,
		_attack_flat(_player) + brutal_flat,
		net_advantage + _pool_bonus(_player),
		0, 0, 0, earthshatter_size
	)
	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk))
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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	if not target.is_defeated:
		await _resolve_attack(true, target_index, p_atk, target_pool)

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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Next round ─────────────────────────────────────────────────────────
	await get_tree().create_timer(0.8).timeout
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
		_effective_tier(_player), _stat_size(_player, "ingenuity"), _training_keep_grade(_player),
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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	if not target.is_defeated:
		await _resolve_attack(true, target_index, p_atk, spell.target_pool)

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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	await get_tree().create_timer(0.8).timeout
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

	# Collect school bonus effects for spells matching any of this spell's tags.
	var spell_pool_bonus := 0
	var spell_keep_bonus := 0
	for node in _player.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = _player.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			for be in nd.levels_data[i].bonus_effects:
				if spell.tags.has(be.tag):
					if be.bonus_type == "pool":
						spell_pool_bonus += be.value
					elif be.bonus_type == "keep":
						spell_keep_bonus += be.value
	if spell_pool_bonus > 0 or spell_keep_bonus > 0:
		var parts: Array = []
		if spell_pool_bonus > 0:
			parts.append("+%d pool" % spell_pool_bonus)
		if spell_keep_bonus > 0:
			parts.append("+%d keep" % spell_keep_bonus)
		log_message.emit("  [color=yellow]School bonus: %s[/color]" % ", ".join(parts))

	var p_atk := RollEngine.resolve(
		_effective_tier(_player) + spell_pool_bonus,
		_stat_size(_player, "ingenuity"),
		_training_keep_grade(_player) + spell_keep_bonus,
		spell.flat_bonus, _pool_bonus(_player), _player.fervor_size,
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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
			)
			log_message.emit(_fmt_attack(e.data.combatant_name, e_atk))
			var e_pool := spell.target_pool if i == target_index else "stance"
			await _resolve_attack(false, i, e_atk, e_pool)
			if _player.is_defeated:
				_end_combat()
				return

	# ── Phase 2: Player attacks chosen target ──────────────────────────────
	if not target.is_defeated:
		await _resolve_attack(true, target_index, p_atk, spell.target_pool)

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
				_effective_tier(e), _stat_size(e, "dominion"), _training_keep_grade(e), _attack_flat(e)
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
		_escalate_fervor(_player, escalation_steps)

	await get_tree().create_timer(0.8).timeout
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
	if not defender.is_pool_rolled(target_pool):
		var sd_adv := 0
		if defender_is_player and target_pool == "stamina" and _player.space_domination_active:
			sd_adv = 1
			_player.space_domination_active = false
			log_message.emit("  [color=cyan]Space Domination: Advantage on Stamina guard![/color]")
		var def_result := RollEngine.resolve(
				_effective_tier(defender), defensive_size,
				_training_keep_grade(defender), _guard_flat(defender),
				sd_adv
			)
		var guard_val: int = def_result.total as int
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
	if (attack_result.total as int) >= current_guard:
		var massive := RollEngine.is_massive(
			attack_result.total as int, current_guard, defensive_size
		)
		var wounds := 2 if massive else 1
		# Meat for the Grinder: player can spend a charge to degrade Massive → 1 Wound.
		if wounds == 2 and not attacker_is_player and _player.stamina_degrade_charges > 0:
			player_massive_incoming.emit(_player.stamina_degrade_charges)
			var use_charge: bool = await _massive_decision_gate
			if use_charge:
				_player.stamina_degrade_charges -= 1
				wounds = 1
				log_message.emit("  [color=lime]Meat for the Grinder! Massive Wound degraded to 1 Wound.[/color]")
		defender.current_wounds += wounds

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
		log_message.emit(
			"  Guard holds. %d absorbed, %d remaining." % [
				attack_result.total as int, remaining
			]
		)

	# Publish final guard value after consumption.
	guard_changed.emit(defender_is_player, defender_ei, target_pool, defender.get_guard(target_pool))


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


## Effective Tier: tier_override if set (player Tier from Constellation), else data.tier,
## then capped by equipment Potency.
func _effective_tier(state: CombatantState) -> int:
	var base := state.tier_override if state.tier_override > 0 else state.data.tier
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return mini(base, w.potency) if w else base


## Flat bonus applied to attack rolls: weapon Forging + matching weapon_flat node bonuses.
func _attack_flat(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return (w.flat_attack_bonus if w else 0) + _node_weapon_bonus_sum(state, "weapon_flat")


## Flat bonus applied to defense rolls from equipped weapon (Warding).
func _guard_flat(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.flat_guard_bonus if w else 0


## Pool size modifier from equipped weapon (Surge/Drain).
func _pool_bonus(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.pool_bonus if w else 0


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


## Steps Fervor up by `steps` track positions. Triggers Burnout if escalation
## would push the index past the cap's slot in FERVOR_TRACK — including the
## d10/d10 ceiling case where new_size == cap but steps remain (magic/fervor.md).
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
	var clamped_idx: int = mini(raw_new_idx, FERVOR_TRACK.size() - 1)
	var new_size: int = FERVOR_TRACK[clamped_idx]
	if new_size != prev_size:
		log_message.emit("  [color=magenta]Fervor escalates: d%d → d%d[/color]" % [prev_size, new_size])
	else:
		log_message.emit("  [color=magenta]Fervor at maximum track position (d%d).[/color]" % new_size)
	if raw_new_idx > cap_idx and not state.is_burned_out:
		state.is_burned_out = true
		log_message.emit("[color=orange][b]BURNOUT![/b] Fervor surged beyond control. True spells blocked until next combat.[/color]")
	state.fervor_size = mini(new_size, cap)
	fervor_changed.emit(state == _player, state.fervor_size, cap, state.is_burned_out)


## Debug only — swap the player's weapon at runtime without restarting combat.
func debug_set_player_weapon(weapon: EquipmentData) -> void:
	if _player:
		_player.weapon_override = weapon


# ── Formatting helpers ────────────────────────────────────────────────────────

func _fmt_attack(name: String, r: Dictionary) -> String:
	var desperation: bool = r.desperation
	var prefix := "[b][DESPERATION][/b] " if desperation else ""
	var flat: int = r.flat as int
	var flat_part := " + %d flat" % flat if flat != 0 else ""
	return "  %s%s attacks: rolled %s, kept %s%s → [b]%d[/b]" % [
		prefix, name, _arr(r.dice as Array), _arr(r.kept as Array), flat_part, r.total as int
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
