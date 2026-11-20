extends "res://scripts/chapters/chapter_base.gd"
## Chapter 3 — The Night Everything Changed (6 April 1994).
##
## Evening: the radio announces that the President's plane has been shot down.
## Night: Aline arrives at the door; her brother Olivier is missing. Emmanuel
## searches the dark village, avoiding patrols and the roadblock, and may bring
## Claudine, Eric and Gasana back to his father's house.
## Being seen never shows violence: Emmanuel slips away and tries again.
##
##   start      radio, the knock at the door, the decision to search
##   free_roam  stealth search (main) + Old Neighbour / Safe Passage (side)
##   end        home again; the hidden room is decided on; chapter complete

const Interactable := preload("res://scripts/world/interactable.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")

var sandal: Node3D
var home_trigger: Area3D
var _fire: OmniLight3D
var _fire_t := 0.0


func _data_path() -> String:
	return "res://data/chapters/ch3.json"


func _spawn_extras() -> void:
	# The roadblock fire in the square.
	_fire = OmniLight3D.new()
	_fire.light_color = Color(1.0, 0.55, 0.25)
	_fire.light_energy = 2.5
	_fire.omni_range = 9.0
	add_child(_fire)
	_fire.global_position = village.ground(Vector2(0.5, 0.0)) + Vector3(0, 0.8, 0)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.35
	fm.height = 0.7
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.5, 0.15)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.1)
	fmat.emission_energy_multiplier = 2.0
	flame.material_override = fmat
	add_child(flame)
	flame.global_position = village.ground(Vector2(0.5, 0.0)) + Vector3(0, 0.35, 0)

	# Olivier's sandal at the edge of the pitch.
	sandal = Interactable.new()
	sandal.name = "Sandal"
	sandal.prompt = "Look at what is lying in the grass"
	sandal.marker_id = "sandal"
	sandal.interact_radius = 2.0
	sandal.requires = [{"objective": "ch3_main:find_sandal"}]
	sandal.effects = [{"start_dialogue": "ch3_sandal"}]
	add_child(sandal)
	sandal.global_position = village.spots["sandal"]
	var sm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.03, 0.24)
	sm.mesh = box
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.55, 0.35, 0.2)
	sm.material_override = smat
	sm.position.y = 0.03
	sandal.add_child(sm)

	# Arriving home shelters whoever is following and can end the search.
	home_trigger = StoryTrigger.new()
	home_trigger.name = "HomeTrigger"
	home_trigger.once = false
	home_trigger.setup(3.2)
	add_child(home_trigger)
	home_trigger.global_position = village.spots["home_door"]
	home_trigger.triggered.connect(_arrive_home)

	GameState.flag_changed.connect(_on_flag)
	MissionManager.objective_changed.connect(func(_id): _update_respawn())


func _on_flag(key: String, _value) -> void:
	match key:
		"ch3_claudine_following":
			add_follower(npcs["claudine"])
			add_follower(npcs["eric"])
		"ch3_gasana_following":
			add_follower(npcs["gasana"])


func _restore_followers() -> void:
	if GameState.get_flag("ch3_claudine_following") and not GameState.get_flag("ch3_sheltered_claudine"):
		add_follower(npcs["claudine"])
		add_follower(npcs["eric"])
	if GameState.get_flag("ch3_gasana_following") and not GameState.get_flag("ch3_sheltered_gasana"):
		add_follower(npcs["gasana"])
	for id in ["claudine", "eric"]:
		if GameState.get_flag("ch3_sheltered_claudine"):
			npcs[id].hide()
	if GameState.get_flag("ch3_sheltered_gasana"):
		npcs["gasana"].hide()
	gather_followers()


## After each step, a retry starts from a quiet place near the last goal.
func _update_respawn() -> void:
	match MissionManager.current_objective_id("ch3_main"):
		"find_sandal":
			set_respawn_spot("home_door", 0.0)
		"find_witness":
			set_respawn_spot("field_cover", PI)
		"reach_beata":
			set_respawn(pt([-19.5, -8.5]), PI / 2)
		"return_home":
			set_respawn_spot("shop_back", -PI / 2)


func _arrive_home() -> void:
	if GameState.is_locked("cinematic"):
		return
	var names := []
	for f in followers.duplicate():
		remove_follower(f)
		f.hide()
		if f == npcs["claudine"]:
			MissionManager.progress("ch3_claudine", "bring")
			names.append("Claudine and Eric")
		elif f == npcs["gasana"]:
			MissionManager.progress("ch3_gasana", "bring")
			names.append("Gasana")
	if not names.is_empty():
		UI.toast("%s slipped inside. Safe, for now." % " and ".join(names))
	if MissionManager.current_objective_id("ch3_main") == "return_home":
		MissionManager.progress("ch3_main", "return_home")


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"end":
			_run_end()
		"free_roam":
			npcs["aline"].hide()
			_restore_player(world)
			_restore_followers()
			_update_respawn()
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "ch3_end":
		_run_end()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	_narrate(data["setting"])
	await _wait(3.0)
	if aborted: return
	UI.caption("")

	# Evening, at home, by the radio.
	_stage_evening_at_home()
	await UI.fade_in(1.5)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch3_radio")
	if aborted: return
	await UI.fade_out(2.0)
	if aborted: return

	# Night. Everyone back in place; Aline at the door.
	village.set_time_of_day("night")
	AudioManager.play_ambience("village_night")
	for id in npcs:
		npcs[id].show()
	var aline: Node3D = npcs["aline"]
	var door: Vector3 = village.spots["home_door"]
	aline.global_position = door + Vector3(1.2, 0, 2.2)
	player.place_at(door + Vector3(-0.2, 0.1, 0.6), 0.0)
	player.face_towards(aline.global_position)
	aline.face(player.global_position)
	var cam := _two_shot(aline.global_position, player.global_position, Vector3(3.2, 1.6, 2.8))
	_narrate("That night.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch3_night")
	if aborted: return

	aline.hide()   # inside the house now
	player.camera_rig.camera.current = true
	cam.queue_free()
	player.place_at(door + Vector3(0, 0.1, 0.4), 0.0)
	player.set_crouched(true)
	_end_cinematic()
	UI.toast("Press C to crouch. Crouch in tall grass to hide.")
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
	var aline: Node3D = npcs["aline"]
	var door: Vector3 = village.spots["home_door"]
	aline.show()
	aline.global_position = door + Vector3(1.0, 0, 1.6)
	player.set_crouched(false)
	player.place_at(door + Vector3(-0.6, 0.1, 1.2), 0.0)
	player.face_towards(aline.global_position)
	aline.face(player.global_position)
	npcs["joseph"].global_position = door + Vector3(-1.6, 0, 1.0)
	npcs["joseph"].face(aline.global_position)
	_two_shot(aline.global_position, player.global_position, Vector3(3.0, 1.6, 3.2))
	await UI.fade_in(1.2)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch3_end")
	if aborted: return
	await _finish_chapter(3, "The Night Everything Changed", "ch4")


func _process(delta: float) -> void:
	super(delta)
	_fire_t += delta
	if _fire:
		_fire.light_energy = 2.3 + sin(_fire_t * 9.0) * 0.3 + sin(_fire_t * 23.0) * 0.15
