class_name CombatMath
extends RefCounted

## Equip-requirements rework: items tagged with this act as casting conduits.
const MAGIC_FOCUS_TAG := "MagicFocus"

# Pure combat math — Layer 1 of the CombatManager refactor (Phase 2).
#
# Stateless static helpers over CombatantState + purchased NodeData. No signals, no await,
# no CombatManager member access. The two functions that once branched on player identity
# (get_action_modifier, attacker_weapon_name) take an explicit `is_player` flag; get_cast_modifier
# takes the chosen casting tool explicitly. CombatManager keeps same-signature wrappers that
# supply those arguments, so call sites and tests are unchanged.
#
# Player vs enemy weapon resolution: for the player, weapon_override == null means bare hands
# (no fallback). For enemies, weapon_override == null falls back to data.equipped_weapon.


## Passive Max Wounds bonus from Tier: +1 at Tier 2, +1 again at Tier 4 (cumulative +2).
static func tier_wound_bonus(tier: int) -> int:
	return (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)


## Sums max_wounds bonuses from Wounds Training nodes (effect_type="training_wounds").
static func wounds_node_bonus(state: CombatantState) -> int:
	return node_effect_sum(state, "training_wounds")


## Returns the effective physical keep grade: max of training_keep or physical_keep nodes.
static func physical_keep_grade(state: CombatantState) -> int:
	return maxi(training_keep_grade(state), node_effect_max(state, "physical_keep"))


## Returns the max uses_per_combat across all purchased meat_grinder NodeLevelData entries.
static func meat_grinder_charges(state: CombatantState) -> int:
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


## Returns the max uses_per_combat across all purchased magic_shield NodeLevelData
## entries (ing_resolve L2 = 1, L3 = 2).
static func magic_shield_charges(state: CombatantState) -> int:
	var best := 0
	for node in state.node_levels.keys():
		var nd: NodeData = node as NodeData
		if nd == null:
			continue
		var lvl: int = state.node_levels[node]
		for i in range(mini(lvl, nd.levels_data.size())):
			var ld: NodeLevelData = nd.levels_data[i]
			if ld.effect_type == "magic_shield":
				best = maxi(best, ld.uses_per_combat)
	return best


## Magic Shield dice count = purchased ing_resolve level (the defense line feeds
## the shield: deeper Resolve training weaves more Ingenuity dice per charge).
static func magic_shield_dice(state: CombatantState) -> int:
	for node in state.node_levels.keys():
		if (node as NodeData).node_id == "ing_resolve":
			return state.node_levels[node] as int
	return 0


## Returns the die size for the given defense pool on a combatant.
## Stance = Negation, Resolve = Ingenuity, Stamina = Dominion (defensive expression).
static func get_pool_size(state: CombatantState, pool: String) -> int:
	match pool:
		"stance":  return stat_size(state, "negation")
		"resolve": return stat_size(state, "ingenuity")
		"stamina": return stat_size(state, "dominion")
	return stat_size(state, "negation")


## Effective Tier: tier_override if set, else data.tier. Items never cap Tier —
## the throttle on expressed dice is the node keep grades (equip-requirements rework).
static func effective_tier(state: CombatantState) -> int:
	return state.tier_override if state.tier_override > 0 else state.data.tier


## Flat bonus applied to attack rolls: strike ActionModifier flat + weapon_flat node bonuses.
static func attack_flat(state: CombatantState, is_player: bool, strike_mod: ActionModifier = null, weapon: EquipmentData = null) -> int:
	var m := strike_mod if strike_mod != null else get_action_modifier(state, "strike", is_player)
	return m.flat_bonus + node_weapon_bonus_sum(state, "weapon_flat", weapon)


## Flat bonus applied to defense rolls: defend ActionModifier flat.
static func guard_flat(state: CombatantState, is_player: bool) -> int:
	return get_action_modifier(state, "defend", is_player).flat_bonus


