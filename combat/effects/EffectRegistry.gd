class_name EffectRegistry
extends RefCounted

# Maps status_id → CombatEffect handler (Phase 2). Lazy singleton dict of stateless handlers. The
# spine (_resolve_attack / _process_statuses_hook / _end_of_round) and StatusOps.tick look up
# handlers here instead of matching status_id literals — adding a discipline = add a handler + one
# registry entry, no spine edit.

static var _handlers: Dictionary = {}


static func get_handler(status_id: String) -> CombatEffect:
	if _handlers.is_empty():
		_handlers = {
			"hex_marked": HexEffect.new(),
			"time_locked": TimeLockEffect.new(),
			"echoing_spell": EchoEffect.new(),
			"mind_detonation_primed": MindBombEffect.new(),
		}
	return _handlers.get(status_id, null)
