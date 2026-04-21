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


# Keep the worst `keep_count` values from `dice`. Used for Desperation.
func keep_worst(dice: Array[int], keep_count: int) -> Array[int]:
	var sorted: Array[int] = dice.duplicate()
	sorted.sort()  # ascending — worst first
	var count: int = mini(keep_count, sorted.size())
	return sorted.slice(0, count)


# Full resolution: Build Pool → Roll → Keep → Flat → total.
# tier             : int — base pool size (1 die per Tier)
# die_size         : int — face value of the Ingenuity/primary stat die (4, 6, 8, or 10)
# keep_grade       : int — training grade: 0 → keep 1, 1 → keep 2, 2 → keep 3
# flat             : int — additive bonus applied after Keep (0 if unused)
# net_advantage    : int — positive = extra dice, negative = fewer dice;
#                          pool ≤ 0 triggers Desperation (roll 2, keep worst)
# fervor_size      : int — if > 0, roll one additive Fervor die of this face value
#                          after Keep; cannot be discarded; result included in total.
# aspect_stat_size : int — face value of the aspect stat die (for mixed-pool spells)
# aspect_count     : int — how many pool dice use aspect_stat_size; the rest use die_size
#                          (Ingenuity-tagged; count toward Fervor escalation on max-roll)
# Returns a Dictionary with full audit trail for the log.
func resolve(tier: int, die_size: int, keep_grade: int, flat: int = 0, net_advantage: int = 0, fervor_size: int = 0, aspect_stat_size: int = 0, aspect_count: int = 0) -> Dictionary:
	var pool_size: int = tier + net_advantage
	var desperation := pool_size <= 0

	var dice: Array[int]
	var kept: Array[int]
	var ingenuity_maxed_count := 0

	if desperation:
		# Desperation: roll 2 dice, keep the worst 1. All treated as Ingenuity-tagged.
		dice = roll_dice(2, die_size)
		kept = keep_worst(dice, 1)
		for d in dice:
			if d == die_size:
				ingenuity_maxed_count += 1
	elif aspect_count > 0 and aspect_stat_size > 0:
		# Mixed pool: aspect dice + ingenuity dice combined, keep best overall.
		var clamped_aspect: int = mini(aspect_count, pool_size)
		var ing_count: int = pool_size - clamped_aspect
		var aspect_dice_arr: Array[int] = roll_dice(clamped_aspect, aspect_stat_size)
		var ing_dice_arr: Array[int] = roll_dice(ing_count, die_size) if ing_count > 0 else []
		# Count Ingenuity maxes before combining (pre-keep, per rules).
		for d in ing_dice_arr:
			if d == die_size:
				ingenuity_maxed_count += 1
		# Combine and keep best.
		var combined: Array[int] = []
		combined.append_array(aspect_dice_arr)
		combined.append_array(ing_dice_arr)
		dice = combined
		var keep_count: int = mini(keep_grade + 1, pool_size)
		kept = keep_best(dice, keep_count)
	else:
		# Pure pool: all dice are Ingenuity-tagged.
		var keep_count: int = mini(keep_grade + 1, pool_size)
		dice = roll_dice(pool_size, die_size)
		kept = keep_best(dice, keep_count)
		for d in dice:
			if d == die_size:
				ingenuity_maxed_count += 1

	var total := flat
	for d in kept:
		total += d

	# Real Fervor die: additive post-Keep, cannot be discarded.
	var fervor_roll := 0
	var fervor_maxed := false
	if fervor_size > 0:
		fervor_roll = roll_dice(1, fervor_size)[0]
		total += fervor_roll
		fervor_maxed = (fervor_roll == fervor_size)

	return {
		"dice":                 dice,
		"kept":                 kept,
		"total":                total,
		"pool_size":            pool_size,
		"die_size":             die_size,
		"keep_count":           kept.size(),
		"flat":                 flat,
		"net_advantage":        net_advantage,
		"desperation":          desperation,
		"fervor_roll":          fervor_roll,
		"fervor_maxed":         fervor_maxed,
		"ingenuity_maxed_count": ingenuity_maxed_count,
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
