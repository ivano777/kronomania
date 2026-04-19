# CombatManager — combat state machine for a 1v1 duel.
#
# Flow per round:
#   _begin_round  →  (player presses Strike)  →  _resolve_round
#   _resolve_round rolls both attacks, checks VT, resolves Fast then Slow,
#   applies wounds, checks defeat, then loops back to _begin_round.
#
# All game-state signals are emitted here; UI nodes listen and update.
extends Node


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

## Emitted after a defender rolls Guard (and after it is consumed / reset).
## is_player: true = player's guard; false = enemy's guard.
signal guard_changed(is_player: bool, guard_value: int)

## Emitted once combat ends.
signal combat_ended(winner_name: String)

## Emitted when the player must choose their action.
signal player_action_required()


# ── Runtime state ─────────────────────────────────────────────────────────────

class CombatantState:
	var data: CombatantData
	var current_wounds: int  = 0
	var current_guard: int   = 0
	var stance_rolled: bool  = false  # true once Stance has been rolled this round
	var is_defeated: bool    = false

	func init(d: CombatantData) -> void:
		data = d
		current_wounds = 0
		current_guard  = 0
		stance_rolled  = false
		is_defeated    = false


var _player: CombatantState
var _enemy:  CombatantState
var _round:  int = 0

## True only while awaiting the player's Strike input.
var _waiting_for_player: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

## Call from BattleScene._ready() to initialise and begin combat.
func start_combat(player_data: CombatantData, enemy_data: CombatantData) -> void:
	_player = CombatantState.new()
	_player.init(player_data)
	_enemy = CombatantState.new()
	_enemy.init(enemy_data)
	_round = 0
	_waiting_for_player = false

	log_message.emit("[b]Combat begins![/b]")
	log_message.emit(
		"Encounter VT: %d | %s (d%d off / d%d def) vs %s (d%d off / d%d def)" % [
			enemy_data.velocity_threshold,
			player_data.combatant_name, player_data.dominion_size, player_data.negation_size,
			enemy_data.combatant_name, enemy_data.dominion_size, enemy_data.negation_size,
		]
	)
	_begin_round()


## Called by BattleScene when the player presses Strike.
func player_chose_strike() -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false
	_resolve_round()


# ── Private — round flow ──────────────────────────────────────────────────────

func _begin_round() -> void:
	_round += 1

	# Guard and roll-flag reset at the start of each new round (rules: defense-and-guard.md).
	_player.current_guard = 0
	_player.stance_rolled = false
	_enemy.current_guard  = 0
	_enemy.stance_rolled  = false
	guard_changed.emit(true,  0)
	guard_changed.emit(false, 0)

	round_started.emit(_round)
	log_message.emit("")
	log_message.emit("[b]═══ Round %d ═══[/b]" % _round)
	phase_changed.emit("Choose your action")

	_waiting_for_player = true
	player_action_required.emit()


# Coroutine: resolves one full round then loops back.
func _resolve_round() -> void:
	phase_changed.emit("Resolving…")
	log_message.emit("Both combatants declare Strike.")

	# ── Roll both attack pools ─────────────────────────────────────────────
	var p_atk := RollEngine.resolve(
		_player.data.tier, _player.data.dominion_size, _player.data.keep_grade
	)
	var e_atk := RollEngine.resolve(
		_enemy.data.tier, _enemy.data.dominion_size, _enemy.data.keep_grade
	)

	log_message.emit(_fmt_attack(_player.data.combatant_name, p_atk))
	log_message.emit(_fmt_attack(_enemy.data.combatant_name, e_atk))

	# ── VT check ──────────────────────────────────────────────────────────
	# VT is a static enemy property. Only the player's roll is compared to it.
	# The enemy's speed is encoded in the VT value itself — no roll needed.
	# Player Fast → player acts first; Player Slow → enemy acts first.
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
	_resolve_attack(player_first, p_atk if player_first else e_atk)

	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	# ── Second attacker ────────────────────────────────────────────────────
	var second_is_player := not player_first
	phase_changed.emit("Slow Phase" if p_fast else "Fast Phase (2nd)")
	_resolve_attack(second_is_player, p_atk if second_is_player else e_atk)

	if _player.is_defeated or _enemy.is_defeated:
		_end_combat()
		return

	# ── Next round ─────────────────────────────────────────────────────────
	await get_tree().create_timer(0.8).timeout
	_begin_round()


