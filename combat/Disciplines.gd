class_name Disciplines
extends RefCounted

# Magic-discipline logic — Layer 3.5 of the CombatManager refactor (Phase 4).
#
# Cohesive home for the four Ingenuity disciplines (Mind Detonation, Hex Mastery / Mind Rend,
# Chrono-Tinkering / Time Lock, Echoing Mind / Mind Lash). These are spine-integrated: they
# route through the CombatManager autoload's async pipeline (`_resolve_attack`), emit its signals,
# and read its round-scoped state. They reach the singleton via the `CombatManager` global
# (the same way the test suite does) rather than a threaded reference.
#
# CombatManager keeps thin delegating wrappers (`_check_mind_detonation`, `_cast_mind_rend`,
# `_cast_time_lock`, `_resolve_spell_echo`) so its round-loop call sites and the contract tests
# are unchanged. Two chrono snippets stay embedded in the spine on purpose: the armed→frozen
# transition in `_resolve_attack` and the frozen-guard restore in `_end_of_round` — moving them
# would mean editing the spine functions themselves.
#
# `roll_enemy_guard` unifies the enemy-defender resolve-pool guard roll that `_cast_mind_rend`
# and `_cast_time_lock` previously copy-pasted.


## Rolls (or reuses) an enemy's guard for `pool` — the enemy-defender subset of _resolve_attack's
## guard logic, shared by the wound-suppressing discipline casts. Emits guard_changed + logs.
static func roll_enemy_guard(enemy: CombatantState, enemy_index: int, pool: String) -> void:
	var pool_label := pool.capitalize()
	if not enemy.is_pool_rolled(pool):
		var defend_mod: ActionModifier = CombatMath.get_action_modifier(enemy, "defend", false)
		var ew := enemy.weapon_override if enemy.weapon_override else enemy.data.equipped_weapon
		var cap_str := "uncapped" if defend_mod.tier_cap == 0 else "cap %d" % defend_mod.tier_cap
		CombatManager.log_message.emit("  %s defends with [i]%s[/i] (%s, Tier %d → %d dice)" % [
			enemy.data.combatant_name,
			ew.item_name if ew else "Bare Hands",
			cap_str,
			enemy.data.tier,
			CombatMath.effective_tier(enemy, defend_mod),
		])
		var flat_debuff: int = 0
		var keep_debuff: int = 0
		var pending: Variant = enemy.pending_guard_debuffs.get(pool, null)
		if pending != null:
			flat_debuff = (pending as Dictionary).get("flat", 0) as int
			keep_debuff = (pending as Dictionary).get("keep", 0) as int
			enemy.pending_guard_debuffs.erase(pool)
			if flat_debuff != 0 or keep_debuff != 0:
				CombatManager.log_message.emit("  [color=purple][Outcome debuff] flat %+d, keep grade %+d on %s %s guard.[/color]" % [
					flat_debuff, keep_debuff, enemy.data.combatant_name, pool_label
				])
		var def_result := RollEngine.resolve(
			CombatMath.effective_tier(enemy, defend_mod), CombatMath.get_pool_size(enemy, pool),
			maxi(1, CombatMath.defense_keep_grade(enemy, pool) + keep_debuff),
			defend_mod.flat_bonus, 0
		)
		var guard_val: int = (def_result.total as int) + flat_debuff
		enemy.set_guard_val(pool, guard_val)
		enemy.set_pool_rolled(pool, true)
		CombatManager.guard_changed.emit(false, enemy_index, pool, guard_val)
		CombatManager.log_message.emit(CombatMath.fmt_defense(enemy.data.combatant_name, def_result, pool_label))
	else:
		CombatManager.log_message.emit("  %s %s already active — Guard [b]%d[/b] absorbs pressure." % [
			enemy.data.combatant_name, pool_label, enemy.get_guard(pool)
		])


# ── Mind Detonation (Group C1) ───────────────────────────────────────────────

## Phase 2.1 check: fires if the enemy carries mind_detonation_primed and their Stance was
## breached this round. KNOWN SIMPLIFICATION: uses global stance-breach tracking, not per-enemy.
static func check_mind_detonation(enemy: CombatantState, enemy_index: int) -> void:
	if not StatusOps.has(enemy, "mind_detonation_primed"):
		return
	if not CombatManager._current_round_player_breaches.get("stance", false):
		return
	await detonate_mind_bomb(enemy, enemy_index)


