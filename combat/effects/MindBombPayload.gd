class_name MindBombPayload
extends RefCounted

# Typed view over the "mind_detonation_primed" status payload (Phase 1). Freezes the Fervor + cast
# tool at prime time so the Phase 2.1 explosion uses those, not live values. Backing store is
# CombatStatus.stat_overrides; the key schema lives here only.

var fervor_at_prime: int = 0
var md_level: int = 1
var cast: CastSnapshot = null


static func from_status(status: CombatStatus, default_tier: int) -> MindBombPayload:
	var p := MindBombPayload.new()
	var sov: Dictionary = status.stat_overrides
	p.fervor_at_prime = sov.get("fervor_at_prime", 0) as int
	p.md_level = sov.get("md_level", 1) as int
	p.cast = CastSnapshot.read(sov, default_tier)
	return p


func to_status(status: CombatStatus) -> void:
	var sov := {}
	sov["fervor_at_prime"] = fervor_at_prime
	sov["md_level"] = md_level
	if cast != null:
		cast.write(sov, true)
	status.stat_overrides = sov