## Pool size modifier from the ActionModifier for the given action key.
static func pool_bonus(state: CombatantState, is_player: bool, action_key: String = "strike", strike_mod: ActionModifier = null) -> int:
	var m := strike_mod if strike_mod != null else get_action_modifier(state, action_key, is_player)
	return m.pool_bonus


## Looks up the ActionModifier for action_key: weapon first, then bare_hands (always present).
## is_player: player weapon_override == null means bare hands; enemies fall back to data.equipped_weapon.
static func get_action_modifier(state: CombatantState, action_key: String, is_player: bool) -> ActionModifier:
	var w: EquipmentData
	if is_player:
		w = state.weapon_override
	else:
		w = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	if w:
		for mod in w.action_modifiers:
			if mod.action_key == action_key:
				return mod
	return state.data.get_bare_hands_modifier(action_key)


## Equip-requirements: true when either of the player's hand slots carries the tag.
## Player-only — reads the override slots directly (null = empty hand, no data fallback).
static func player_has_equipped_tag(state: CombatantState, tag: String) -> bool:
	for w in [state.weapon_override, state.off_hand_override]:
		if w != null and (w as EquipmentData).tags.has(tag):
			return true
	return false


## True when both player hand slots are empty (bare hands). Player-only.
static func player_hands_empty(state: CombatantState) -> bool:
	return state.weapon_override == null and state.off_hand_override == null


## Cantrips channel through truly empty hands or an equipped Magic Focus.
static func can_channel_cantrips(state: CombatantState) -> bool:
	return player_hands_empty(state) or player_has_equipped_tag(state, MAGIC_FOCUS_TAG)


## True spells always require an equipped Magic Focus (empty hands are not enough).
static func can_channel_spells(state: CombatantState) -> bool:
	return player_has_equipped_tag(state, MAGIC_FOCUS_TAG)


## Resolves the "cast" ActionModifier from the player's chosen casting tool.
## Null tool or no "cast" key → bare-hands stub (all bonuses zero).
static func get_cast_modifier(state: CombatantState, cast_weapon: EquipmentData) -> ActionModifier:
	if cast_weapon:
		for mod in cast_weapon.action_modifiers:
			if mod.action_key == "cast":
				return mod
	return state.data.get_bare_hands_modifier("cast")


## Architecture stub: applies derivation_ratio to parent's bonuses (floor). No derived actions yet.
static func derived_modifier(mod: ActionModifier, parent: ActionModifier) -> ActionModifier:
	var derived := mod.duplicate() as ActionModifier
	if mod.parent_action_key != "" and mod.derivation_ratio > 0.0:
		derived.flat_bonus  = floori(parent.flat_bonus  * mod.derivation_ratio)
		derived.keep_bonus  = floori(parent.keep_bonus  * mod.derivation_ratio)
		derived.pool_bonus  = floori(parent.pool_bonus  * mod.derivation_ratio)
	return derived


## Returns all ActionModifiers for a state: main-hand + off-hand + bare_hands (always present).
static func get_all_action_modifiers(state: CombatantState) -> Array:
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
static func node_effect_max(state: CombatantState, key: String) -> int:
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
static func node_effect_sum(state: CombatantState, key: String) -> int:
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
static func node_weapon_bonus_sum(state: CombatantState, key: String, weapon_override: EquipmentData = null) -> int:
	var total := 0
	var weapon: EquipmentData = weapon_override if weapon_override != null else (state.weapon_override if state.weapon_override else state.data.equipped_weapon)
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
static func has_effect_type(state: CombatantState, key: String) -> bool:
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
static func stat_size(state: CombatantState, stat: String) -> int:
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
	return maxi(base, node_effect_max(state, "stat_size_" + stat))


## Returns the effective keep grade for a combatant: highest Training node value,
## or data.keep_grade as fallback when no Training node is present.
static func training_keep_grade(state: CombatantState) -> int:
	return maxi(state.data.keep_grade, node_effect_max(state, "training_keep"))


