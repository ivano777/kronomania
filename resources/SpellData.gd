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
