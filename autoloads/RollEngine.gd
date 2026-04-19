# RollEngine — stateless dice resolution engine.
# Implements: Build Pool → Roll → Keep → Flat → Outcome
# All functions are pure; no state is held here.
extends Node


# Roll `n` dice of `size` faces. Returns raw results as Array[int].
func roll_dice(n: int, size: int) -> Array[int]:
	var results: Array[int] = []
	for i in n:
		results.append(randi_range(1, size))
	return results


# Keep the best `keep_count` values from `dice`. Returns kept values.
# If keep_count >= dice.size(), all dice are kept.
func keep_best(dice: Array[int], keep_count: int) -> Array[int]:
	var sorted: Array[int] = dice.duplicate()
	sorted.sort()
	sorted.reverse()  # descending
	var count: int = mini(keep_count, sorted.size())
	return sorted.slice(0, count)


# Full resolution: Build Pool → Roll → Keep → Flat → total.
# tier       : int  — base pool size (1 die per Tier)
# die_size   : int  — face value of the stat die (4, 6, 8, or 10)
# keep_grade : int  — training grade: 0 → keep 1, 1 → keep 2, 2 → keep 3
# flat       : int  — additive bonus applied after Keep (0 for the slice)
# Returns a Dictionary with full audit trail for the log.
func resolve(tier: int, die_size: int, keep_grade: int, flat: int = 0) -> Dictionary:
	var pool_size: int = tier
	var keep_count: int = keep_grade + 1  # grade 0 → keep 1, etc.
	keep_count = mini(keep_count, pool_size)

	var dice := roll_dice(pool_size, die_size)
	var kept := keep_best(dice, keep_count)

	var total := 0
	for d in kept:
		total += d
	total += flat

	return {
		"dice":       dice,
		"kept":       kept,
		"total":      total,
		"pool_size":  pool_size,
		"die_size":   die_size,
		"keep_count": keep_count,
		"flat":       flat,
	}


# Returns true when the action qualifies as Fast (resolves in Fast Phase).
func is_fast(total: int, vt: int) -> bool:
	return total >= vt


# Returns true when the hit is Massive (2 Wounds instead of 1).
# Rule: (attack_total - guard) > defensive_size
# defensive_size is the numeric face of the defending stat die (e.g. 6 for d6).
func is_massive(attack_total: int, guard: int, defensive_size: int) -> bool:
	var overflow: int = attack_total - guard
	return overflow > defensive_size