# Resolves a single attack: defender rolls Guard, wounds applied if Guard broken.
# attacker_is_player : who is swinging
# attack_result      : Dictionary from RollEngine.resolve()
func _resolve_attack(attacker_is_player: bool, attack_result: Dictionary) -> void:
	var attacker: CombatantState = _player if attacker_is_player else _enemy
	var defender: CombatantState = _enemy  if attacker_is_player else _player
	var defender_is_player := not attacker_is_player

	log_message.emit(
		"  [b]%s → %s[/b]  (attack total: %d)" % [
			attacker.data.combatant_name,
			defender.data.combatant_name,
			attack_result.total as int,
		]
	)

	# Stance may only be rolled once per round (rules: defense-and-guard.md).
	# If already rolled this round, reuse the existing Guard value.
	if not defender.stance_rolled:
		var def_result := RollEngine.resolve(
			defender.data.tier, defender.data.negation_size, defender.data.keep_grade
		)
		defender.current_guard = def_result.total as int
		defender.stance_rolled = true
		guard_changed.emit(defender_is_player, defender.current_guard)
		log_message.emit(_fmt_defense(defender.data.combatant_name, def_result))
	else:
		log_message.emit(
			"  %s Stance already active — Guard [b]%d[/b] absorbs pressure." % [
				defender.data.combatant_name, defender.current_guard
			]
		)

	# Compare: guard breached when attack_total >= guard (guard reaches 0 or below).
	if (attack_result.total as int) >= defender.current_guard:
		var massive := RollEngine.is_massive(
			attack_result.total as int, defender.current_guard, defender.data.negation_size
		)
		var wounds := 2 if massive else 1
		defender.current_wounds += wounds

		if massive:
			log_message.emit(
				"  [color=orange][b]MASSIVE![/b][/color] Overflow %d > d%d. %s suffers [b]2 Wounds[/b]!" % [
					(attack_result.total as int) - defender.current_guard,
					defender.data.negation_size,
					defender.data.combatant_name,
				]
			)
		else:
			log_message.emit(
				"  Guard broken! %s suffers [b]1 Wound[/b]. (%d/%d)" % [
					defender.data.combatant_name,
					defender.current_wounds,
					defender.data.max_wounds,
				]
			)

		wounds_changed.emit(defender_is_player, defender.current_wounds, defender.data.max_wounds)

		if defender.current_wounds >= defender.data.max_wounds:
			defender.is_defeated = true
			log_message.emit(
				"  [color=red][b]%s is DEFEATED![/b][/color]" % defender.data.combatant_name
			)
	else:
		var remaining: int = defender.current_guard - (attack_result.total as int)
		log_message.emit(
			"  Guard holds. %d absorbed, %d remaining." % [
				attack_result.total as int, remaining
			]
		)

	# Publish final guard value after consumption.
	guard_changed.emit(defender_is_player, defender.current_guard)


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


# ── Formatting helpers ────────────────────────────────────────────────────────

func _fmt_attack(name: String, r: Dictionary) -> String:
	return "  %s attacks: rolled %s, kept %s → [b]%d[/b]" % [
		name, _arr(r.dice as Array), _arr(r.kept as Array), r.total as int
	]


func _fmt_speed(name: String, total: int, vt: int, fast: bool) -> String:
	var tag := "[color=cyan]FAST[/color]" if fast else "[color=gray]slow[/color]"
	return "  %s: %d vs VT %d → %s" % [name, total, vt, tag]


func _fmt_defense(name: String, r: Dictionary) -> String:
	return "  %s rolls Stance: %s → kept %s → Guard [b]%d[/b]" % [
		name, _arr(r.dice as Array), _arr(r.kept as Array), r.total as int
	]


func _arr(a: Array) -> String:
	return "[" + ", ".join(a.map(func(v): return str(v))) + "]"
