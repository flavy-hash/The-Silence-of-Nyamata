extends "res://scripts/chapters/chapter_base.gd"
## Chapter 5 — The Road to Hope.
##
## Mama Beata sends the group down the valley path. On the way: an injured man
## (first aid uses scarce medicine), a family nailed inside their house (optional
## rescue), a rest where the group must share limited food and water, a roadblock
## to get around unseen through tall grass, and a frightened boy in the banana
## grove. The group reaches the abandoned houses at the edge of the marsh.
## Supplies spent here are not available at the river in Chapter 7.

const Interactable := preload("res://scripts/world/interactable.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")

var pole: Node3D
var rest_spot: Node3D


func _data_path() -> String:
	return "res://data/chapters/ch5.json"


func _spawn_extras() -> void:
	_trigger("innocent", 6.0, [{"objective": "ch5_main:walk"}, {"not_flag": "ch5_met_innocent"}],
		func(): npcs["innocent"].interact(player))
	_trigger("family_door", 9.0, [{"mission_not_started": "ch5_family"}, {"not_flag": "ch5_left_family"}],
		func(): npcs["mother"].interact(player))
	_trigger("beyond_road", 4.5, [{"objective": "ch5_main:roadblock"}],
		func(): MissionManager.progress("ch5_main", "roadblock"))
	_trigger("shelter_door", 5.0, [{"objective": "ch5_main:shelter"}],
		func(): MissionManager.progress("ch5_main", "shelter"))

	pole = Interactable.new()
	pole.name = "Pole"
	pole.prompt = "Pick up the old hoe handle"
	pole.marker_id = "pole"
	pole.requires = [{"objective": "ch5_family:find_pole"}]
	pole.effects = [{"start_dialogue": "ch5_pole"}]
	add_child(pole)
	pole.global_position = village.spots["pole"]
	var pm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 1.4
	pm.mesh = cm
	pm.rotation.z = PI / 2
	pm.position.y = 0.05
	pole.add_child(pm)
	pole.used.connect(func(_by): pole.hide())

	# The door marker for the barred house.
	var door := Node3D.new()
	door.set_meta("marker_id", "family_door")
	door.add_to_group("markers")
	add_child(door)
	door.global_position = village.spots["family_door"]

	rest_spot = Interactable.new()
	rest_spot.name = "RestLog"
	rest_spot.prompt = "Rest with the group"
	rest_spot.marker_id = "rest"
	rest_spot.interact_radius = 3.0
	rest_spot.requires = [{"objective": "ch5_main:rest"}]
	rest_spot.effects = [{"start_dialogue": "ch5_rest"}]
	add_child(rest_spot)
	rest_spot.global_position = village.spots["rest"]

	for id in ["beyond_road", "shelter"]:
		var m := Node3D.new()
		m.set_meta("marker_id", id)
		m.add_to_group("markers")
		add_child(m)
		m.global_position = village.spots["shelter_door" if id == "shelter" else id]

	npcs["vestine"].hide()
	GameState.flag_changed.connect(_on_flag)
	MissionManager.objective_changed.connect(func(_id): _update_respawn())


func _trigger(spot: String, radius: float, requires: Array, action: Callable) -> void:
	var t := StoryTrigger.new()
	t.setup(radius)
	t.once = false
	t.requires = requires
	add_child(t)
	t.global_position = village.spots[spot]
	t.triggered.connect(func():
		if not DialogueManager.is_active() and not GameState.is_locked():
			action.call())


func _on_flag(key: String, _value) -> void:
	if key == "ch5_treated_innocent":
		add_follower(npcs["innocent"])
	elif key == "ch5_freed_family":
		var m: Node3D = npcs["mother"]
		m.global_position = village.spots["family_door"]
		m.enabled = false
		await m.walk_to(village.ground(Vector2(-44, 30)), 1.8, village.height_at)
		m.hide()


func _update_respawn() -> void:
	match MissionManager.current_objective_id("ch5_main"):
		"roadblock":
			set_respawn_spot("rest", PI * 0.75)
		"stranger", "shelter":
			set_respawn_spot("beyond_road", PI * 0.8)
		_:
			set_respawn_spot("start", 2.39)


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"end":
			_run_end()
		"free_roam":
			_restore_player(world)
			if GameState.get_flag("ch5_freed_family") or GameState.get_flag("ch5_left_family"):
				npcs["mother"].hide()
			if GameState.get_flag("ch5_met_innocent") and not GameState.get_flag("ch5_treated_innocent"):
				npcs["innocent"].enabled = true
			spawn_group()
			_update_respawn()
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "ch5_end":
		_run_end()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	spawn_group()
	await _wait(1.0)
	if aborted: return
	_narrate("Before dawn.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	npcs["beata"].face(player.global_position)
	player.face_towards(npcs["beata"].global_position)
	_end_cinematic()
	await DialogueManager.play("ch5_opening")
	if aborted: return
	player.place_at(village.spots["start"] + Vector3(0, 0.1, 0), 2.39)
	gather_followers()
	GameState.checkpoint = "free_roam"
	_update_respawn()
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
	for w in watchers:
		w.hide()
	village.set_time_of_day("dusk")
	AudioManager.play_ambience("village_dusk")
	var door: Vector3 = village.spots["shelter_door"]
	player.set_crouched(false)
	player.place_at(door + Vector3(-1.5, 0.1, 2.5), 0.0)
	gather_followers()
	var v: Node3D = npcs["vestine"]
	v.show()
	v.global_position = door + Vector3(1.5, 0, 3.5)
	v.face(player.global_position)
	player.face_towards(v.global_position)
	_two_shot(v.global_position, player.global_position, Vector3(-3.0, 1.6, 3.0))
	await UI.fade_in(1.2)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch5_end")
	if aborted: return
	await _finish_chapter(5, "The Road to Hope", "ch6")
