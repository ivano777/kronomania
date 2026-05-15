extends GutTest

# PlayerProgression is an Autoload. Access it via /root/PlayerProgression.
# before_each() calls reset() so each test starts from a clean initial state.
#
# IMPORTANT: reset() calls _grant_default_keep_nodes() which pre-populates 4 training nodes
# (dom_martial_arts, dom_stamina, neg_stance, ing_resolve) at level 1.
# These are set directly (not via upgrade()), so tier_combat_spent stays 0.

const _DOM_CORE       = preload("res://resources/data/nodes/dominion/dom_core.tres")
const _DOM_MART_ARTS  = preload("res://resources/data/nodes/dominion/dom_martial_arts.tres")
const _DOM_WOUNDS     = preload("res://resources/data/nodes/dominion/dom_wounds.tres")
const _MINOR_STUDIES  = preload("res://resources/data/nodes/ability_minor_studies.tres")
const _WARRIOR_OATH   = preload("res://resources/data/nodes/flavor_warrior_oath.tres")
const _ARENA_CHAMP    = preload("res://resources/data/nodes/flavors/flavor_arena_champion.tres")

var pp: Node


func before_each() -> void:
	pp = get_node("/root/PlayerProgression")
	pp.reset()


# ── reset() ───────────────────────────────────────────────────────────────────

func test_reset_tier_is_1() -> void:
	pp.debug_set_tier(3)
	pp.reset()
	assert_eq(pp.get_tier(), 1, "reset() sets tier to 1")


func test_reset_populates_4_default_training_nodes() -> void:
	# reset() calls _grant_default_keep_nodes() → 4 entries at level 1.
	assert_eq(pp.node_levels.size(), 4,
		"reset() pre-populates exactly 4 default training nodes")


func test_reset_available_points_is_3() -> void:
	pp.grant_points(100)
	pp.reset()
	assert_eq(pp.available_points, 3, "reset() restores available_points to 3")


func test_reset_tier_combat_spent_is_0() -> void:
	pp.reset()
	assert_eq(pp.tier_combat_spent, 0, "reset() clears tier_combat_spent")


func test_reset_tier_flavor_spent_is_0() -> void:
	pp.reset()
	assert_eq(pp.tier_flavor_spent, 0, "reset() clears tier_flavor_spent")


func test_reset_clears_fervor_and_burnout() -> void:
	pp.saved_fervor_size = 10
	pp.saved_is_burned_out = true
	pp.reset()
	assert_eq(pp.saved_fervor_size, 4, "reset() sets fervor to d4")
	assert_false(pp.saved_is_burned_out, "reset() clears burnout")


# ── grant_points() ────────────────────────────────────────────────────────────

func test_grant_points_adds_to_available() -> void:
	pp.grant_points(5)
	assert_eq(pp.available_points, 8, "grant_points(5) adds 5 to starting 3")


func test_grant_points_cumulative() -> void:
	pp.grant_points(2)
	pp.grant_points(3)
	assert_eq(pp.available_points, 8, "successive grant_points calls accumulate")


# ── apply_long_rest() ─────────────────────────────────────────────────────────

func test_long_rest_resets_fervor_to_d4() -> void:
	pp.saved_fervor_size = 10
	pp.apply_long_rest()
	assert_eq(pp.saved_fervor_size, 4, "long rest resets fervor to d4")


func test_long_rest_clears_burnout() -> void:
	pp.saved_is_burned_out = true
	pp.apply_long_rest()
	assert_false(pp.saved_is_burned_out, "long rest clears burnout")


func test_long_rest_resets_wounds() -> void:
	pp.saved_wounds = 3
	pp.apply_long_rest()
	assert_eq(pp.saved_wounds, 0, "long rest heals all wounds")


# ── apply_short_rest() ────────────────────────────────────────────────────────

func test_short_rest_decrements_wounds() -> void:
	pp.saved_wounds = 3
	pp.apply_short_rest()
	assert_eq(pp.saved_wounds, 2, "short rest reduces wounds by 1")


func test_short_rest_clamps_wounds_at_0() -> void:
	pp.saved_wounds = 0
	pp.apply_short_rest()
	assert_eq(pp.saved_wounds, 0, "short rest does not reduce wounds below 0")


