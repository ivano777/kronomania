extends GutTest

# Direct unit tests for the CombatMath static module (Phase 2 of the CombatManager refactor).
# The payoff of extraction: these run against a hand-built CombatantState — no start_combat,
# no CombatManager singleton, no signals. Pure functions, tested in isolation.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")

var _state: CombatantState


func before_each() -> void:
	_state = CombatantState.new()
	_state.init(_PLAYER_DATA)


# ── tier_wound_bonus (pure) ──────────────────────────────────────────────────

func test_tier_wound_bonus(params = use_parameters([[1, 0], [2, 1], [3, 1], [4, 2]])) -> void:
	assert_eq(CombatMath.tier_wound_bonus(params[0]), params[1],
		"tier_wound_bonus(T%d) == %d" % [params[0], params[1]])


# ── effective_tier ───────────────────────────────────────────────────────────

func test_effective_tier_override_beats_base() -> void:
	_state.tier_override = 3
	assert_eq(CombatMath.effective_tier(_state), 3, "tier_override wins over data.tier")


func test_effective_tier_never_item_capped() -> void:
	_state.tier_override = 4
	assert_eq(CombatMath.effective_tier(_state), 4, "items never cap Tier (equip-requirements rework)")


# ── get_action_modifier / get_cast_modifier ──────────────────────────────────

func test_get_action_modifier_player_bare_hands() -> void:
	# Player with no weapon_override resolves the bare-hands strike modifier.
	var mod := CombatMath.get_action_modifier(_state, "strike", true)
	assert_not_null(mod, "player strike modifier resolves")
	assert_eq(mod.action_key, "strike", "resolves the strike action")


func test_get_cast_modifier_bare_hands_when_no_tool() -> void:
	var mod := CombatMath.get_cast_modifier(_state, null)
	assert_not_null(mod, "cast modifier resolves to bare-hands stub with no tool")
	assert_eq(mod.action_key, "cast", "resolves the cast action")


func test_weaponless_enemy_resolves_actions_from_data() -> void:
	# Enemy weapon strip: enemies carry no equipped_weapon; actions live in
	# bare_hands_actions and flavor the combat log via action_name.
	var e := CombatantState.new()
	e.init(preload("res://resources/data/enemies/enemy_soldier.tres"))
	var m := CombatMath.get_action_modifier(e, "strike", false)
	assert_eq(m.action_name, "Sword Slash", "enemy strike resolves from bare_hands_actions")
	assert_eq(m.flat_bonus, 1, "weapon flat bonus preserved on the native action")
	assert_eq(CombatMath.attacker_weapon_name(e, false), "Sword Slash",
		"weaponless enemy attack flavored by the strike action name")
	assert_eq(CombatMath.get_action_modifier(e, "defend", false).action_name, "Guard",
		"enemy defend resolves from bare_hands_actions")


# ── Consistency + node lookups ───────────────────────────────────────────────

func test_pool_size_stance_matches_negation() -> void:
	assert_eq(CombatMath.get_pool_size(_state, "stance"),
		CombatMath.stat_size(_state, "negation"),
		"Stance pool size derives from Negation")


func test_node_effect_max_unknown_key_is_zero() -> void:
	assert_eq(CombatMath.node_effect_max(_state, "no_such_effect_key"), 0,
		"unknown effect key yields 0")


# ── Defense rework: keep from defense-node level + negation riders ──────────

const _NEG_STANCE  = preload("res://resources/data/nodes/negation/neg_stance.tres")
const _DOM_STAMINA = preload("res://resources/data/nodes/dominion/dom_stamina.tres")
const _ING_RESOLVE = preload("res://resources/data/nodes/ingenuity/ing_resolve.tres")


func test_defense_keep_grade_follows_node_level() -> void:
	_state.node_levels[_NEG_STANCE] = 2
	_state.node_levels[_ING_RESOLVE] = 3
	assert_eq(CombatMath.defense_keep_grade(_state, "stance"), 2,
		"stance keep = neg_stance purchased level")
	assert_eq(CombatMath.defense_keep_grade(_state, "resolve"), 3,
		"resolve keep = ing_resolve purchased level")


func test_defense_keep_grade_training_is_floor() -> void:
	# No defense nodes purchased: keep falls back to the training grade.
	var floor_grade := CombatMath.training_keep_grade(_state)
	assert_eq(CombatMath.defense_keep_grade(_state, "stamina"), floor_grade,
		"pool without a defense node uses the training floor")
	_state.node_levels[_DOM_STAMINA] = 1
	assert_eq(CombatMath.defense_keep_grade(_state, "stamina"), maxi(floor_grade, 1),
		"defense node L1 never lowers the grade below the training floor")


func test_guard_flat_bonus_applies_to_stance_only() -> void:
	_state.node_levels[_NEG_STANCE] = 2
	assert_eq(CombatMath.guard_flat_bonus(_state, "stance"), 2,
		"neg_stance L2 grants +2 flat on Stance guard")
	assert_eq(CombatMath.guard_flat_bonus(_state, "stamina"), 0,
		"stance_flat rider never leaks onto other pools")


func test_guard_bonus_dice_from_neg_stance_l3() -> void:
	_state.node_levels[_NEG_STANCE] = 2
	assert_eq(CombatMath.guard_bonus_dice(_state), 0, "no bonus die below L3")
	_state.node_levels[_NEG_STANCE] = 3
	assert_eq(CombatMath.guard_bonus_dice(_state), 1,
		"neg_stance L3 lends 1 Negation die to every pool")


func test_stamina_l2_carries_the_single_wound_bonus() -> void:
	_state.node_levels[_DOM_STAMINA] = 1
	assert_eq(CombatMath.wounds_node_bonus(_state), 0, "L1 grants no wound bonus")
	_state.node_levels[_DOM_STAMINA] = 3
	assert_eq(CombatMath.wounds_node_bonus(_state), 1,
		"dom_stamina L2 rider is the only Max Wounds bonus (+1 total, dom_wounds deleted)")
