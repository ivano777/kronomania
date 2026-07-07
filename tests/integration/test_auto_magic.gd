extends GutTest

# ATK Auto — magic parity with Strike.
# In ATK Auto mode, clicking the Magic intent must auto-cast the pinned spell
# (RoundHUD._on_intent_magic gate → _try_auto_magic → cantrip_selected/spell_selected).
# With no pinned default it must fall through to the manual panel.

const _MINOR_STUDIES = preload("res://resources/data/nodes/ability_minor_studies.tres")
const _ROUND_HUD     = preload("res://scenes/battle/RoundHUD.tscn")

var _hud: RoundHUD


func before_each() -> void:
	PlayerProgression.reset()
	# Learn a cantrip (Arcane Bolt) via Minor Studies L1 — set the level directly for determinism.
	PlayerProgression.node_levels[_MINOR_STUDIES] = 1
	PlayerProgression.combat_prefs.atk_mode = "auto"
	_hud = _ROUND_HUD.instantiate() as RoundHUD
	add_child_autofree(_hud)
	await wait_frames(1)
	# Cantrips available, true spells not (no Spellcasting) — matches a Minor-Studies-only build.
	_hud._can_cantrip = true
	_hud._can_cast_spell = false


func test_auto_magic_fires_pinned_cantrip() -> void:
	PlayerProgression.combat_prefs.defaults["magic"] = "Arcane Bolt"
	watch_signals(_hud)
	_hud._on_intent_magic()
	assert_signal_emitted(_hud, "cantrip_selected",
		"ATK Auto + pinned cantrip must auto-emit cantrip_selected")
	var params: Array = get_signal_parameters(_hud, "cantrip_selected", 0)
	var sp: SpellData = params[0] as SpellData
	assert_eq(sp.spell_name, "Arcane Bolt", "must fire the pinned spell")


func test_no_default_falls_through_to_manual() -> void:
	PlayerProgression.combat_prefs.defaults.erase("magic")
	watch_signals(_hud)
	var fired: bool = _hud._try_auto_magic()
	assert_false(fired, "no pinned default → _try_auto_magic returns false (manual panel opens)")
	assert_signal_not_emitted(_hud, "cantrip_selected",
		"no default must not auto-cast")


func test_pinned_true_spell_during_burnout_falls_through() -> void:
	# Pin a name that resolves only as a true spell; with _can_cast_spell false (Burnout),
	# auto must decline so the manual panel can still offer cantrips.
	PlayerProgression.combat_prefs.defaults["magic"] = "Arcane Missile"
	watch_signals(_hud)
	var fired: bool = _hud._try_auto_magic()
	assert_false(fired, "true spell pinned but not castable → returns false")
	assert_signal_not_emitted(_hud, "spell_selected",
		"blocked true spell must not auto-cast")
