class_name EchoPayload
extends RefCounted

# Typed view over the "echoing_spell" status payload (Phase 1). Lives on the PLAYER (the caster).
# Freezes Fervor + cast tool at cast time; current_kept_dice is the decaying kept-dice count that
# drives echo termination (focus keep already baked in, so CastSnapshot.keep_bonus is unused here —
# note write(include_keep=false)). Backing store is CombatStatus.stat_overrides; schema lives here.

var spell_path: String = ""
var target_index: int = -1
var frozen_fervor: int = 0
var current_kept_dice: int = 0
var em_level: int = 1
var cast: CastSnapshot = null


static func from_status(status: CombatStatus, default_tier: int) -> EchoPayload:
	var p := EchoPayload.new()
	var sov: Dictionary = status.stat_overrides
	p.spell_path = sov.get("spell_path", "") as String
	p.target_index = sov.get("target_index", -1) as int
	p.frozen_fervor = sov.get("frozen_fervor", 0) as int
	p.current_kept_dice = sov.get("current_kept_dice", 0) as int
	p.em_level = sov.get("em_level", 1) as int
	p.cast = CastSnapshot.read(sov, default_tier)
	return p


func to_status(status: CombatStatus) -> void:
	var sov := {}
	sov["spell_path"] = spell_path
	sov["target_index"] = target_index
	sov["frozen_fervor"] = frozen_fervor
	sov["current_kept_dice"] = current_kept_dice
	sov["em_level"] = em_level
	if cast != null:
		cast.write(sov, false)  # no cast_keep_bonus — focus keep lives in current_kept_dice
	status.stat_overrides = sov


## In-place update of the decaying kept-dice count (the only field that changes per echo pass).
static func set_kept(status: CombatStatus, kept: int) -> void:
	status.stat_overrides["current_kept_dice"] = kept
