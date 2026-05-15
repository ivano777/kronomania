extends RefCounted
# Pure arithmetic mirrors of CombatManager helpers.
# No class_name — keeps the global script cache clean.
# Used by test_combat_rules.gd; never imported by production code.


## Mirrors CombatManager._effective_tier().
## tier_override > 0 overrides base_tier; result is then capped by tier_cap (0 = uncapped).
func effective_tier(base_tier: int, tier_override: int, tier_cap: int) -> int:
	var base: int = tier_override if tier_override > 0 else base_tier
	if tier_cap == 0:
		return base
	return mini(base, tier_cap)


## Mirrors CombatManager._tier_wound_bonus().
## +1 at Tier 2, +1 again at Tier 4 (cumulative +2 maximum).
func tier_wound_bonus(tier: int) -> int:
	return (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)


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
