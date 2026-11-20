extends Node
## Save slots (user://save_<slot>.json) and a small profile file that remembers
## which chapters have been unlocked across playthroughs.
##
## Slots: "auto" (checkpoints) and "1".."3" (manual).

const VERSION := 1
const MANUAL_SLOTS := ["1", "2", "3"]
const PROFILE_PATH := "user://profile.json"

var profile := {"unlocked": ["ch1"], "endings_seen": []}

## Tests switch this to a separate prefix so real saves are never touched.
var prefix := "user://save_"


func _ready() -> void:
	var p = DataLoader.load_json(PROFILE_PATH, null) if FileAccess.file_exists(PROFILE_PATH) else null
	if p is Dictionary:
		profile.merge(p, true)


func slot_path(slot: String) -> String:
	return prefix + slot + ".json"


func save_game(slot: String) -> bool:
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"chapter": GameState.current_chapter,
		"checkpoint": GameState.checkpoint,
		"state": GameState.to_dict(),
		"missions": MissionManager.to_dict(),
		"world": Router.collect_world_state(),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Could not write save %s" % slot)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func read_slot(slot: String) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {}
	var d = DataLoader.load_json(slot_path(slot), {})
	return d if d is Dictionary else {}


## Restores state from a slot and enters the saved chapter.
func load_game(slot: String) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	GameState.from_dict(data.get("state", {}))
	MissionManager.from_dict(data.get("missions", {}))
	return Router.start_chapter(data.get("chapter", "ch1"), data.get("world", {}))


func delete_slot(slot: String) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))


func has_any_save() -> bool:
	return latest_slot() != ""


## The most recently written slot, or "" if there are no saves.
func latest_slot() -> String:
	var best := ""
	var best_time := ""
	for slot in ["auto"] + MANUAL_SLOTS:
		var info := read_slot(slot)
		if info.is_empty():
			continue
		var t: String = info.get("saved_at", "")
		if best == "" or t > best_time:
			best = slot
			best_time = t
	return best


func unlock_chapter(id: String) -> void:
	if id not in profile["unlocked"]:
		profile["unlocked"].append(id)
		_save_profile()


func is_unlocked(id: String) -> bool:
	return id in profile["unlocked"]


func _save_profile() -> void:
	if prefix != "user://save_":
		return  # test mode
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "\t"))
