extends GutTest

# Unit tests for the Group A4 SpellOutcomeEffect resource and related schema additions.
# Tests are resource-instantiation and field-default checks only — no autoload required.


func test_spell_outcome_effect_defaults() -> void:
	var effect := SpellOutcomeEffect.new()
	assert_eq(effect.spell_id, "", "spell_id default empty")
	assert_eq(effect.trigger, "on_hit", "trigger default on_hit")
	assert_eq(effect.target, "enemy", "target default enemy")
	assert_eq(effect.target_pool, "", "target_pool default empty")
	assert_eq(effect.effect_type, "", "effect_type default empty")
	assert_eq(effect.value, 0, "value default 0")
	assert_eq(effect.condition, "", "condition default empty")
	assert_null(effect.status_to_apply, "status_to_apply default null")
	assert_eq(effect.source_node_id, "", "source_node_id default empty")


func test_spell_bonus_effect_spell_id_field() -> void:
	var be := SpellBonusEffect.new()
	assert_eq(be.spell_id, "", "SpellBonusEffect.spell_id default empty")


func test_node_level_data_outcome_effects_field() -> void:
	var ld := NodeLevelData.new()
	assert_not_null(ld.outcome_effects, "outcome_effects field exists")
	assert_eq(ld.outcome_effects.size(), 0, "outcome_effects default empty array")


func test_spell_outcome_effect_can_set_fields() -> void:
	var effect := SpellOutcomeEffect.new()
	effect.spell_id = "arcane_missile"
	effect.trigger = "on_cast"
	effect.target = "self"
	effect.target_pool = "stance"
	effect.effect_type = "debuff_flat"
	effect.value = -3
	effect.condition = "if_stance_breached_this_round"
	effect.source_node_id = "spellcasting"
	assert_eq(effect.spell_id, "arcane_missile")
	assert_eq(effect.trigger, "on_cast")
	assert_eq(effect.target, "self")
	assert_eq(effect.target_pool, "stance")
	assert_eq(effect.effect_type, "debuff_flat")
	assert_eq(effect.value, -3)
	assert_eq(effect.condition, "if_stance_breached_this_round")
	assert_eq(effect.source_node_id, "spellcasting")


func test_spell_outcome_effect_with_status() -> void:
	var status := CombatStatus.new()
	status.status_id = "test_status"
	status.duration_rounds = 2

	var effect := SpellOutcomeEffect.new()
	effect.effect_type = "apply_status"
	effect.status_to_apply = status

	assert_not_null(effect.status_to_apply)
	assert_eq(effect.status_to_apply.status_id, "test_status")
	assert_eq(effect.status_to_apply.duration_rounds, 2)
