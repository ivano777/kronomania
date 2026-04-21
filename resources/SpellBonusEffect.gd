# SpellBonusEffect — bonus applied at spell resolution when the spell's tags match.
# Embedded in NodeData.bonus_effects on spell school nodes.
class_name SpellBonusEffect
extends Resource

## School tag that must appear in SpellData.tags for this bonus to apply.
@export var tag: String = ""

## "pool" adds dice to the roll pool; "keep" adds to the keep count.
@export_enum("pool", "keep") var bonus_type: String = "pool"

## Amount to add.
@export_range(1, 4) var value: int = 1

## Optional stat restriction (reserved for future use; "" = no restriction).
@export var stat: String = ""
