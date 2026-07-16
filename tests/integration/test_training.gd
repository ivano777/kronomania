extends GutTest

# Training room — DungeonManager.training_mode serves the Training Dummy
# outside the run flow: no run state touched, cleanly reversible.


func after_each() -> void:
	DungeonManager.end_training()


func test_training_mode_serves_dummy() -> void:
	DungeonManager.start_training()
	assert_true(DungeonManager.training_mode, "training mode set")
	var enemies := DungeonManager.current_enemies()
	assert_eq(enemies.size(), 1, "exactly one training enemy")
	var dummy := enemies[0] as CombatantData
	assert_not_null(dummy, "dummy resource loads as CombatantData")
	if dummy == null:
		return
	assert_eq(dummy.combatant_name, "Training Dummy")
	assert_eq(dummy.velocity_threshold, 0, "player always wins speed vs the dummy")
	assert_gt(dummy.max_wounds, 5, "dummy soaks enough hits to test a build")


func test_training_does_not_touch_run_state() -> void:
	var was_active := DungeonManager.run_active
	DungeonManager.start_training()
	assert_eq(DungeonManager.run_active, was_active, "run_active unchanged by training")
	DungeonManager.end_training()
	assert_false(DungeonManager.training_mode, "training mode cleared")
	assert_eq(DungeonManager.current_enemies().size(), 0,
		"no run, no training: no enemies served")


func test_dummy_attacks_off_by_default() -> void:
	DungeonManager.training_dummy_attacks = true  # stale value from a prior session
	DungeonManager.start_training()
	assert_false(DungeonManager.training_dummy_attacks,
		"dummy attack toggle resets to OFF on every training entry")


func test_training_restores_player_state_on_exit() -> void:
	PlayerProgression.saved_wounds = 1
	PlayerProgression.saved_fervor_size = 8
	PlayerProgression.saved_is_burned_out = false
	DungeonManager.start_training()
	# Simulate a rough sparring session writing back worse state.
	PlayerProgression.saved_wounds = 4
	PlayerProgression.saved_fervor_size = 10
	PlayerProgression.saved_is_burned_out = true
	DungeonManager.end_training()
	assert_eq(PlayerProgression.saved_wounds, 1, "wounds restored to pre-training value")
	assert_eq(PlayerProgression.saved_fervor_size, 8, "fervor restored")
	assert_false(PlayerProgression.saved_is_burned_out, "burnout restored")


func test_end_training_idempotent() -> void:
	PlayerProgression.saved_wounds = 2
	DungeonManager.start_training()
	PlayerProgression.saved_wounds = 5
	DungeonManager.end_training()
	assert_eq(PlayerProgression.saved_wounds, 2, "restored once")
	PlayerProgression.saved_wounds = 3
	DungeonManager.end_training()
	assert_eq(PlayerProgression.saved_wounds, 3,
		"second end_training must not re-apply the stale snapshot")