## Defense node per pool — a pool's keep grade equals the purchased level of its
## branch defense node (L1 auto-granted = keep 1). Implicit keep frees each level's
## effect_type for riders (defense-rework); the *_keep effect types are retired.
const DEFENSE_NODE_FOR_POOL: Dictionary = {
	"stance": "neg_stance",
	"resolve": "ing_resolve",
	"stamina": "dom_stamina",
}


## Returns the effective defensive keep grade for the given pool: max of
## training_keep_grade (floor, covers enemies) and the pool's defense node level.
static func defense_keep_grade(state: CombatantState, pool: String) -> int:
	var want: String = DEFENSE_NODE_FOR_POOL.get(pool, "")
	var lvl := 0
	for node in state.node_levels.keys():
		if (node as NodeData).node_id == want:
			lvl = state.node_levels[node] as int
			break
	return maxi(training_keep_grade(state), lvl)


## Flat guard bonus for a pool (neg_stance L2 rider "stance_flat" — Stance pool only).
static func guard_flat_bonus(state: CombatantState, pool: String) -> int:
	if pool != "stance":
		return 0
	return node_effect_sum(state, "stance_flat")


## Extra defense pool dice of Negation size on EVERY pool (neg_stance L3 rider
## "guard_aspect_all"). Added dice, not substituted: caller must widen the pool
## by this count AND pass it as aspect_count with Negation as aspect_stat_size.
static func guard_bonus_dice(state: CombatantState) -> int:
	return node_effect_max(state, "guard_aspect_all")


# ── Formatting helpers ────────────────────────────────────────────────────────

static func attacker_weapon_name(state: CombatantState, is_player: bool) -> String:
	var w: EquipmentData
	if is_player:
		w = state.weapon_override
	else:
		w = state.weapon_override if state.weapon_override else state.data.equipped_weapon
	if w:
		return w.item_name
	if not is_player:
		# Weaponless enemies (enemy = tier + action list): flavor from the strike action's name.
		var m := get_action_modifier(state, "strike", false)
		if m.action_name != "":
			return m.action_name
	return "Bare Hands"


static func fmt_attack(name: String, r: Dictionary, weapon_name: String = "") -> String:
	var desperation: bool = r.desperation
	var prefix := "[b][DESPERATION][/b] " if desperation else ""
	var flat: int = r.flat as int
	var flat_part := " + %d flat" % flat if flat != 0 else ""
	var with_part := " with [i]%s[/i]" % weapon_name if weapon_name != "" else ""
	return "  %s%s attacks%s: rolled %s, kept %s%s → [b]%d[/b]" % [
		prefix, name, with_part, arr(r.dice as Array), arr(r.kept as Array), flat_part, r.total as int
	]


static func fmt_spell_attack(name: String, r: Dictionary) -> String:
	var desperation: bool = r.desperation
	var prefix := "[b][DESPERATION][/b] " if desperation else ""
	var fervor_roll: int = r.fervor_roll as int
	var fervor_part := " + [color=magenta]Fervor %d[/color]" % fervor_roll if fervor_roll > 0 else ""
	var maxed_note := " [color=magenta][b][MAX][/b][/color]" if (r.fervor_maxed as bool) else ""
	return "  %s%s casts: rolled %s, kept %s%s → [b]%d[/b]%s" % [
		prefix, name, arr(r.dice as Array), arr(r.kept as Array),
		fervor_part, r.total as int, maxed_note
	]


static func fmt_speed(name: String, total: int, vt: int, fast: bool) -> String:
	var tag := "[color=cyan]FAST[/color]" if fast else "[color=gray]slow[/color]"
	return "  %s: %d vs VT %d → %s" % [name, total, vt, tag]


static func fmt_defense(name: String, r: Dictionary, pool_label: String) -> String:
	var flat: int = r.flat as int
	var flat_part := " + %d flat" % flat if flat != 0 else ""
	return "  %s rolls %s: %s → kept %s%s → Guard [b]%d[/b]" % [
		name, pool_label, arr(r.dice as Array), arr(r.kept as Array), flat_part, r.total as int
	]


static func arr(a: Array) -> String:
	return "[" + ", ".join(a.map(func(v): return str(v))) + "]"
