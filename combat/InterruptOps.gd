class_name InterruptOps
extends RefCounted

# Interrupt-handler bookkeeping — Layer 2 of the CombatManager refactor (Phase 3).
#
# Stateless static helpers over CombatantState.interrupt_handlers. No signals, no await.
# The awaited resolvers (_resolve_interrupt, _resolve_meat_for_the_grinder, _try_prevent_burnout)
# stay in CombatManager — they emit signals and await player-decision gates.


## Registers a handler on a combatant. No deduplication — two distinct handlers with the same
## trigger may coexist (each manages its own charges).
static func register(state: CombatantState, handler: InterruptHandler) -> void:
	state.interrupt_handlers.append(handler)


## Returns all handlers matching the trigger that still have charges (charges > 0 or -1 = unlimited),
## sorted by priority ascending.
static func find(state: CombatantState, trigger: String) -> Array[InterruptHandler]:
	var matches: Array[InterruptHandler] = []
	for h in state.interrupt_handlers:
		if h.trigger == trigger and (h.charges > 0 or h.charges == -1):
			matches.append(h)
	matches.sort_custom(func(a, b): return a.priority < b.priority)
	return matches


## Decrements a handler's charges (no-op for unlimited/-1 or already-spent handlers).
static func consume_charge(handler: InterruptHandler) -> void:
	if handler.charges > 0:
		handler.charges -= 1
