class_name DataLoader
extends RefCounted
## Small helper for reading the game's JSON content files.


static func load_json(path: String, fallback = null):
	if not FileAccess.file_exists(path):
		push_error("Data file not found: %s" % path)
		return fallback
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	return json.data


static func vec3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
