class_name InterruptHandler extends Resource

## Reactive interrupt fired during _resolve_attack() before final outcome
## application. HARD RULE: data only, zero functional methods. All
## dispatching logic lives in CombatManager._resolve_interrupt().

@export var handler_id: String = ""

## Trigger event.
## Triggers in use: "on_massive_wound" (Meat for the Grinder, in _resolve_attack),
## "on_burnout" (Lucidity L2, in _escalate_fervor).
@export var trigger: String = ""

## Who this handler protects. "self" = the combatant carrying the handler.
## "enemy" = reserved for future symmetric mechanics, unused in A3.
@export var target: String = "self"

## Charges remaining. -1 = unlimited. Decremented on each successful use.
@export var charges: int = 1

## Processing order when multiple handlers fire on the same trigger.
## Lower priority = processed first. Documented priority table lives in CLAUDE.md.
@export var priority: int = 100

## Node that registered this handler. Debug and UI only.
@export var source_node_id: String = ""
