extends GutTest

# Tests for pure arithmetic rules extracted from CombatManager.
# Uses a lightweight helper class so CombatManager itself is never instantiated here.

const CombatRulesHelper = preload("res://tests/unit/combat_manager/combat_rules_helper.gd")

var _h: CombatRulesHelper


func before_each() -> void:
	_h = CombatRulesHelper.new()


# ── Tier wound bonus ──────────────────────────────────────────────────────────

func test_tier_wound_bonus(params = use_parameters([[1, 0], [2, 1], [3, 1], [4, 2]])) -> void:
	var tier: int = params[0]
	var expected: int = params[1]
	assert_eq(_h.tier_wound_bonus(tier), expected,
		"tier_wound_bonus(T%d) should be %d" % [tier, expected])


# ── effective_tier ────────────────────────────────────────────────────────────

func test_effective_tier_no_override() -> void:
	# base_tier=2, no override (0) → returns base_tier
	assert_eq(_h.effective_tier(2, 0), 2, "no override → base_tier")


func test_effective_tier_with_override() -> void:
	# tier_override=3 overrides base_tier=2 → 3
	assert_eq(_h.effective_tier(2, 3), 3, "tier_override wins over base_tier")


func test_effective_tier_override_less_than_base() -> void:
	# tier_override=1 overrides base_tier=2 → 1
	assert_eq(_h.effective_tier(2, 1), 1, "tier_override can be lower than base_tier")


# ── is_fast (VT check) ────────────────────────────────────────────────────────

func test_is_fast_exactly_at_vt() -> void:
	assert_true(_h.is_fast(10, 10), "total == VT → Fast (acts first)")


func test_is_fast_above_vt() -> void:
	assert_true(_h.is_fast(15, 10), "total > VT → Fast")


func test_is_fast_below_vt() -> void:
	assert_false(_h.is_fast(9, 10), "total < VT → Slow (enemy acts first)")


func test_is_fast_at_zero_vt() -> void:
	assert_true(_h.is_fast(0, 0), "total == 0 == VT → Fast")


# ── is_breach ─────────────────────────────────────────────────────────────────

func test_is_breach_attack_equals_guard() -> void:
	# Exactly meeting guard → breach (rules: "reaching exactly 0 is a breach")
	assert_true(_h.is_breach(5, 5), "attack == guard → breach")


func test_is_breach_attack_exceeds_guard() -> void:
	assert_true(_h.is_breach(6, 5), "attack > guard → breach")


func test_is_breach_attack_below_guard() -> void:
	assert_false(_h.is_breach(4, 5), "attack < guard → guard holds")


func test_is_breach_at_zero_guard() -> void:
	# Guard already at 0 — any attack (even 0) breaches.
	assert_true(_h.is_breach(0, 0), "attack 0 vs guard 0 → breach")


# ── massive_check ─────────────────────────────────────────────────────────────

func test_massive_check_overflow_greater_than_die() -> void:
	# overflow = 10, defensive_size = 4 → 10 > 4 → Massive
	assert_true(_h.massive_check(10, 0, 4), "overflow 10 > d4 → Massive")


func test_massive_check_overflow_equals_die() -> void:
	# overflow = 4, defensive_size = 4 → 4 NOT > 4 → not Massive
	assert_false(_h.massive_check(4, 0, 4), "overflow == defensive_size → NOT Massive")


func test_massive_check_overflow_less_than_die() -> void:
	assert_false(_h.massive_check(3, 0, 4), "overflow < defensive_size → NOT Massive")


func test_massive_check_with_nonzero_guard() -> void:
	# attack=8, guard=3 → overflow=5, defensive_size=4 → 5 > 4 → Massive
	assert_true(_h.massive_check(8, 3, 4), "overflow 5 > d4 with guard=3 → Massive")


func test_massive_check_uses_full_overflow(params = use_parameters([
	[6, 2, 4, false],   # overflow=4, 4 not > 4
	[7, 2, 4, true],    # overflow=5, 5 > 4
	[10, 5, 6, false],  # overflow=5, 5 not > 6 (d6)
	[12, 5, 6, true],   # overflow=7, 7 > 6
])) -> void:
	var attack: int = params[0]
	var guard: int = params[1]
	var die: int = params[2]
	var expected: bool = params[3]
	assert_eq(_h.massive_check(attack, guard, die), expected,
		"attack=%d guard=%d die=%d → massive=%s" % [attack, guard, die, str(expected)])
