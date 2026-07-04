# SpellData — immutable configuration for a single spell or cantrip.
# Set in .tres files; referenced by NodeData.spell.
class_name SpellData
extends Resource

## Display name shown in the spell selection popup.
@export var spell_name: String = ""

## Human-readable description shown in the popup.
@export_multiline var description: String = ""

## Non-Ingenuity stat used for aspect dice. "" = pure Ingenuity spell.
## Accepted values: "dominion" | "negation" | ""
@export var aspect_stat: String = ""

## How many pool dice use aspect_stat instead of Ingenuity.
## Remaining (Tier - aspect_dice) dice are Ingenuity-tagged (count toward escalation).
@export_range(0, 4) var aspect_dice: int = 0

## Defense pool this spell pressures.
@export var target_pool: String = "stance"

## Flat bonus added after Keep (Channeling equivalent for spells).
@export var flat_bonus: int = 0

## If true: no Fervor die, no escalation; available during Burnout.
@export var is_cantrip: bool = false

## School tags matched against SpellBonusEffect.tag (e.g. "fire", "arcane").
@export var tags: PackedStringArray = []

# ── Discipline cast dispatch (data-driven; replaces spell_name string matches) ──

## Which discipline cast routine handles the player attack in _resolve_round_spell.
## "" = the standard _resolve_attack pipeline. "mind_rend" / "time_lock" = the wound-suppressing
## discipline casts (bypass _resolve_attack). Governs Phase 2 routing only.
@export var cast_handler: String = ""

## If true, the player attack roll is a weak pool=1 Ingenuity scratch with no school bonuses
## (Mind Detonation placement). If false, the normal cast roll is built.
@export var placement_scratch: bool = false

## status_id to prime on the target after a successful cast (Mind Detonation → "mind_detonation_primed").
## "" = primes nothing. The payload built for the primed status is discipline-specific.
@export var primes_status: String = ""
