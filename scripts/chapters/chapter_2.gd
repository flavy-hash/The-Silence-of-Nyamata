extends "res://scripts/chapters/chapter_base.gd"
## Chapter 2 — The Radio (Rural Rwanda, early 1994).
##
## The same village under an overcast sky. Propaganda spreads by radio and by
## repetition; some villagers repeat it, some question it, many are frightened.
## The player investigates (listening to villagers, reading the meeting notice),
## which shows that the coming violence is being organised, and then faces
## Patrick's pressure: refuse, stay silent, or pretend to go along.
## These choices shape relationships and later scenes, never the history.
##
##   start      narration, a slow pass over the market, Joseph's errand
##   free_roam  main mission "The Radio" + side mission "One Team"
##   evening    Joseph and Emmanuel at dusk; chapter complete

const Interactable := preload("res://scripts/world/interactable.gd")

var notice: Node3D


func _data_path() -> String:
	return "res://data/chapters/ch2.json"


func _spawn_extras() -> void:
	# The meeting notice on the school board.
	notice = Interactable.new()
	notice.name = "MeetingNotice"
	notice.prompt = "Read the notice"
	notice.marker_id = "notice"
	notice.interact_radius = 2.0
	notice.effects = [{"start_dialogue": "ch2_notice"}]
	add_child(notice)
	notice.global_position = village.spots["notice"]
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.42, 0.55, 0.02)
	paper.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.9, 0.82)
	paper.material_override = pmat
	add_child(paper)
	paper.global_position = village.ground(Vector2(22.2, 6.56)) + Vector3(0, 1.25, 0)

	# Bosco's radio on his stall.
	var radio := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.38, 0.22, 0.16)
	radio.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.16, 0.14, 0.12)
	radio.material_override = rmat
	add_child(radio)
	radio.global_position = village.spots["radio_stall"] + Vector3(0, 0.96, 0)

	# The game has stopped: two children stand by the ball, two stand apart.
	var c: Vector3 = village.spots["kids"]
	kid_idle_spots = {0: c + Vector3(-0.6, 0, 0.4), 1: c + Vector3(0.6, 0, 0.6)}
	_set_kids_together(GameState.get_flag("ch2_kids_together"))


func _set_kids_together(together: bool) -> void:
	kids_playing = range(kids.size()) if together else []


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"evening":
			_run_evening()
		"free_roam":
			_restore_player(world)
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"ch2_kids_together":
			_set_kids_together(true)
		"ch2_evening":
			_run_evening()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	for line in data.get("opening_captions", []):
		_narrate(line)
		await _wait(maxf(3.5, line.length() * 0.075))
		if aborted: return
	_narrate("")

	# A slow pass over the quiet market and Bosco's radio, ending at home.
	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true
	var stall: Vector3 = village.spots["radio_stall"]
	var home: Vector3 = village.spots["home_door"]
	var from := Transform3D(Basis(), stall + Vector3(9, 7, 12)).looking_at(stall + Vector3(0, 1, 0))
	var mid := Transform3D(Basis(), stall + Vector3(-4, 3.2, 6)).looking_at(stall + Vector3(0, 1, 0))
	var to := Transform3D(Basis(), home + Vector3(2.5, 2.4, 6.0)).looking_at(home + Vector3(0, 1.2, 0))
	UI.fade_in(2.0)
	_narrate(data.get("setting", ""))
	get_tree().create_timer(4.0, false).timeout.connect(func(): UI.caption(""))
	await _camera_move(cam, from, mid, to, 10.0)
	if aborted: return
	UI.caption("")
	UI.set_black(false)
	player.camera_rig.camera.current = true
	cam.queue_free()

	npcs["joseph"].face(player.global_position)
	player.face_towards(npcs["joseph"].global_position)
	_end_cinematic()
	await DialogueManager.play("ch2_opening")
	if aborted: return
	GameState.checkpoint = "free_roam"
	SaveManager.save_game("auto")
	running_sequence = ""


func _run_evening() -> void:
	if running_sequence == "evening":
		return
	running_sequence = "evening"
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	GameState.checkpoint = "evening"
	SaveManager.save_game("auto")
	_begin_cinematic()
	await UI.fade_out(2.0)
	if aborted: return
	_stage_evening_at_home()
	for id in ["stranger_1", "stranger_2"]:
		npcs[id].hide()
	_narrate("That evening.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch2_evening")
	if aborted: return
	await _finish_chapter(2, "The Radio", "ch3")
