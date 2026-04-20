# CombatManager — combat state machine for a 1v1 duel.
#
# Flow per round:
#   _begin_round  →  (player presses Strike / Cantrip / Spell)  →  _resolve_round_*
#   _resolve_round_* rolls both attacks, checks VT, resolves Fast then Slow,
#   applies wounds, checks defeat, then loops back to _begin_round.
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
signal wounds_changed(is_player: bool, current: int, max_wounds: int)

## Emitted after a defender's guard pool changes (roll, consumption, or reset).
## is_player: true = player's guard; false = enemy's guard.
## pool: "stance" | "resolve" | "stamina"
signal guard_changed(is_player: bool, pool: String, guard_value: int)

## Emitted once combat ends.
signal combat_ended(winner_name: String)

## Emitted when the player must choose their action.
signal player_action_required()

## Emitted before player_action_required to inform the UI which magic actions are available.
signal player_magic_available(can_cantrip: bool, can_cast_spell: bool)

## Emitted whenever the player's Fervor state changes (initial emit at combat start).
signal fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool)


# ── Runtime state ─────────────────────────────────────────────────────────────

class CombatantState:
	var data: CombatantData
	var current_wounds: int = 0
	var max_wounds: int     = 3
	var is_defeated: bool   = false
	var weapon_override: EquipmentData = null  # set by debug tools; null = use data.equipped_weapon
	var unlocked_nodes: Array[NodeData] = []   # runtime copy; for player, overridden from PlayerProgression
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

	func init(d: CombatantData) -> void:
		data = d
		current_wounds = 0
		max_wounds = d.max_wounds + (d.equipped_weapon.max_wounds_bonus if d.equipped_weapon else 0)
		is_defeated = false
		unlocked_nodes.clear()
		for n in d.starting_nodes:
			if n is NodeData:
				unlocked_nodes.append(n as NodeData)
		fervor_size = 4
		is_burned_out = false
		has_minor_studies = false
		has_spellcasting = false
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
var _enemy:  CombatantState
var _round:  int = 0

## True only while awaiting the player's action input.
var _waiting_for_player: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

## Call from BattleScene._ready() to initialise and begin combat.
func start_combat(player_data: CombatantData, enemy_data: CombatantData) -> void:
	_player = CombatantState.new()
	_player.init(player_data)
	_player.unlocked_nodes = PlayerProgression.unlocked_nodes.duplicate()
	_player.tier_override = PlayerProgression.get_tier()
	_player.has_minor_studies = _player.unlocked_nodes.any(func(n: NodeData): return n.effect_type == "minor_studies")
	_player.has_spellcasting  = _player.unlocked_nodes.any(func(n: NodeData): return n.effect_type == "spellcasting")
	_player.fervor_size = 4
	_player.is_burned_out = false
	_enemy = CombatantState.new()
	_enemy.init(enemy_data)
	_round = 0
	_waiting_for_player = false

	log_message.emit("[b]Combat begins![/b]")
	log_message.emit(
		"Encounter VT: %d\n  %s: off d%d | Stance d%d / Resolve d%d / Stamina d%d\n  %s: off d%d | Stance d%d / Resolve d%d / Stamina d%d" % [
			enemy_data.velocity_threshold,
			player_data.combatant_name,
			player_data.dominion_size, player_data.negation_size,
			player_data.ingenuity_size, player_data.dominion_size,
			enemy_data.combatant_name,
			enemy_data.dominion_size, enemy_data.negation_size,
			enemy_data.ingenuity_size, enemy_data.dominion_size,
		]
	)

	# Emit initial Fervor state so HUD is initialised before round 1.
	fervor_changed.emit(true, _player.fervor_size, _player.data.ingenuity_size, _player.is_burned_out)

	_begin_round()


## Called by BattleScene when the player presses Strike.
## net_advantage : positive = Advantage dice, negative = Disadvantage dice.
## target_pool   : which defense pool the attack pressures ("stance" | "resolve" | "stamina").
func player_chose_strike(net_advantage: int = 0, target_pool: String = "stance") -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
	_resolve_round(net_advantage, target_pool)


