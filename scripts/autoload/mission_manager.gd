extends Node
## Mission and objective tracking.
##
## Missions are defined per chapter in data/chapters/<id>.json:
##   "missions": {
##     "ch1_main": {
##       "title": "...", "main": true,
##       "objectives": [ {"id": "talk", "text": "...", "count": 1, "marker": "gasana"}, ... ],
##       "on_complete": [ effects... ]
##     }
##   }
## Objectives are sequential: only the current one accepts progress.

signal mission_started(mission_id: String)
signal objective_changed(mission_id: String)
signal mission_completed(mission_id: String)

var _defs := {}      # mission_id -> definition
var _state := {}     # mission_id -> {"status": "active"|"completed", "index": int, "progress": int}
var _order := []     # start order, for stable HUD listing


func reset() -> void:
	_state.clear()
	_order.clear()


func register_missions(defs: Dictionary) -> void:
	for id in defs:
		_defs[id] = defs[id]


func get_definition(id: String) -> Dictionary:
	return _defs.get(id, {})


func start_mission(id: String) -> void:
	if not _defs.has(id):
		push_error("Unknown mission: %s" % id)
		return
	if _state.has(id):
		return
	_state[id] = {"status": "active", "index": 0, "progress": 0}
	_order.append(id)
	mission_started.emit(id)
	objective_changed.emit(id)
	UI.toast(("New: %s" % _defs[id].get("title", id)), "mission")


## Adds progress to an objective. Ignored unless it is that mission's current objective.
func progress(id: String, objective_id: String, amount: int = 1) -> bool:
	if not is_active(id) or current_objective_id(id) != objective_id:
		return false
	var st: Dictionary = _state[id]
	var obj: Dictionary = _defs[id]["objectives"][st["index"]]
	st["progress"] += amount
	if st["progress"] >= int(obj.get("count", 1)):
		st["index"] += 1
		st["progress"] = 0
		GameState.apply_effects(obj.get("on_complete", []))
		if st["index"] >= _defs[id]["objectives"].size():
			_complete(id)
			return true
	objective_changed.emit(id)
	return true


func _complete(id: String) -> void:
	_state[id]["status"] = "completed"
	objective_changed.emit(id)
	mission_completed.emit(id)
	UI.toast("Completed: %s" % _defs[id].get("title", id), "mission")
	GameState.apply_effects(_defs[id].get("on_complete", []))


func is_started(id: String) -> bool:
	return _state.has(id)


func is_active(id: String) -> bool:
	return _state.has(id) and _state[id]["status"] == "active"


func is_completed(id: String) -> bool:
	return _state.has(id) and _state[id]["status"] == "completed"


func current_objective(id: String) -> Dictionary:
	if not is_active(id):
		return {}
	var st: Dictionary = _state[id]
	return _defs[id]["objectives"][st["index"]]


func current_objective_id(id: String) -> String:
	return current_objective(id).get("id", "")


func current_progress(id: String) -> int:
	return int(_state.get(id, {}).get("progress", 0))


## How many units of an objective are done (full count once it is behind us).
func objective_amount_done(id: String, objective_id: String) -> int:
	if not _state.has(id):
		return 0
	var objs: Array = _defs[id]["objectives"]
	for i in objs.size():
		if objs[i]["id"] == objective_id:
			var idx: int = _state[id]["index"]
			if is_completed(id) or i < idx:
				return int(objs[i].get("count", 1))
			if i == idx:
				return current_progress(id)
			return 0
	return 0


## Active missions, main missions first.
func active_missions() -> Array:
	var main := []
	var side := []
	for id in _order:
		if is_active(id):
			if _defs[id].get("main", false):
				main.append(id)
			else:
				side.append(id)
	return main + side


func to_dict() -> Dictionary:
	return {"state": _state.duplicate(true), "order": _order.duplicate()}


func from_dict(d: Dictionary) -> void:
	reset()
	_state = d.get("state", {}).duplicate(true)
	_order = d.get("order", []).duplicate()
	for id in _state:
		_state[id]["index"] = int(_state[id]["index"])
		_state[id]["progress"] = int(_state[id]["progress"])
	for id in _order:
		objective_changed.emit(id)
