extends Node
## Moves between screens (content warning, title, chapters) and knows which
## chapters exist. Chapter list: data/chapters/index.json.

signal returned_to_title

const INDEX_PATH := "res://data/chapters/index.json"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const WARNING_SCENE := "res://scenes/ui/content_warning.tscn"

var chapters: Array = []

## World state handed to the next chapter scene (player position etc. from a save).
var pending_world := {}

## When true (automated tests), scene changes are reported instead of performed.
var test_mode := false


func _ready() -> void:
	chapters = DataLoader.load_json(INDEX_PATH, [])


func chapter_info(id: String) -> Dictionary:
	for c in chapters:
		if c["id"] == id:
			return c
	return {}


func is_playable(id: String) -> bool:
	return chapter_info(id).get("scene", "") != ""


func show_content_warning() -> void:
	get_tree().change_scene_to_file(WARNING_SCENE)


func go_to_title() -> void:
	get_tree().paused = false
	UI.set_gameplay(false)
	returned_to_title.emit()
	if not test_mode:
		get_tree().change_scene_to_file(TITLE_SCENE)


func new_game() -> void:
	GameState.reset()
	MissionManager.reset()
	start_chapter("ch1")


## Starting from chapter select resets the playthrough state for that chapter.
func start_chapter_fresh(id: String) -> void:
	GameState.reset()
	MissionManager.reset()
	GameState.current_chapter = id
	start_chapter(id)


func start_chapter(id: String, world: Dictionary = {}) -> bool:
	if not is_playable(id):
		UI.toast("%s is still in development." % chapter_info(id).get("title", id))
		return false
	GameState.current_chapter = id
	pending_world = world
	get_tree().paused = false
	if not test_mode:
		get_tree().change_scene_to_file(chapter_info(id)["scene"])
	return true


## Asks the active chapter for the world state to store in a save.
func collect_world_state() -> Dictionary:
	var chapter := get_tree().get_first_node_in_group("chapter")
	if chapter and chapter.has_method("get_world_state"):
		return chapter.get_world_state()
	return {}