## Called by BattleScene when the player presses Cantrip.
## Ingenuity-based attack; no Fervor cost; available during Burnout.
func player_chose_cantrip(target_pool: String = "resolve") -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
	_resolve_round_cantrip(target_pool)


## Called by BattleScene when the player presses Cast Spell.
## Ingenuity-based attack with a real Fervor die; blocked during Burnout.
func player_chose_spell(net_advantage: int = 0, target_pool: String = "resolve") -> void:
	if not _waiting_for_player:
		return
	if _player.is_burned_out:
		log_message.emit("[color=orange]Burnout! True spells are blocked — choose Strike or Cantrip.[/color]")
		player_magic_available.emit(_player.has_minor_studies, false)
		player_action_required.emit()
		return
	_waiting_for_player = false
	_resolve_round_spell(net_advantage, target_pool)


## Debug only — override Fervor state at runtime.
func debug_set_fervor(new_fervor_size: int, burned_out: bool) -> void:
	if _player:
		_player.fervor_size = new_fervor_size
		_player.is_burned_out = burned_out
		fervor_changed.emit(true, _player.fervor_size, _player.data.ingenuity_size, burned_out)


# ── Private — round flow ──────────────────────────────────────────────────────

func _begin_round() -> void:
	_round += 1

	# All guard pools reset at the start of each new round (rules: defense-and-guard.md).
	_player.reset_guard()
	_enemy.reset_guard()
	for pool in POOL_NAMES:
		guard_changed.emit(true,  pool, 0)
		guard_changed.emit(false, pool, 0)

	round_started.emit(_round)
	log_message.emit("")
	log_message.emit("[b]═══ Round %d ═══[/b]" % _round)
	phase_changed.emit("Choose your action")

	_waiting_for_player = true
	player_magic_available.emit(
		_player.has_minor_studies,
		_player.has_spellcasting and not _player.is_burned_out
	)
	player_action_required.emit()


# Coroutine: physical Strike — resolves one full round then loops back.
func _resolve_round(net_advantage: int = 0, target_pool: String = "stance") -> void:
	phase_changed.emit("Resolving…")
	log_message.emit("Both combatants declare Strike.")

	# ── Roll both attack pools ─────────────────────────────────────────────
	var p_atk := RollEngine.resolve(
		_effective_tier(_player), _player.data.dominion_size, _training_keep_grade(_player),
		_attack_flat(_player),
		net_advantage + _pool_bonus(_player)
	)
	var e_atk := RollEngine.resolve(
		_effective_tier(_enemy), _enemy.data.dominion_size, _training_keep_grade(_enemy),
		_attack_flat(_enemy)
	)

	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk))
	log_message.emit(_fmt_attack(_enemy.data.combatant_name, e_atk))

	# ── VT check ──────────────────────────────────────────────────────────
	# VT is a static enemy property. Only the player's roll is compared to it.
	var encounter_vt: int = _enemy.data.velocity_threshold
	var p_fast := RollEngine.is_fast(p_atk.total as int, encounter_vt)

	log_message.emit(_fmt_speed(_player.data.combatant_name, p_atk.total as int, encounter_vt, p_fast))

	# ── Determine resolution order ─────────────────────────────────────────
	var player_first: bool = p_fast
	if p_fast:
		phase_changed.emit("Fast Phase — Player acts first")
	else:
		log_message.emit("%s is Slow — %s acts first." % [_player.data.combatant_name, _enemy.data.combatant_name])
		phase_changed.emit("Slow Phase — Enemy acts first")

	# ── First attacker ─────────────────────────────────────────────────────
	_resolve_attack(player_first, p_atk if player_first else e_atk, target_pool)

	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	# ── Second attacker ────────────────────────────────────────────────────
	var second_is_player := not player_first
	phase_changed.emit("Slow Phase" if p_fast else "Fast Phase (2nd)")
	_resolve_attack(second_is_player, p_atk if second_is_player else e_atk, target_pool)

	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	# ── Next round ─────────────────────────────────────────────────────────
	await get_tree().create_timer(0.8).timeout
	_begin_round()


