extends Node
## Branching dialogue runner. Content lives in data/dialogue/*.json:
##
##   "conversation_id": [
##     {"speaker": "aline", "text": "Hello."},
##     {"id": "ask", "speaker": "emmanuel", "choices": [
##         {"text": "Option A", "goto": "a", "do": [effects], "if": [conditions]},
##         {"text": "Option B", "end": true}
##     ]},
##     {"id": "a", "speaker": "aline", "text": "...", "if": [conditions], "do": [effects]},
##     {"speaker": "aline", "text": "...", "text_reduced": "softer text", "end": true}
##   ]
##
## Node keys: id, speaker, text, text_reduced (used when intensity = reduced),
## if (skip node unless conditions pass), do (effects applied when shown),
## choices, goto, end, voice (path to a voice-over clip; optional).
## Lines without "goto"/"end" continue to the next node in the list.

signal started(conversation_id: String)
signal line_shown(data: Dictionary)
signal ended(conversation_id: String)

const CHARACTERS_PATH := "res://data/characters.json"

var characters := {}
var conversations := {}

var _conv_id := ""
var _nodes: Array = []
var _index := -1
var _choice_map: Array = []   # visible choice -> index in node["choices"]


func _ready() -> void:
	characters = DataLoader.load_json(CHARACTERS_PATH, {})


func load_file(path: String) -> void:
	var data = DataLoader.load_json(path, {})
	for id in data:
		conversations[id] = data[id]


func has_conversation(id: String) -> bool:
	return conversations.has(id)


func is_active() -> bool:
	return _conv_id != ""


func current_id() -> String:
	return _conv_id


func speaker_name(speaker_id: String) -> String:
	return characters.get(speaker_id, {}).get("name", speaker_id.capitalize())


func start(conv_id: String) -> bool:
	if is_active():
		return false
	if not conversations.has(conv_id):
		push_error("Unknown conversation: %s" % conv_id)
		return false
	_conv_id = conv_id
	_nodes = conversations[conv_id]
	GameState.lock("dialogue")
	started.emit(conv_id)
	_show(0)
	return true


## Starts a conversation and waits until it finishes.
func play(conv_id: String) -> void:
	if start(conv_id):
		while is_active():
			await ended


## Continue past a line that has no choices.
func advance() -> void:
	if not is_active() or not _choice_map.is_empty():
		return
	var node: Dictionary = _nodes[_index]
	if node.get("end", false):
		_end()
	elif node.has("goto"):
		_show(_find(node["goto"]))
	else:
		_show(_index + 1)


## Pick one of the currently visible choices (0-based).
func choose(visible_index: int) -> void:
	if not is_active() or visible_index < 0 or visible_index >= _choice_map.size():
		return
	var choice: Dictionary = _nodes[_index]["choices"][_choice_map[visible_index]]
	_choice_map = []
	GameState.apply_effects(choice.get("do", []))
	if choice.get("end", false):
		_end()
	elif choice.has("goto"):
		_show(_find(choice["goto"]))
	else:
		_show(_index + 1)


func visible_choice_count() -> int:
	return _choice_map.size()


func _show(i: int) -> void:
	# Skip nodes whose conditions are not met.
	while i >= 0 and i < _nodes.size() and not GameState.check(_nodes[i].get("if")):
		i += 1
	if i < 0 or i >= _nodes.size():
		_end()
		return
	_index = i
	var node: Dictionary = _nodes[i]
	GameState.apply_effects(node.get("do", []))
	if not is_active():
		return  # an effect ended the conversation

	# A node without text is a pure jump/effect node.
	if not node.has("text") and not node.has("choices"):
		advance()
		return

	_choice_map = []
	var choices := []
	for ci in node.get("choices", []).size():
		var ch: Dictionary = node["choices"][ci]
		if GameState.check(ch.get("if")):
			_choice_map.append(ci)
			choices.append(ch["text"])

	var text: String = node.get("text", "")
	if Settings.intensity == "reduced" and node.has("text_reduced"):
		text = node["text_reduced"]

	var speaker: String = node.get("speaker", "narrator")
	var info: Dictionary = characters.get(speaker, {})
	line_shown.emit({
		"conversation": _conv_id,
		"speaker": speaker,
		"name": info.get("name", speaker.capitalize()),
		"color": info.get("color", "#efe9dd"),
		"narration": info.get("narration", false),
		"text": text,
		"choices": choices,
	})
	AudioManager.play_voice(node.get("voice", ""))


func _find(id: String) -> int:
	for i in _nodes.size():
		if _nodes[i].get("id", "") == id:
			return i
	push_error("Dialogue '%s': unknown goto '%s'" % [_conv_id, id])
	return -1


func _end() -> void:
	var id := _conv_id
	_conv_id = ""
	_nodes = []
	_index = -1
	_choice_map = []
	GameState.unlock("dialogue")
	AudioManager.stop_voice()
	ended.emit(id)