## Detonates a primed mind-bomb: builds the explosion roll, routes through _resolve_attack vs
## Resolve using the Fervor + cast values frozen at prime time. No Fervor escalation. Status
## removed BEFORE _resolve_attack (anti re-trigger: MD keys on Stance, explosion hits Resolve).
static func detonate_mind_bomb(enemy: CombatantState, enemy_index: int) -> void:
	var status := StatusOps.get_status(enemy, "mind_detonation_primed")
	if status == null:
		return
	var player: CombatantState = CombatManager._player
	var frozen_fervor: int   = status.stat_overrides.get("fervor_at_prime", 0) as int
	var cast_tier: int       = status.stat_overrides.get("cast_tier", CombatMath.effective_tier(player, null)) as int
	var cast_pool_bonus: int = status.stat_overrides.get("cast_pool_bonus", 0) as int
	var cast_keep_bonus: int = status.stat_overrides.get("cast_keep_bonus", 0) as int
	var cast_flat_bonus: int = status.stat_overrides.get("cast_flat_bonus", 0) as int
	StatusOps.remove(enemy, "mind_detonation_primed")

	var md_spell: SpellData = preload("res://resources/data/spells/mind_detonation.tres")
	var bonuses := CombatManager._collect_spell_bonuses(md_spell)
	# Cast tool frozen at prime time governs the explosion (cap + pool/keep/flat); see Phase 2.
	var pool: int = cast_tier + cast_pool_bonus + (bonuses["pool"] as int)
	var keep: int = CombatMath.training_keep_grade(player) + cast_keep_bonus + (bonuses["keep"] as int)
	var die: int  = CombatMath.stat_size(player, "ingenuity")
	var flat: int = (bonuses["flat"] as int) + cast_flat_bonus

	CombatManager.log_message.emit("[color=magenta][b]MIND DETONATION![/b] The charge erupts against %s's Resolve![/color]" % enemy.data.combatant_name)

	var explosion_result := RollEngine.resolve(pool, die, keep, flat, 0, frozen_fervor)
	CombatManager.log_message.emit(CombatMath.fmt_spell_attack("[Mind Detonation]", explosion_result))

	await CombatManager._resolve_attack(true, enemy_index, explosion_result, "resolve")
	# _resolve_attack handles guard roll, Massive logic, wound signals, and defeat detection.


# ── Hex Mastery / Mind Rend (Group C2) ───────────────────────────────────────

