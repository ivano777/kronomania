extends RefCounted
# Pure arithmetic mirrors of CombatManager helpers.
# No class_name — keeps the global script cache clean.
# Used by test_combat_rules.gd; never imported by production code.


## Mirrors CombatManager._effective_tier().
## tier_override > 0 overrides base_tier. Items never cap Tier (equip-requirements rework).
func effective_tier(base_tier: int, tier_override: int) -> int:
	return tier_override if tier_override > 0 else base_tier


## Delegates to the real CombatMath.tier_wound_bonus (single source of truth after Phase 2).
func tier_wound_bonus(tier: int) -> int:
	return CombatMath.tier_wound_bonus(tier)


## Mirrors the Massive Wound condition used in CombatManager._resolve_attack().
## True when (attack - guard) > defensive_size.
func massive_check(attack: int, guard: int, defensive_size: int) -> bool:
	return (attack - guard) > defensive_size


## Mirrors RollEngine.is_fast() — also tested via RollEngine directly in test_roll_engine.gd.
func is_fast(attack_total: int, vt: int) -> bool:
	return attack_total >= vt


## Mirrors the breach condition from CombatManager._resolve_attack().
## True when attack_total >= guard (attack meets or exceeds guard → guard broken).
func is_breach(attack: int, guard: int) -> bool:
	return attack >= guard
