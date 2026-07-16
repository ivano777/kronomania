extends GutTest

# PlayerProgression is an Autoload. Access it via /root/PlayerProgression.
# before_each() calls reset() so each test starts from a clean initial state.
#
# IMPORTANT: reset() calls _grant_default_keep_nodes() which pre-populates 4 training nodes
# (dom_martial_arts, dom_stamina, neg_stance, ing_resolve) at level 1.
# These are set directly (not via upgrade()), so tier_combat_spent stays 0.

const _DOM_CORE       = preload("res://resources/data/nodes/dominion/dom_core.tres")
const _DOM_MART_ARTS  = preload("res://resources/data/nodes/dominion/dom_martial_arts.tres")
const _DOM_MELEE      = preload("res://resources/data/nodes/dominion/dom_melee.tres")
const _DOM_MEAT_GRIND = preload("res://resources/data/nodes/dominion/dom_meat_grinder.tres")
const _MINOR_STUDIES  = preload("res://resources/data/nodes/ability_minor_studies.tres")
const _WARRIOR_OATH   = preload("res://resources/data/nodes/flavor_warrior_oath.tres")
const _ARENA_CHAMP    = preload("res://resources/data/nodes/flavors/flavor_arena_champion.tres")

var pp: Node


func before_each() -> void:
	pp = get_node("/root/PlayerProgression")
	pp.reset()


func after_each() -> void:
	# Free Buy is session-scoped debug state, deliberately untouched by reset().
	pp.debug_free_buy = false
	get_node("/root/DebugManager").enabled = false


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

	# Step 4: dom_melee L1 — 1 combat slot (requires dom_martial_arts L1 ✓ auto-granted)
	pp.upgrade(_DOM_MELEE)
	assert_eq(pp.tier_combat_spent, 5, "after dom_melee L1: 5 combat slots spent")

	# Step 5: warrior_oath — 1 flavor slot
	pp.upgrade(_WARRIOR_OATH)
	assert_eq(pp.tier_flavor_spent, 1, "after warrior_oath: 1 flavor slot spent")

	# Step 6: arena_champion — 1 flavor slot → triggers tier advance
	pp.upgrade(_ARENA_CHAMP)
	assert_eq(pp.get_tier(), 2, "tier advances to 2 after 5 combat + 2 flavor slots filled")
	assert_eq(pp.tier_combat_spent, 0, "combat slot counter resets on tier advance")
	assert_eq(pp.tier_flavor_spent, 0, "flavor slot counter resets on tier advance")


# ── debug Free Buy toggle ─────────────────────────────────────────────────────

func test_free_buy_bypasses_gates_and_budget() -> void:
	get_node("/root/DebugManager").enabled = true
	pp.debug_free_buy = true
	pp.debug_set_points(20)
	pp.upgrade(_DOM_CORE)  # L1 (cost 2)
	pp.upgrade(_DOM_CORE)  # L2 (cost 2) — combat budget now 4/5
	assert_true(pp.can_upgrade(_DOM_CORE),
		"Free Buy allows dom_core L3 (would overflow the 5-slot budget)")


func test_free_buy_inert_without_debug_mode() -> void:
	get_node("/root/DebugManager").enabled = false
	pp.debug_free_buy = true
	pp.debug_set_points(20)
	pp.upgrade(_DOM_CORE)
	pp.upgrade(_DOM_CORE)
	assert_false(pp.can_upgrade(_DOM_CORE),
		"Free Buy flag does nothing while F12 debug mode is off")


func test_slot_budget_holds_without_free_buy() -> void:
	pp.debug_set_points(20)
	pp.upgrade(_DOM_CORE)
	pp.upgrade(_DOM_CORE)
	# Gate {dominion:3} is met (spend 4), but 4 + 2 slots overflows the 5-slot budget.
	assert_false(pp.can_upgrade(_DOM_CORE),
		"dom_core L3 stays blocked by the tier slot budget without Free Buy")


func test_free_buy_waives_point_cost_and_spends_nothing() -> void:
	get_node("/root/DebugManager").enabled = true
	pp.debug_free_buy = true
	pp.debug_set_points(0)
	assert_true(pp.can_upgrade(_DOM_CORE),
		"Free Buy waives the point cost (0 points, cost 2)")
	pp.upgrade(_DOM_CORE)
	assert_eq(pp.get_level(_DOM_CORE), 1, "Free Buy grants the level")
	assert_eq(pp.available_points, 0, "Free Buy spends no points")
	assert_eq(pp.tier_combat_spent, 0, "Free Buy fills no combat slots")
	assert_eq(pp.get_tier(), 1, "Free Buy never auto-advances the tier")