## Mind Rend: attacks enemy Resolve. On breach, suppresses the wound and applies hex_marked.
## On hold, nothing. Bypasses _resolve_attack (which always deals the breach wound). Mark applied
## AFTER the on_breach hook so Mind Rend's own breach is never self-amplified.
static func cast_mind_rend(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	if enemy == null or enemy.is_defeated:
		return
	var attack_total: int = attack_result.total as int
	roll_enemy_guard(enemy, enemy_index, "resolve")

	var current_guard: int = enemy.get_guard("resolve")
	if attack_total >= current_guard:
		CombatManager._process_statuses_hook("on_breach", enemy, {"pool": "resolve", "attacker": CombatManager._player})
		CombatManager._current_round_player_breaches["resolve"] = true
		var hex_level: int = PlayerProgression.get_node_level_by_id("hex_mastery")
		var dur: int = 3 if hex_level < 2 else 7
		var hex := CombatStatus.new()
		hex.status_id = "hex_marked"
		hex.duration_rounds = dur
		hex.source_node_id = "hex_mastery"
		StatusOps.add(enemy, hex)
		var perceived_turns: int = 2 if hex_level < 2 else 4
		CombatManager.log_message.emit("[color=purple]Mind Rend tears through! %s's mind is BRANDED — no wound, but the hex takes hold (%d turns).[/color]" % [
			enemy.data.combatant_name, perceived_turns
		])
	else:
		var remaining: int = current_guard - attack_total
		enemy.set_guard_val("resolve", remaining)
		CombatManager.log_message.emit("  %s's Resolve holds (%d remaining). No brand takes hold." % [
			enemy.data.combatant_name, remaining
		])

	CombatManager.guard_changed.emit(false, enemy_index, "resolve", enemy.get_guard("resolve"))


# ── Chrono-Tinkering / Time Lock (Group C4) ──────────────────────────────────

## Time Lock: attacks enemy Resolve. On breach, suppresses the wound and applies the
## "time_locked" status (armed phase). On hold, nothing. Mirrors cast_mind_rend's structure.
## The armed→frozen transition + frozen-guard restore live inline in CombatManager's spine.
static func cast_time_lock(enemy: CombatantState, enemy_index: int, attack_result: Dictionary) -> void:
	if enemy == null or enemy.is_defeated:
		return
	var attack_total: int = attack_result.total as int
	roll_enemy_guard(enemy, enemy_index, "resolve")

	var current_guard: int = enemy.get_guard("resolve")
	if attack_total >= current_guard:
		CombatManager._process_statuses_hook("on_breach", enemy, {"pool": "resolve", "attacker": CombatManager._player})
		CombatManager._current_round_player_breaches["resolve"] = true
		var tl := CombatStatus.new()
		tl.status_id = "time_locked"
		tl.duration_rounds = 20  # safety bound; real lifecycle driven by phase + skip_resets
		tl.source_node_id = "chrono_tinkering"
		tl.stat_overrides = {"phase": "armed", "locked_pool": "", "skip_resets": 0, "frozen_value": 0}
		StatusOps.add(enemy, tl)
		CombatManager.log_message.emit("[color=cyan]Time Lock takes hold — the next guard you strike will be frozen.[/color]")
	else:
		var remaining: int = current_guard - attack_total
		enemy.set_guard_val("resolve", remaining)
		CombatManager.log_message.emit("  %s's Resolve holds (%d remaining). The time-snare fails to catch." % [
			enemy.data.combatant_name, remaining
		])

	CombatManager.guard_changed.emit(false, enemy_index, "resolve", enemy.get_guard("resolve"))


# ── Echoing Mind / Mind Lash (Group C3) ──────────────────────────────────────

## Resolves one end_of_round echo. Routes through _resolve_attack with frozen Fervor + cast
## values and the decaying kept-dice count. No Fervor escalation. Self-removes when the next
## echo would keep < 1 die.
static func resolve_spell_echo(status: CombatStatus, state: CombatantState) -> void:
	var player: CombatantState = CombatManager._player
	var enemies: Array = CombatManager._enemies
	var spell_path: String   = status.stat_overrides.get("spell_path", "") as String
	var target_index: int    = status.stat_overrides.get("target_index", -1) as int
	var frozen_fervor: int   = status.stat_overrides.get("frozen_fervor", 0) as int
	var current_kept: int    = status.stat_overrides.get("current_kept_dice", 0) as int
	var em_level: int        = status.stat_overrides.get("em_level", 1) as int
	var cast_tier: int       = status.stat_overrides.get("cast_tier", CombatMath.effective_tier(player, null)) as int
	var cast_pool_bonus: int = status.stat_overrides.get("cast_pool_bonus", 0) as int
	var cast_flat_bonus: int = status.stat_overrides.get("cast_flat_bonus", 0) as int

	if spell_path == "" or target_index < 0 or target_index >= enemies.size():
		StatusOps.remove(state, "echoing_spell")
		return
	var spell: SpellData = load(spell_path) as SpellData
	if spell == null:
		StatusOps.remove(state, "echoing_spell")
		return
	var target: CombatantState = enemies[target_index]
	if target == null or target.is_defeated:
		CombatManager.log_message.emit("[color=cyan]The echo fades — no one left to hear it.[/color]")
		StatusOps.remove(state, "echoing_spell")
		return

	var bonuses := CombatManager._collect_spell_bonuses(spell)
	# Cast tool frozen at cast time governs the echo pool + flat; keep_grade carries the
	# decaying kept-dice count (focus keep was baked into it at arming). See Phase 2.
	var pool: int       = cast_tier + cast_pool_bonus + (bonuses["pool"] as int)
	var keep_grade: int = current_kept  # decaying kept-dice count; focus keep already in it
	var die: int        = CombatMath.stat_size(player, "ingenuity")
	var base_flat: int  = spell.flat_bonus + (bonuses["flat"] as int) + cast_flat_bonus
	var echo_flat: int  = current_kept if em_level >= 2 else 0  # L2: flat = kept dice for this echo
	var total_flat: int = base_flat + echo_flat

	var flat_note: String = (" (+%d flat from Echoing Mind L2)" % echo_flat) if em_level >= 2 else ""
	CombatManager.log_message.emit("[color=cyan][b]ECHO![/b] %s resounds — keeping %d die(s)%s.[/color]" % [
		spell.spell_name, current_kept, flat_note
	])

	var echo_result := RollEngine.resolve(pool, die, keep_grade, total_flat, 0, frozen_fervor)
	CombatManager.log_message.emit(CombatMath.fmt_spell_attack("[Echo: %s]" % spell.spell_name, echo_result))

	# Route through _resolve_attack: Hex amplification and on_breach hooks fire normally.
	await CombatManager._resolve_attack(true, target_index, echo_result, spell.target_pool)

	# Phase 2.1 equivalent: echo Stance breach can detonate primed mind-bombs.
	if not target.is_defeated:
		await check_mind_detonation(target, target_index)

	# Decrement kept dice; remove status when next echo would keep 0 dice.
	var next_kept: int = current_kept - 1
	if next_kept < 1:
		StatusOps.remove(state, "echoing_spell")
		CombatManager.log_message.emit("[color=cyan]The echo dies away.[/color]")
	else:
		status.stat_overrides["current_kept_dice"] = next_kept
