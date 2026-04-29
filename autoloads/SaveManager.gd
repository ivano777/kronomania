# SaveManager — persists PlayerProgression and DungeonManager state to JSON.
# 3 save slots at user://saves/slot_{1,2,3}.json.
extends Node

const SAVE_DIR := "user://saves/"
const SAVE_VER := 1

## Last slot used for save or load (0 = none; auto-targets slot 1 on first explicit save).
var active_slot: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func save(slot: int) -> void:
	active_slot = slot
	var data: Dictionary = {}
	data.merge(PlayerProgression.serialize())
	data.merge(DungeonManager.serialize())
	data["version"]   = SAVE_VER
	data["timestamp"] = Time.get_datetime_string_from_system()
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager.save: cannot open '%s'" % _slot_path(slot))
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func load(slot: int) -> void:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("SaveManager.load: slot %d not found." % slot)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager.load: cannot open '%s'" % path)
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SaveManager.load: invalid JSON in slot %d." % slot)
		return
	active_slot = slot
	PlayerProgression.deserialize(parsed)
	DungeonManager.deserialize(parsed)


## Returns metadata for the slot picker UI.
## Keys: exists (bool), tier (int), points (int), timestamp (String).
func get_slot_meta(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"exists": false}
	return {
		"exists":      true,
		"tier":        int(parsed.get("tier", 1)),
		"points":      int(parsed.get("available_points", 0)),
		"timestamp":   str(parsed.get("timestamp", "")),
		"last_result": str(parsed.get("last_result", "")),
	}


func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if active_slot == slot:
		active_slot = 0


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot
