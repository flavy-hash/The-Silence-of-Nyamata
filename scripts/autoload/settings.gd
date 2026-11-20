extends Node
## Player preferences: accessibility, audio and controls.
## Persisted to user://settings.cfg. Also registers every input action in one place,
## so keyboard and gamepad bindings are easy to find and change.

signal changed

const PATH := "user://settings.cfg"
const SUBTITLE_SIZES := {"small": 20, "medium": 26, "large": 34}

var subtitle_size := "medium"        # small | medium | large
var subtitles_enabled := true         # ambient lines and cinematic captions
var text_speed := 45.0                # characters per second; 0 = instant
var reduced_shake := false            # disables camera shake
var intensity := "full"               # full | reduced (softens distressing descriptions)
var objective_markers := true
var mouse_sensitivity := 0.25
var invert_y := false
var master_volume := 0.8

## Set by automated tests so they never touch the player's real settings file.
var persist := true


func _ready() -> void:
	_register_input()
	load_settings()
	apply()


func subtitle_font_size() -> int:
	return SUBTITLE_SIZES.get(subtitle_size, 26)


func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(max(master_volume, 0.0001)))
	changed.emit()


func set_value(key: String, value) -> void:
	set(key, value)
	apply()
	save_settings()


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in _keys():
		if cfg.has_section_key("settings", key):
			set(key, cfg.get_value("settings", key))


func _keys() -> Array:
	return ["subtitle_size", "subtitles_enabled", "text_speed", "reduced_shake", "intensity",
		"objective_markers", "mouse_sensitivity", "invert_y", "master_volume"]


# --- Input actions -----------------------------------------------------------

func _register_input() -> void:
	_action("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_action("interact", [KEY_E], [JOY_BUTTON_A])
	_action("advance", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	_action("inventory", [KEY_TAB, KEY_I], [JOY_BUTTON_Y])
	for i in range(4):
		_action("choice_%d" % (i + 1), [KEY_1 + i], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(name, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(name, jm)
