extends HBoxContainer

var _pool: String = "stance"


func _ready() -> void:
	$StanceButton.pressed.connect(func(): _select("stance"))
	$ResolveButton.pressed.connect(func(): _select("resolve"))
	$StaminaButton.pressed.connect(func(): _select("stamina"))
	_select("stance")
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func get_target_pool() -> String:
	return _pool


func _select(pool: String) -> void:
	_pool = pool
	$StanceButton.text  = "[Stance]"  if pool == "stance"  else "Stance"
	$ResolveButton.text = "[Resolve]" if pool == "resolve" else "Resolve"
	$StaminaButton.text = "[Stamina]" if pool == "stamina" else "Stamina"
