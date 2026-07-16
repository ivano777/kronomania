extends GutTest

# RoundHUD presentation behaviors that need a live scene tree:
# the reversed combat log (newest line on top) and the floating decision
# modals (Burnout / Massive Wound), which must fit inside the viewport.

const _ROUND_HUD := preload("res://scenes/battle/RoundHUD.tscn")

var _hud: RoundHUD


func before_each() -> void:
	_hud = _ROUND_HUD.instantiate() as RoundHUD
	add_child_autofree(_hud)


func _log_label() -> RichTextLabel:
	return _hud.get_node("LogScroll/LogText") as RichTextLabel


# ── Combat log order ──────────────────────────────────────────────────────────

func test_add_log_puts_newest_line_on_top() -> void:
	_hud.add_log("first")
	_hud.add_log("second")
	_hud.add_log("third")
	assert_eq(_log_label().text, "third\nsecond\nfirst",
		"newest log line renders above older ones")


func test_clear_log_forgets_old_lines() -> void:
	_hud.add_log("stale")
	_hud.clear_log()
	_hud.add_log("fresh")
	assert_eq(_log_label().text, "fresh", "cleared log holds only new lines")


# ── Decision modals ───────────────────────────────────────────────────────────

func test_burnout_modal_fits_inside_viewport() -> void:
	_hud.show_burnout_prompt(2)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := _hud._burnout_overlay as Control
	assert_true(overlay.visible, "burnout modal visible after prompt")
	var panels := overlay.find_children("*", "PanelContainer", true, false)
	assert_eq(panels.size(), 1, "modal has exactly one panel")
	var rect := (panels[0] as Control).get_global_rect()
	var view := _hud.get_viewport().get_visible_rect()
	assert_true(view.encloses(rect),
		"burnout panel fully inside viewport (panel %s, viewport %s)" % [rect, view])


func test_massive_modal_fits_inside_viewport() -> void:
	_hud.show_massive_prompt(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := _hud._massive_overlay as Control
	assert_true(overlay.visible, "massive modal visible after prompt")
	var panels := overlay.find_children("*", "PanelContainer", true, false)
	assert_eq(panels.size(), 1, "modal has exactly one panel")
	var rect := (panels[0] as Control).get_global_rect()
	var view := _hud.get_viewport().get_visible_rect()
	assert_true(view.encloses(rect),
		"massive panel fully inside viewport (panel %s, viewport %s)" % [rect, view])


func test_burnout_choice_hides_modal_and_emits_signal() -> void:
	watch_signals(_hud)
	_hud.show_burnout_prompt(1)
	_hud._on_burnout_choice(true)
	assert_false((_hud._burnout_overlay as Control).visible,
		"burnout modal hidden after choice")
	assert_signal_emitted_with_parameters(_hud, "burnout_prevent_chosen", [true])


func test_massive_choice_hides_modal_and_emits_signal() -> void:
	watch_signals(_hud)
	_hud.show_massive_prompt(1)
	_hud._on_massive_choice(false)
	assert_false((_hud._massive_overlay as Control).visible,
		"massive modal hidden after choice")
	assert_signal_emitted_with_parameters(_hud, "wound_degrade_chosen", [false])
