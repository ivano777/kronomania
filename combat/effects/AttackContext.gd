class_name AttackContext
extends RefCounted

# Typed context for a single _resolve_attack pass (Phase 1). Replaces the free-floating did_breach
# local and the ad-hoc {pool, attacker} dict passed to _process_statuses_hook. In Phase 2 the
# discipline effect handlers read/mutate this instead of reaching into spine locals — it is the
# surface the generic dispatch loops hand to each handler.

var attacker_state: CombatantState = null
var defender_state: CombatantState = null
var defender_index: int = -1
var attacker_is_player: bool = false
var target_pool: String = ""
var attack_total: int = 0
var guard_value: int = 0       # defender guard at the moment of the breach comparison
var did_breach: bool = false
var is_massive: bool = false
var wounds_pending: int = 0