func test_free_buy_still_requires_prerequisites() -> void:
	get_node("/root/DebugManager").enabled = true
	pp.debug_free_buy = true
	pp.debug_set_points(20)
	# dom_meat_grinder L1 requires dom_stamina L2; auto-grant only gives L1.
	assert_false(pp.can_upgrade(_DOM_MEAT_GRIND),
		"Free Buy keeps prerequisite chains intact")


# ── branch-spend gates (replaced required_tier — defense-rework Phase 1) ─────

func _gated_node(gate: Dictionary) -> NodeData:
	var ld := NodeLevelData.new()
	ld.cost = 1
	ld.branch_spend = gate
	var n := NodeData.new()
	n.node_id = "test_gated"
	n.branch = "dominion"
	n.max_levels = 1
	n.levels_data.append(ld)
	return n


func test_branch_gate_blocks_when_spend_too_low() -> void:
	pp.debug_set_points(10)
	var n := _gated_node({"dominion": 3})
	assert_false(pp.can_upgrade(n), "gate {dominion:3} blocks at 0 dominion spend")


func test_branch_gate_opens_at_threshold() -> void:
	pp.debug_set_points(10)
	pp.upgrade(_DOM_CORE)       # +2 dominion
	pp.upgrade(_DOM_MART_ARTS)  # +1 dominion (martial arts L2)
	var n := _gated_node({"dominion": 3})
	assert_true(pp.can_upgrade(n), "gate {dominion:3} opens at 3 dominion spend")


func test_get_branch_spent_counts_only_matching_branch() -> void:
	pp.debug_set_points(10)
	assert_eq(pp.get_branch_spent("dominion"), 0,
		"auto-granted defaults cost 0 — no spend after reset")
	pp.upgrade(_DOM_CORE)
	assert_eq(pp.get_branch_spent("dominion"), 2, "dom_core L1 counts 2 toward dominion")
	assert_eq(pp.get_branch_spent("ingenuity"), 0, "no ingenuity spend yet")
	pp.upgrade(_MINOR_STUDIES)
	assert_eq(pp.get_branch_spent("ingenuity"), 1, "minor_studies counts toward ingenuity")


func test_hybrid_gate_requires_both_branches() -> void:
	pp.debug_set_points(10)
	pp.upgrade(_DOM_CORE)
	var n := _gated_node({"dominion": 2, "ingenuity": 1})
	assert_false(pp.can_upgrade(n), "hybrid gate blocked while ingenuity spend is 0")
	pp.upgrade(_MINOR_STUDIES)
	assert_true(pp.can_upgrade(n), "hybrid gate opens once both branches reach threshold")


func test_free_buy_bypasses_branch_gate() -> void:
	get_node("/root/DebugManager").enabled = true
	pp.debug_free_buy = true
	var n := _gated_node({"negation": 9})
	assert_true(pp.can_upgrade(n), "Free Buy ignores branch-spend gates")


# ── hero_sprite (cosmetic hero variant) ─────────────────────────────────────────

func test_reset_hero_sprite_defaults_to_player() -> void:
	pp.hero_sprite = "heroine"
	pp.reset()
	assert_eq(pp.hero_sprite, "player", "reset() restores default hero_sprite")


func test_serialize_includes_hero_sprite() -> void:
	pp.hero_sprite = "heroine"
	var data: Dictionary = pp.serialize()
	assert_eq(str(data.get("hero_sprite", "")), "heroine", "serialize() writes hero_sprite")


func test_deserialize_reads_hero_sprite() -> void:
	pp.deserialize({"hero_sprite": "heroine"})
	assert_eq(pp.hero_sprite, "heroine", "deserialize() reads hero_sprite")


func test_deserialize_missing_hero_sprite_defaults_to_player() -> void:
	pp.hero_sprite = "heroine"
	pp.deserialize({})
	assert_eq(pp.hero_sprite, "player",
		"deserialize() defaults hero_sprite to 'player' for old saves")


func test_hero_sprite_survives_save_load_round_trip() -> void:
	pp.hero_sprite = "heroine"
	var data: Dictionary = pp.serialize()
	pp.reset()  # back to "player"
	pp.deserialize(data)
	assert_eq(pp.hero_sprite, "heroine",
		"hero_sprite round-trips through serialize → deserialize")
