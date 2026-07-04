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


func test_effective_tier_cap_limits() -> void:
	_state.tier_override = 4
	var mod := ActionModifier.new()
	mod.tier_cap = 2
	assert_eq(CombatMath.effective_tier(_state, mod), 2, "tier_cap caps the effective tier")


func test_effective_tier_null_mod_uncapped() -> void:
	_state.tier_override = 4
	assert_eq(CombatMath.effective_tier(_state, null), 4, "null mod → uncapped")


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


# ── Consistency + node lookups ───────────────────────────────────────────────

func test_pool_size_stance_matches_negation() -> void:
	assert_eq(CombatMath.get_pool_size(_state, "stance"),
		CombatMath.stat_size(_state, "negation"),
		"Stance pool size derives from Negation")


func test_node_effect_max_unknown_key_is_zero() -> void:
	assert_eq(CombatMath.node_effect_max(_state, "no_such_effect_key"), 0,
		"unknown effect key yields 0")