# Coroutine: Cantrip — Ingenuity-based attack, no Fervor die, available during Burnout.
func _resolve_round_cantrip(target_pool: String = "resolve") -> void:
	phase_changed.emit("Resolving…")
	log_message.emit("%s channels a cantrip (Ingenuity d%d)." % [
		_player.data.combatant_name, _player.data.ingenuity_size
	])

	var p_atk := RollEngine.resolve(
		_effective_tier(_player), _player.data.ingenuity_size, _training_keep_grade(_player),
		0, _pool_bonus(_player)
	)
	var e_atk := RollEngine.resolve(
		_effective_tier(_enemy), _enemy.data.dominion_size, _training_keep_grade(_enemy),
		_attack_flat(_enemy)
	)

	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk) + " [cantrip]")
	log_message.emit(_fmt_attack(_enemy.data.combatant_name, e_atk))

	var encounter_vt: int = _enemy.data.velocity_threshold
	var p_fast := RollEngine.is_fast(p_atk.total as int, encounter_vt)
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_atk.total as int, encounter_vt, p_fast))

	var player_first: bool = p_fast
	if p_fast:
		phase_changed.emit("Fast Phase — Player acts first")
	else:
		log_message.emit("%s is Slow — %s acts first." % [_player.data.combatant_name, _enemy.data.combatant_name])
		phase_changed.emit("Slow Phase — Enemy acts first")

	_resolve_attack(player_first, p_atk if player_first else e_atk, target_pool)
	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	var second_is_player := not player_first
	phase_changed.emit("Slow Phase" if p_fast else "Fast Phase (2nd)")
	_resolve_attack(second_is_player, p_atk if second_is_player else e_atk, target_pool)
	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	await get_tree().create_timer(0.8).timeout
	_begin_round()


# Coroutine: True Spell — Ingenuity + real Fervor die; escalates Fervor on max-roll.
func _resolve_round_spell(net_advantage: int = 0, target_pool: String = "resolve") -> void:
	phase_changed.emit("Resolving…")
	log_message.emit("%s casts a true spell (Ingenuity d%d + Fervor d%d)." % [
		_player.data.combatant_name, _player.data.ingenuity_size, _player.fervor_size
	])

	var p_atk := RollEngine.resolve(
		_effective_tier(_player), _player.data.ingenuity_size, _training_keep_grade(_player),
		0, net_advantage + _pool_bonus(_player), _player.fervor_size
	)
	var e_atk := RollEngine.resolve(
		_effective_tier(_enemy), _enemy.data.dominion_size, _training_keep_grade(_enemy),
		_attack_flat(_enemy)
	)

	log_message.emit(_fmt_spell_attack(_player.data.combatant_name, p_atk))
	log_message.emit(_fmt_attack(_enemy.data.combatant_name, e_atk))

	var encounter_vt: int = _enemy.data.velocity_threshold
	var p_fast := RollEngine.is_fast(p_atk.total as int, encounter_vt)
	log_message.emit(_fmt_speed(_player.data.combatant_name, p_atk.total as int, encounter_vt, p_fast))

	var player_first: bool = p_fast
	if p_fast:
		phase_changed.emit("Fast Phase — Player acts first")
	else:
		log_message.emit("%s is Slow — %s acts first." % [_player.data.combatant_name, _enemy.data.combatant_name])
		phase_changed.emit("Slow Phase — Enemy acts first")

	_resolve_attack(player_first, p_atk if player_first else e_atk, target_pool)
	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	var second_is_player := not player_first
	phase_changed.emit("Slow Phase" if p_fast else "Fast Phase (2nd)")
	_resolve_attack(second_is_player, p_atk if second_is_player else e_atk, target_pool)
	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	# Post-resolution: check Fervor escalation (rules: magic/fervor.md).
	if p_atk.fervor_maxed as bool:
		_escalate_fervor(_player, 1)

	await get_tree().create_timer(0.8).timeout
	_begin_round()


