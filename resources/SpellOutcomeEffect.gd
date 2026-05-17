class_name SpellOutcomeEffect extends Resource

## ARCHITECTURE BOUNDARY:
##
## SpellOutcomeEffect describes effects that resolve AFTER the spell's attack roll
## has been computed and outcome (hit/breach) determined.
##
## For modifiers to the caster's roll itself (e.g. +1 flat to Arcane Missile,
## Keep 2 on all arcane spells), use SpellBonusEffect with spell_id filter —
## those apply DURING roll construction in _resolve_round_spell.
##
## The "bonus_keep" and "bonus_flat" effect_types here are reserved for
## conditional bonuses tied to outcome state (e.g. +1 Keep on the detonation if
## Stance was breached this round). They are NOT for flat upgrades to the
## caster's roll — those belong in SpellBonusEffect.
##
## If the effect must persist across rounds, use effect_type="apply_status" with
## a CombatStatus referenced in status_to_apply. NEVER add a duration field to
## SpellOutcomeEffect — persistence is CombatStatus's job.
##
## HARD RULE: data only, zero functional methods. All processing logic lives in
## CombatManager._apply_spell_outcome_effects(), never here.

## Filter — only applies when the resolved spell's spell_name matches.
## Empty string = applies to all spells.
@export var spell_id: String = ""

## When to apply the effect during resolution.
##   "on_cast"   — applied immediately when the spell is cast, regardless of outcome
##   "on_hit"    — applied when breach happened on the spell's target_pool
##   "on_breach" — alias of on_hit; kept for design clarity. Treated identically.
@export var trigger: String = "on_hit"

## Who receives the effect.
##   "enemy" — the target of the spell (defender)
##   "self"  — the caster
@export var target: String = "enemy"

## Which defense pool of the target is affected. Empty when effect_type does not
## concern a pool (e.g. apply_status).
@export var target_pool: String = ""

## What the effect does.
##   "debuff_flat"   — adds value (negative int) to target_pool's next guard total
##                     (one-shot, consumed on next defense roll for that pool)
##   "debuff_keep"   — adds value (negative int) to target_pool's next guard keep
##                     grade (one-shot, consumed on next defense roll, clamped ≥ 0)
##   "bonus_keep"    — reserved: conditional keep bonus tied to outcome state
##   "bonus_flat"    — reserved: conditional flat bonus tied to outcome state
##   "apply_status"  — applies status_to_apply to the target (duplicated per apply)
@export var effect_type: String = ""

@export var value: int = 0

## Optional condition evaluated at apply-time. Supported values:
##   ""                              — no condition, always applies
##   "if_stance_breached_this_round"
##   "if_resolve_breached_this_round"
##   "if_stamina_breached_this_round"
##   "if_fervor_at_cap"
@export var condition: String = ""

## Status to apply when effect_type == "apply_status".
## Duplicated before adding so each application is independent.
@export var status_to_apply: CombatStatus

## Node that authored this effect. Debug/UI only.
@export var source_node_id: String = ""
