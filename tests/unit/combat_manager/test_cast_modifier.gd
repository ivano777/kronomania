extends GutTest

# Permanent regression guard for cast-tool cap/bonus resolution (Casting implement system).
# Deterministic: no spells cast, no combat coroutine, no RNG. Verifies _get_cast_modifier +
# _effective_tier — the resolved cast tier that feeds direct casts AND the frozen delayed payoffs.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")
const _IRON_SWORD  = preload("res://resources/data/weapons/iron_sword.tres")


func before_each() -> void:
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	CombatManager._player.tier_override = 4  # deterministic Tier 4


func after_each() -> void:
	CombatManager._player_cast_weapon = null  # don't leak the chosen tool across tests


func _make_focus(cap: int, pool: int, keep: int, flat: int) -> EquipmentData:
	var m := ActionModifier.new()
	m.action_key = "cast"
	m.action_name = "Cast"
	m.tier_cap = cap
	m.pool_bonus = pool
	m.keep_bonus = keep
	m.flat_bonus = flat
	var eq := EquipmentData.new()
	eq.item_name = "Test Focus"
	eq.action_modifiers = [m]
	return eq


func _cast_tier() -> int:
	return CombatManager._effective_tier(
		CombatManager._player, CombatManager._get_cast_modifier(CombatManager._player))


# 1. Bare hands → full Tier (uncapped).
func test_bare_hands_full_tier() -> void:
	CombatManager._player_cast_weapon = null
	assert_eq(_cast_tier(), 4, "Bare hands should cast at full Tier")
	assert_eq(CombatManager._get_cast_modifier(CombatManager._player).tier_cap, 0,
		"Bare-hands cast modifier is uncapped")


# 2. Mundane weapon → cap 1.
func test_mundane_weapon_caps_at_one() -> void:
	CombatManager._player_cast_weapon = _IRON_SWORD
	assert_eq(_cast_tier(), 1, "A mundane weapon caps casting at Tier 1")


# 3. Focus (tier_cap=0) → full Tier, bonuses surfaced.
func test_focus_uncapped_with_bonuses() -> void:
	CombatManager._player_cast_weapon = _make_focus(0, 1, 1, 1)
	var mod := CombatManager._get_cast_modifier(CombatManager._player)
	assert_eq(_cast_tier(), 4, "A focus with tier_cap=0 leaves the pool at full Tier")
	assert_eq(mod.pool_bonus, 1, "Focus pool bonus surfaced")
	assert_eq(mod.keep_bonus, 1, "Focus keep bonus surfaced")
	assert_eq(mod.flat_bonus, 1, "Focus flat bonus surfaced")


# 4. Impairing focus (tier_cap=2) → capped at 2 (at Tier 4).
func test_impairing_focus_caps() -> void:
	CombatManager._player_cast_weapon = _make_focus(2, 0, 0, 0)
	assert_eq(_cast_tier(), 2, "A focus with tier_cap=2 caps the pool at 2 at Tier 4")
