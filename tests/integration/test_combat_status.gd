extends GutTest

# Tests for CombatStatus helpers on CombatManager (Phase A1 — Group A).
# Uses start_combat() to get a live _player CombatantState; no UI needed.

const _PLAYER_DATA = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA  = preload("res://resources/data/enemy_grunt.tres")


func before_each() -> void:
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])


func _make_status(id: String, duration: int) -> CombatStatus:
	var s = CombatStatus.new()
	s.status_id = id
	s.duration_rounds = duration
	return s


# ── 1. Add and has ────────────────────────────────────────────────────────────

func test_add_and_has() -> void:
	var s = _make_status("test_status", 2)
	CombatManager._add_status(CombatManager._player, s)
	assert_true(CombatManager._has_status(CombatManager._player, "test_status"),
		"_has_status should return true after _add_status")


# ── 2. Stat override applied and removed ─────────────────────────────────────

func test_stat_override_applied() -> void:
	var s = _make_status("ing_override", 2)
	s.stat_overrides = { "ingenuity_size": 12 }
	CombatManager._add_status(CombatManager._player, s)
	assert_eq(CombatManager._stat_size(CombatManager._player, "ingenuity_size"), 12,
		"_stat_size should return override value when status is active")


func test_stat_override_removed() -> void:
	var base = CombatManager._stat_size(CombatManager._player, "ingenuity_size")
	var s = _make_status("ing_override", 2)
	s.stat_overrides = { "ingenuity_size": 12 }
	CombatManager._add_status(CombatManager._player, s)
	CombatManager._remove_status(CombatManager._player, "ing_override")
	assert_eq(CombatManager._stat_size(CombatManager._player, "ingenuity_size"), base,
		"_stat_size should return base value after status removed")


# ── 3. Deduplication on add ───────────────────────────────────────────────────

func test_deduplication_on_add() -> void:
	var s1 = _make_status("test_status", 3)
	var s2 = _make_status("test_status", 99)
	CombatManager._add_status(CombatManager._player, s1)
	CombatManager._add_status(CombatManager._player, s2)
	assert_eq(CombatManager._player.active_statuses.size(), 1,
		"Adding same status_id twice should replace, not stack")
	assert_eq(CombatManager._player.active_statuses[0].duration_rounds, 99,
		"Second add should replace with the new instance")


# ── 4. Tick and expiry ────────────────────────────────────────────────────────

func test_tick_and_expiry() -> void:
	var s = _make_status("tick_status", 2)
	CombatManager._add_status(CombatManager._player, s)
	CombatManager._tick_statuses(CombatManager._player)
	assert_true(CombatManager._has_status(CombatManager._player, "tick_status"),
		"Status with 2 rounds should survive after 1 tick")
	CombatManager._tick_statuses(CombatManager._player)
	assert_false(CombatManager._has_status(CombatManager._player, "tick_status"),
		"Status with 2 rounds should expire after 2 ticks")


# ── 5. Permanent status never expires ────────────────────────────────────────

func test_permanent_status_never_expires() -> void:
	var s = _make_status("perm_status", -1)
	CombatManager._add_status(CombatManager._player, s)
	CombatManager._tick_statuses(CombatManager._player)
	CombatManager._tick_statuses(CombatManager._player)
	CombatManager._tick_statuses(CombatManager._player)
	assert_true(CombatManager._has_status(CombatManager._player, "perm_status"),
		"Permanent status (duration=-1) should never expire from ticking")


# ── 6. _get_status returns null for missing id ────────────────────────────────

func test_get_status_null_for_missing() -> void:
	var result = CombatManager._get_status(CombatManager._player, "nonexistent")
	assert_null(result, "_get_status should return null for unknown status_id")


# ── 7. Combat regression — active_statuses starts empty ──────────────────────

func test_active_statuses_empty_at_combat_start() -> void:
	assert_eq(CombatManager._player.active_statuses.size(), 0,
		"active_statuses must be empty when combat begins")


func test_active_statuses_empty_for_enemies() -> void:
	for enemy in CombatManager._enemies:
		assert_eq(enemy.active_statuses.size(), 0,
			"Enemy active_statuses must be empty at combat start")
