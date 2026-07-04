class_name TimeLockPayload
extends RefCounted

# Typed view over the "time_locked" status payload (Phase 1). Two-phase: ARMED (waiting for the next
# player attack on this enemy) → FROZEN (a guard pool is locked for `skip_resets` rounds at
# `frozen_value`). Backing store is CombatStatus.stat_overrides; phase names + key schema live here.

const PHASE_ARMED := "armed"
const PHASE_FROZEN := "frozen"

var phase: String = PHASE_ARMED
var locked_pool: String = ""
var skip_resets: int = 0
var frozen_value: int = 0


static func from_status(status: CombatStatus) -> TimeLockPayload:
	var p := TimeLockPayload.new()
	var sov: Dictionary = status.stat_overrides
	p.phase = sov.get("phase", "") as String
	p.locked_pool = sov.get("locked_pool", "") as String
	p.skip_resets = sov.get("skip_resets", 0) as int
	p.frozen_value = sov.get("frozen_value", 0) as int
	return p


func to_status(status: CombatStatus) -> void:
	status.stat_overrides = {
		"phase": phase,
		"locked_pool": locked_pool,
		"skip_resets": skip_resets,
		"frozen_value": frozen_value,
	}
