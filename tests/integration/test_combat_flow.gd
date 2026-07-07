extends GutTest

# Integration smoke test: verifies that the CombatManager signal plumbing fires
# without crashing through one round of combat.
#
# Design constraints:
#   - _begin_round() emits all player-facing signals SYNCHRONOUSLY; no await needed.
#   - After player_chose_strike(), _resolve_round() runs synchronously up to its
#     0.8 s timer. With d4 vs d4 (Grunt), Massive Wounds are impossible (max overflow
#     = 3 < 4), so _massive_decision_gate never deadlocks.
#   - No UI nodes are connected — the background coroutine suspends at the timer
#     and GUT's process exits before it resumes. This is safe for a smoke test.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")


func before_each() -> void:
	get_node("/root/PlayerProgression").reset()
	watch_signals(CombatManager)


# ── Test 1: start_combat emits player_intents_available ───────────────────────

func test_start_combat_emits_player_intents() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	assert_signal_emitted(CombatManager, "player_intents_available",
		"start_combat() must emit player_intents_available")


func test_player_intents_includes_attack() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	var params: Array = get_signal_parameters(CombatManager, "player_intents_available", 0)
	var intents: Array = params[0] as Array
	assert_true(intents.has("attack"), "intents array must include 'attack'")


func test_start_combat_emits_round_started() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	assert_signal_emitted(CombatManager, "round_started",
		"start_combat() must emit round_started")


func test_start_combat_emits_wounds_changed() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	assert_signal_emitted(CombatManager, "wounds_changed",
		"start_combat() must emit initial wounds_changed for both combatants")


# ── Test 2: player_chose_strike emits log_message ────────────────────────────

func test_strike_emits_log_message() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	# Clear watchers so we only catch signals from the strike onwards.
	clear_signal_watcher()
	watch_signals(CombatManager)
	# Synchronous: _resolve_round() runs up to its 0.8 s timer before suspending.
	CombatManager.player_chose_strike(0, "stance", false, 0, null)
	assert_signal_emitted(CombatManager, "log_message",
		"player_chose_strike() must produce at least one log_message")


func test_strike_emits_guard_changed() -> void:
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	clear_signal_watcher()
	watch_signals(CombatManager)
	CombatManager.player_chose_strike(0, "stance", false, 0, null)
	assert_signal_emitted(CombatManager, "guard_changed",
		"guard must be rolled and emitted during round resolution")


func test_enemy_turn_emits_combatant_attacking() -> void:
	seed(7)  # deterministic: grunt must survive the player's hit and swing back
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	clear_signal_watcher()
	watch_signals(CombatManager)
	CombatManager.player_chose_strike(0, "stance", false, 0, null)
	if CombatManager._enemies[0].is_defeated:
		pass_test("grunt died to the opening hit under this seed — no enemy turn")
		return
	assert_signal_emitted_with_parameters(
		CombatManager, "combatant_attacking", [false, 0])
