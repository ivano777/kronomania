class_name CastSnapshot
extends RefCounted

# Typed view of the casting-tool values frozen at cast/prime time (Phase 1 of the discipline
# effect-handler refactor). Delayed payoffs (Mind Detonation explosion, Echo) read these instead
# of the live _player_cast_weapon, so the cast tool chosen at cast time governs the payoff.
#
# Backing store is CombatStatus.stat_overrides (unchanged, so the frozen test net keeps working);
# this class is the SINGLE place the cast_* key names + defaults live. Production code never touches
# the raw "cast_tier"/"cast_pool_bonus"/… strings — it goes through from_mod / read / write.
#
# Asymmetry documented once here: Echo omits keep_bonus (its focus keep is baked into
# current_kept_dice at arming), so writers pass include_keep=false for echoes.

var tier: int = 0
var pool_bonus: int = 0
var keep_bonus: int = 0
var flat_bonus: int = 0


## Captures the chosen cast tool's bonuses at cast time. `cast_tier` is the already-resolved
## effective tier (caller applies the tool's tier_cap via CombatMath.effective_tier).
static func from_mod(cast_tier: int, cast_mod: ActionModifier) -> CastSnapshot:
	var s := CastSnapshot.new()
	s.tier = cast_tier
	if cast_mod != null:
		s.pool_bonus = cast_mod.pool_bonus
		s.keep_bonus = cast_mod.keep_bonus
		s.flat_bonus = cast_mod.flat_bonus
	return s


## Reads the cast_* keys from a stat_overrides dict. Legacy statuses predating the snapshot lack
## "cast_tier" → fall back to `default_tier` (the caller's full effective tier).
static func read(sov: Dictionary, default_tier: int) -> CastSnapshot:
	var s := CastSnapshot.new()
	s.tier = sov.get("cast_tier", default_tier) as int
	s.pool_bonus = sov.get("cast_pool_bonus", 0) as int
	s.keep_bonus = sov.get("cast_keep_bonus", 0) as int
	s.flat_bonus = sov.get("cast_flat_bonus", 0) as int
	return s


## Writes the cast_* keys into a stat_overrides dict. `include_keep=false` for echoes (no
## cast_keep_bonus key — focus keep lives in current_kept_dice).
func write(sov: Dictionary, include_keep: bool = true) -> void:
	sov["cast_tier"] = tier
	sov["cast_pool_bonus"] = pool_bonus
	if include_keep:
		sov["cast_keep_bonus"] = keep_bonus
	sov["cast_flat_bonus"] = flat_bonus
