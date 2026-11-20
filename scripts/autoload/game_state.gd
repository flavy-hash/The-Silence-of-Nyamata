extends Node
## Narrative state for the current playthrough: story flags (the choice tracker),
## NPC trust, inventory, chapter and checkpoint.
##
## Dialogue, missions and world objects never change state directly. They describe
## *conditions* and *effects* as data (see check() and apply_effects()), so chapter
## content stays in JSON and is easy to review and extend.
##
## Important design rule: choices change relationships, side missions and endings.
## They never change the historical reality the story is set in.

signal flag_changed(key: String, value)
signal trust_changed(npc_id: String, value: int)
signal inventory_changed(item_id: String, count: int)
signal story_event(event_name: String, data: Dictionary)

const ITEMS_PATH := "res://data/items.json"

var current_chapter := "ch1"
var checkpoint := "start"
var flags := {}
var trust := {}
var inventory := {}

## Static item definitions (name, description) loaded from data/items.json.
var items := {}

## Reasons the player currently cannot move (dialogue, cinematic, menu...).
var _locks := {}


func _ready() -> void:
	items = DataLoader.load_json(ITEMS_PATH, {})


func reset() -> void:
	current_chapter = "ch1"
	checkpoint = "start"
	flags.clear()
	trust.clear()
	inventory.clear()
	_locks.clear()


# --- Flags ---------------------------------------------------------------------

func set_flag(key: String, value = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: String, default = false):
	return flags.get(key, default)


# --- Trust ---------------------------------------------------------------------

func get_trust(npc_id: String) -> int:
	return int(trust.get(npc_id, 0))


func add_trust(npc_id: String, delta: int) -> void:
	trust[npc_id] = get_trust(npc_id) + delta
	trust_changed.emit(npc_id, trust[npc_id])


# --- Inventory -----------------------------------------------------------------

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = item_count(item_id) + count
	inventory_changed.emit(item_id, inventory[item_id])


func remove_item(item_id: String, count: int = 1) -> bool:
	if item_count(item_id) < count:
		return false
	inventory[item_id] = item_count(item_id) - count
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	inventory_changed.emit(item_id, item_count(item_id))
	return true


func item_name(item_id: String) -> String:
	return items.get(item_id, {}).get("name", item_id.capitalize())


# --- Input locks -----------------------------------------------------------------

func lock(reason: String) -> void:
	_locks[reason] = true


func unlock(reason: String) -> void:
	_locks.erase(reason)


func is_locked(reason: String = "") -> bool:
	if reason == "":
		return not _locks.is_empty()
	return _locks.has(reason)


# --- Conditions ------------------------------------------------------------------
## A condition list is an Array of Dictionaries; all must pass. Supported forms:
##   {"flag": "x"}                       flag is truthy
##   {"flag": "x", "equals": value}      flag equals value
##   {"not_flag": "x"}                   flag is falsy / unset
##   {"trust": "aline", "min": 2}        trust >= min (also "max")
##   {"item": "water", "count": 1}       inventory has at least count
##   {"mission_active": "id"}
##   {"mission_done": "id"}
##   {"mission_not_started": "id"}
##   {"objective": "mission_id:objective_id"}   that objective is the current one
##   {"intensity": "reduced"}            player's intensity setting

func check(conditions) -> bool:
	if conditions == null:
		return true
	if conditions is Dictionary:
		conditions = [conditions]
	for c in conditions:
		if not _check_one(c):
			return false
	return true


func _check_one(c: Dictionary) -> bool:
	if c.has("flag"):
		var v = flags.get(c["flag"], false)
		if c.has("equals"):
			return v == c["equals"]
		return bool(v)
	if c.has("not_flag"):
		return not bool(flags.get(c["not_flag"], false))
	if c.has("trust"):
		var t := get_trust(c["trust"])
		if c.has("min") and t < int(c["min"]):
			return false
		if c.has("max") and t > int(c["max"]):
			return false
		return true
	if c.has("item"):
		return item_count(c["item"]) >= int(c.get("count", 1))
	if c.has("mission_active"):
		return MissionManager.is_active(c["mission_active"])
	if c.has("mission_done"):
		return MissionManager.is_completed(c["mission_done"])
	if c.has("mission_not_started"):
		return not MissionManager.is_started(c["mission_not_started"])
	if c.has("objective"):
		var parts: PackedStringArray = String(c["objective"]).split(":")
		return MissionManager.current_objective_id(parts[0]) == parts[1]
	if c.has("intensity"):
		return Settings.intensity == c["intensity"]
	push_warning("Unknown condition: %s" % [c])
	return false


# --- Effects ---------------------------------------------------------------------
## An effect list is an Array of Dictionaries applied in order. Supported forms:
##   {"set_flag": "x", "value": v}       (value defaults to true)
##   {"trust": "aline", "delta": 1}
##   {"give_item": "water", "count": 1}
##   {"take_item": "water", "count": 1}
##   {"start_mission": "id"}
##   {"progress": "mission_id:objective_id", "amount": 1}
##   {"event": "name", "data": {...}}    picked up by the chapter director
##   {"toast": "text"}                   short on-screen notification

func apply_effects(effects) -> void:
	if effects == null:
		return
	if effects is Dictionary:
		effects = [effects]
	for e in effects:
		_apply_one(e)


func _apply_one(e: Dictionary) -> void:
	if e.has("set_flag"):
		set_flag(e["set_flag"], e.get("value", true))
	elif e.has("trust"):
		add_trust(e["trust"], int(e.get("delta", 1)))
	elif e.has("give_item"):
		var n := int(e.get("count", 1))
		add_item(e["give_item"], n)
		UI.toast("Received: %s ×%d" % [item_name(e["give_item"]), n])
	elif e.has("take_item"):
		var n := int(e.get("count", 1))
		if remove_item(e["take_item"], n):
			UI.toast("Gave: %s ×%d" % [item_name(e["take_item"]), n])
	elif e.has("start_mission"):
		MissionManager.start_mission(e["start_mission"])
	elif e.has("progress"):
		var parts: PackedStringArray = String(e["progress"]).split(":")
		MissionManager.progress(parts[0], parts[1], int(e.get("amount", 1)))
	elif e.has("event"):
		story_event.emit(e["event"], e.get("data", {}))
	elif e.has("toast"):
		UI.toast(e["toast"])
	else:
		push_warning("Unknown effect: %s" % [e])


# --- Save data -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"chapter": current_chapter,
		"checkpoint": checkpoint,
		"flags": flags.duplicate(true),
		"trust": trust.duplicate(true),
		"inventory": inventory.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	current_chapter = d.get("chapter", "ch1")
	checkpoint = d.get("checkpoint", "start")
	flags = d.get("flags", {}).duplicate(true)
	trust = d.get("trust", {}).duplicate(true)
	inventory = d.get("inventory", {}).duplicate(true)
	# JSON turns ints into floats; normalise counts.
	for k in trust.keys():
		trust[k] = int(trust[k])
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