func test_short_rest_steps_fervor_down() -> void:
	pp.saved_fervor_size = 6
	pp.apply_short_rest()
	assert_eq(pp.saved_fervor_size, 4, "short rest steps fervor d6 → d4")


func test_short_rest_does_not_go_below_d4() -> void:
	pp.saved_fervor_size = 4
	pp.apply_short_rest()
	assert_eq(pp.saved_fervor_size, 4, "short rest does not reduce fervor below d4")


func test_short_rest_clears_burnout() -> void:
	pp.saved_is_burned_out = true
	pp.apply_short_rest()
	assert_false(pp.saved_is_burned_out, "short rest clears burnout")


# ── apply_recovery() ─────────────────────────────────────────────────────────

func test_recovery_clears_burnout() -> void:
	pp.saved_is_burned_out = true
	pp.apply_recovery()
	assert_false(pp.saved_is_burned_out, "recovery clears burnout")


func test_recovery_does_not_touch_wounds() -> void:
	pp.saved_wounds = 2
	pp.apply_recovery()
	assert_eq(pp.saved_wounds, 2, "recovery does not change wounds")


func test_recovery_does_not_touch_fervor() -> void:
	pp.saved_fervor_size = 8
	pp.apply_recovery()
	assert_eq(pp.saved_fervor_size, 8, "recovery does not change fervor")


# ── spell/cantrip lists ───────────────────────────────────────────────────────

func test_known_spells_empty_after_reset() -> void:
	assert_eq(pp.get_known_spells().size(), 0,
		"get_known_spells() returns empty array after reset")


func test_known_cantrips_empty_after_reset() -> void:
	assert_eq(pp.get_known_cantrips().size(), 0,
		"get_known_cantrips() returns empty array after reset")


func test_buying_minor_studies_grants_cantrips() -> void:
	pp.debug_set_points(10)
	pp.upgrade(_MINOR_STUDIES)
	var cantrips: Array = pp.get_known_cantrips()
	assert_gt(cantrips.size(), 0, "buying Minor Studies grants at least one cantrip")


func test_minor_studies_grants_no_true_spells() -> void:
	pp.debug_set_points(10)
	pp.upgrade(_MINOR_STUDIES)
	var spells: Array = pp.get_known_spells()
	assert_eq(spells.size(), 0, "Minor Studies grants cantrips only, no true spells")


# ── tier advancement ──────────────────────────────────────────────────────────

func test_tier_advances_after_5_combat_plus_2_flavor_slots() -> void:
	pp.debug_set_points(20)

	# Step 1: dom_core L1 — 2 combat slots (Core node)
	pp.upgrade(_DOM_CORE)
	assert_eq(pp.tier_combat_spent, 2, "after dom_core L1: 2 combat slots spent")

	# Step 2: dom_martial_arts L2 — 1 combat slot (requires dom_core L1 ✓ + martial_arts L1 ✓)
	pp.upgrade(_DOM_MART_ARTS)
	assert_eq(pp.tier_combat_spent, 3, "after martial_arts L2: 3 combat slots spent")

	# Step 3: minor_studies — 1 combat slot (no prerequisites)
	pp.upgrade(_MINOR_STUDIES)
	assert_eq(pp.tier_combat_spent, 4, "after minor_studies: 4 combat slots spent")

	# Step 4: dom_wounds L1 — 1 combat slot (requires dom_core L1 ✓)
	pp.upgrade(_DOM_WOUNDS)
	assert_eq(pp.tier_combat_spent, 5, "after dom_wounds L1: 5 combat slots spent")

	# Step 5: warrior_oath — 1 flavor slot
	pp.upgrade(_WARRIOR_OATH)
	assert_eq(pp.tier_flavor_spent, 1, "after warrior_oath: 1 flavor slot spent")

	# Step 6: arena_champion — 1 flavor slot → triggers tier advance
	pp.upgrade(_ARENA_CHAMP)
	assert_eq(pp.get_tier(), 2, "tier advances to 2 after 5 combat + 2 flavor slots filled")
	assert_eq(pp.tier_combat_spent, 0, "combat slot counter resets on tier advance")
	assert_eq(pp.tier_flavor_spent, 0, "flavor slot counter resets on tier advance")