# Resolves a single attack against the specified defense pool.
# attacker_is_player : who is swinging
# attack_result      : Dictionary from RollEngine.resolve()
# target_pool        : which pool the defender uses ("stance" | "resolve" | "stamina")
func _resolve_attack(attacker_is_player: bool, attack_result: Dictionary, target_pool: String = "stance") -> void:
	var attacker: CombatantState = _player if attacker_is_player else _enemy
	var defender: CombatantState = _enemy  if attacker_is_player else _player
	var defender_is_player := not attacker_is_player
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
		var def_result := RollEngine.resolve(
				_effective_tier(defender), defensive_size,
				_training_keep_grade(defender), _guard_flat(defender)
			)
		var guard_val: int = def_result.total as int
		defender.set_guard_val(target_pool, guard_val)
		defender.set_pool_rolled(target_pool, true)
		guard_changed.emit(defender_is_player, target_pool, guard_val)
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

		wounds_changed.emit(defender_is_player, defender.current_wounds, defender.max_wounds)

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
	guard_changed.emit(defender_is_player, target_pool, defender.get_guard(target_pool))


func _end_combat() -> void:
	var winner: String
	if _player.is_defeated:
		winner = _enemy.data.combatant_name
		log_message.emit("")
		log_message.emit("[color=red][b]DEFEAT — %s wins.[/b][/color]" % winner)
	else:
		winner = _player.data.combatant_name
		log_message.emit("")
		log_message.emit("[color=lime][b]VICTORY — %s wins![/b][/color]" % winner)

	phase_changed.emit("Combat Over")
	combat_ended.emit(winner)


# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns the die size for the given defense pool on a combatant.
## Stance = Negation, Resolve = Ingenuity, Stamina = Dominion (defensive expression).
func _get_pool_size(state: CombatantState, pool: String) -> int:
	match pool:
		"stance":  return state.data.negation_size
		"resolve": return state.data.ingenuity_size
		"stamina": return state.data.dominion_size
	return state.data.negation_size


## Effective Tier: tier_override if set (player Tier from Constellation), else data.tier,
## then capped by equipment Potency.
func _effective_tier(state: CombatantState) -> int:
	var base := state.tier_override if state.tier_override > 0 else state.data.tier
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return mini(base, w.potency) if w else base


## Flat bonus applied to attack rolls from equipped weapon (Forging).
func _attack_flat(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.flat_attack_bonus if w else 0


## Flat bonus applied to defense rolls from equipped weapon (Warding).
func _guard_flat(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.flat_guard_bonus if w else 0


## Pool size modifier from equipped weapon (Surge/Drain).
func _pool_bonus(state: CombatantState) -> int:
	var w: EquipmentData = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	return w.pool_bonus if w else 0


## Returns the effective keep grade for a combatant: highest Training node value,
## or data.keep_grade as fallback when no Training node is present.
func _training_keep_grade(state: CombatantState) -> int:
	var best: int = state.data.keep_grade
	for node in state.unlocked_nodes:
		if node.effect_type == "training_keep":
			best = maxi(best, node.effect_value)
	return best


## Steps Fervor up by `steps` track positions. Triggers Burnout if new size exceeds
## the Ingenuity cap. Fervor is clamped at the cap (rules: magic/fervor.md).
func _escalate_fervor(state: CombatantState, steps: int) -> void:
	var cap: int = state.data.ingenuity_size
	var idx: int = FERVOR_TRACK.find(state.fervor_size)
	if idx == -1:
		idx = 0
	var prev_size: int = FERVOR_TRACK[idx]
	idx = mini(idx + steps, FERVOR_TRACK.size() - 1)
	var new_size: int = FERVOR_TRACK[idx]
	if new_size != prev_size:
		log_message.emit("  [color=magenta]Fervor escalates: d%d → d%d[/color]" % [prev_size, new_size])
	else:
		log_message.emit("  [color=magenta]Fervor at maximum track position (d%d).[/color]" % new_size)
	if new_size > cap and not state.is_burned_out:
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
