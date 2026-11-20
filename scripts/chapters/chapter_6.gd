extends "res://scripts/chapters/chapter_base.gd"
## Chapter 6 — The Betrayal.
##
## Morning at the abandoned houses. Their hiding place has been exposed.
## Emmanuel investigates (footprints, a dropped jug, a page from a list), finds
## Vestine, who was coerced with threats against her children, confronts Patrick
## at the old school, then leads the group out past the returning searchers.
## The game does not equate Patrick with those he hunted: fear explains, it does
## not excuse.

const Interactable := preload("res://scripts/world/interactable.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")

var clues := {}
var escaping := false


func _data_path() -> String:
	return "res://data/chapters/ch6.json"


func _spawn_extras() -> void:
	_clue("prints", "Look at the ground by the door", "ch6_clue_prints", "ch6_clue_prints")
	_clue("jug", "Look at what is lying in the path", "ch6_clue_jug", "ch6_clue_jug")
	_clue("trampled", "Look at the trampled grass", "ch6_clue_page", "ch6_clue_page")

	var exit_marker := Node3D.new()
	exit_marker.set_meta("marker_id", "exit")
	exit_marker.add_to_group("markers")
	add_child(exit_marker)
	exit_marker.global_position = village.spots["exit"]

	var t := StoryTrigger.new()
	t.setup(5.0)
	t.once = false
	t.requires = [{"objective": "ch6_main:escape"}]
	add_child(t)
	t.global_position = village.spots["exit"]
	t.triggered.connect(_try_exit)

	for id in ["claudine", "eric", "innocent"]:
		if not id in group_ids():
			npcs[id].hide()
	npcs["patrick"].hide()
	_set_patrols(false)
	MissionManager.objective_changed.connect(func(_id): _on_objective())


func _clue(spot: String, prompt: String, conv: String, flag: String) -> void:
	var i := Interactable.new()
	i.name = "Clue_" + spot
	i.prompt = prompt
	i.interact_radius = 2.0
	i.requires = [{"objective": "ch6_main:clues"}, {"not_flag": flag}]
	i.effects = [{"start_dialogue": conv}]
	add_child(i)
	i.global_position = village.spots[spot]
	clues[spot] = i
	if spot == "jug":
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.16
		cm.height = 0.4
		m.mesh = cm
		m.rotation.z = PI / 2
		m.position.y = 0.15
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.6, 0.2)
		m.material_override = mat
		i.add_child(m)


func _set_patrols(on: bool) -> void:
	stealth_enabled = on
	for w in watchers:
		w.visible = on
		if on:
			w.reset_to_start()


func _on_objective() -> void:
	var obj := MissionManager.current_objective_id("ch6_main")
	npcs["patrick"].visible = obj == "confront"
	if obj == "escape" and not escaping:
		_start_escape()


func _start_escape() -> void:
	escaping = true
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	npcs["patrick"].hide()
	# The group comes to Emmanuel; the searchers return.
	player.place_at(village.spots["shelter_door"] + Vector3(0.5, 0.1, 1.5), 2.2)
	spawn_group()
	set_respawn(player.global_position, 2.2)
	_set_patrols(true)
	GameState.checkpoint = "escape"
	SaveManager.save_game("auto")
	DialogueManager.start("ch6_escape")


func _try_exit() -> void:
	if not escaping:
		return
	for f in followers:
		if f.global_position.distance_to(player.global_position) > 14.0:
			UI.toast("Wait. Not everyone is with you yet.")
			return
	MissionManager.progress("ch6_main", "escape")


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"end":
			_run_end()
		"escape":
			_start_escape()
		"free_roam":
			_restore_player(world)
			_on_objective()
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "ch6_end":
		_run_end()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	_narrate(data["setting"] + ".")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	npcs["aline"].face(player.global_position)
	player.face_towards(npcs["aline"].global_position)
	_end_cinematic()
	await DialogueManager.play("ch6_opening")
	if aborted: return
	GameState.checkpoint = "free_roam"
	SaveManager.save_game("auto")
	running_sequence = ""


func _run_end() -> void:
	if running_sequence == "end":
		return
	running_sequence = "end"
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	GameState.checkpoint = "end"
	SaveManager.save_game("auto")
	_begin_cinematic()
	UI.clear_meters()
	await UI.fade_out(1.5)
	if aborted: return
	_set_patrols(false)
	await UI.fade_in(0.5)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch6_end")
	if aborted: return
	await _finish_chapter(6, "The Betrayal", "ch7")
