extends "res://scripts/chapters/chapter_base.gd"
## Chapter 7 — The Crossing.
##
## The group reaches the river. Emmanuel tests the water to find the one safe
## ford (Mukamana's advice from Chapter 5 marks it), decides how to share the
## last supplies (Gasana's fever, Innocent's wound), then leads people across
## one or two at a time while voices draw closer on the ridge. Aline, exhausted,
## crosses last on Emmanuel's shoulder: slow, tiring, and only possible by
## resting when stamina runs out. If time runs out, those still on the near bank
## flee into the papyrus and the group is separated (Ending 3: A Long Road Home).

const Interactable := preload("res://scripts/world/interactable.gd")

var tests := {}
var camp_spot: Node3D
var time_left := -1.0
var time_total := 1.0
var separated := false
var _last_safe := Vector3.ZERO


func _data_path() -> String:
	return "res://data/chapters/ch7.json"


## Who has to be led across (Eric crosses on Claudine's back; Aline goes last).
func crossers() -> Array:
	return group_ids().filter(func(id): return id != "aline" and id != "eric")


func _spawn_extras() -> void:
	for s in ["test_north", "test_mid", "test_ford"]:
		var i := Interactable.new()
		i.name = s
		i.prompt = "Test the water here"
		i.interact_radius = 2.4
		i.requires = [{"mission_active": "ch7_main"}]
		i.effects = [{"start_dialogue": "ch7_" + s}]
		add_child(i)
		i.global_position = village.spots[s]
		tests[s] = i
	var hint := Node3D.new()
	hint.set_meta("marker_id", "ford_hint")
	hint.add_to_group("markers")
	add_child(hint)
	hint.global_position = village.spots["test_ford"]
	hint.visible = bool(GameState.get_flag("ch5_knows_ford"))

	camp_spot = Interactable.new()
	camp_spot.name = "Camp"
	camp_spot.prompt = "Sit down with the group"
	camp_spot.marker_id = "camp"
	camp_spot.interact_radius = 3.5
	camp_spot.requires = [{"objective": "ch7_main:care"}]
	camp_spot.effects = [{"start_dialogue": "ch7_care"}]
	add_child(camp_spot)
	camp_spot.global_position = village.spots["camp"]

	for id in ["claudine", "eric", "innocent"]:
		if not id in group_ids():
			npcs[id].hide()
	player.place_at(village.spots["camp"] + Vector3(3.5, 0.1, 2.0), -1.2)
	_last_safe = player.global_position
	MissionManager.objective_changed.connect(func(_id): _on_objective())


func _on_objective() -> void:
	var obj := MissionManager.current_objective_id("ch7_main")
	if obj == "cross" and time_left < 0.0:
		time_total = 120.0 + 75.0 * crossers().size()
		time_left = time_total


func _on_story_event(event_name: String, d: Dictionary) -> void:
	match event_name:
		"ch7_lead":
			var id: String = d.get("id", "")
			GameState.set_flag("ch7_leading_" + id)
			add_follower(npcs[id])
			if id == "claudine":
				add_follower(npcs["eric"])
		"ch7_support_aline":
			add_follower(npcs["aline"])
			player.supporting = npcs["aline"]
			UI.toast("Supporting Aline. It is slow and tiring; stop to rest when you need to.")
		"ch7_end":
			_run_end()


func _physics_process(delta: float) -> void:
	super(delta)
	if aborted or GameState.is_locked() or get_tree().paused:
		return
	var p := player.global_position
	# Wading is slow; deep, fast water is not an option.
	player.terrain_speed = 0.55 if village.is_water(p.x, p.z) else 1.0
	if village.height_at(p.x, p.z) < -0.9:
		player.place_at(_last_safe + Vector3(0, 0.1, 0), player.model.rotation.y + PI)
		UI.toast("Too deep. The current would take you.")
	elif not village.is_water(p.x, p.z):
		_last_safe = p
	_check_crossings()
	_tick_timer(delta)


func _check_crossings() -> void:
	for f in followers.duplicate():
		if not village.is_east_bank(f.global_position.x, f.global_position.z):
			continue
		if f == npcs["aline"]:
			if village.is_east_bank(player.global_position.x, player.global_position.z):
				remove_follower(f)
				player.supporting = null
				_settle(f, 0)
				MissionManager.progress("ch7_main", "aline")
			continue
		var id: String = npcs.find_key(f)
		remove_follower(f)
		_settle(f, crossers().find(id) + 1)
		if id == "eric":
			continue
		GameState.set_flag("ch7_across_" + id)
		GameState.set_flag("ch7_leading_" + id, false)
		UI.toast("%s is across." % f.display_name)
	if MissionManager.current_objective_id("ch7_main") == "cross":
		if crossers().all(func(id): return GameState.get_flag("ch7_across_" + id) or GameState.get_flag("ch7_separated_" + id)):
			time_left = -1.0
			UI.clear_meter("ridge")
			MissionManager.progress("ch7_main", "cross")


## Seat someone at the camp on the far bank.
func _settle(n: Node3D, slot: int) -> void:
	var a := slot * 0.9
	var p: Vector3 = village.spots["far_camp"] + Vector3(cos(a) * 2.2, 0, sin(a) * 2.2)
	p.y = village.height_at(p.x, p.z)
	n.global_position = p
	n.face(village.spots["far_camp"])


func _tick_timer(delta: float) -> void:
	if time_left < 0.0 or separated:
		return
	time_left -= delta
	UI.set_meter("ridge", "Voices on the ridge", 1.0 - time_left / time_total, Color(0.8, 0.45, 0.3))
	if time_left <= 0.0:
		_separate()


## Time ran out: those still waiting on the near bank flee into the papyrus.
func _separate() -> void:
	separated = true
	time_left = -1.0
	UI.clear_meter("ridge")
	var lost := []
	for id in crossers():
		if GameState.get_flag("ch7_across_" + id) or npcs[id] in followers:
			continue
		lost.append(id)
	if lost.is_empty():
		return
	GameState.set_flag("ch7_group_separated")
	for id in lost:
		GameState.set_flag("ch7_separated_" + id)
		npcs[id].hide()
		if id == "claudine":
			GameState.set_flag("ch7_separated_eric")
			npcs["eric"].hide()
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	DialogueManager.start("ch7_separated")


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"end":
			_run_end()
		"free_roam":
			_restore_player(world)
			for id in crossers():
				GameState.set_flag("ch7_leading_" + id, false)
				if GameState.get_flag("ch7_across_" + id):
					_settle(npcs[id], crossers().find(id) + 1)
					if id == "claudine":
						_settle(npcs["eric"], 0)
				elif GameState.get_flag("ch7_separated_" + id):
					npcs[id].hide()
			_on_objective()
			UI.refresh_objectives()
		_:
			_run_opening()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	_narrate("The river.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	npcs["aline"].face(player.global_position)
	player.face_towards(npcs["aline"].global_position)
	_end_cinematic()
	await DialogueManager.play("ch7_opening")
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
	player.supporting = null
	player.terrain_speed = 1.0
	GameState.checkpoint = "end"
	SaveManager.save_game("auto")
	_begin_cinematic()
	UI.clear_meters()
	await UI.fade_out(1.5)
	if aborted: return
	village.set_time_of_day("dusk")
	AudioManager.play_ambience("village_dusk")
	player.place_at(village.spots["evening_player"] + Vector3(0, 0.1, 0), -2.4)
	var a: Node3D = npcs["aline"]
	a.global_position = village.spots["evening_joseph"]
	a.face(player.global_position)
	player.face_towards(a.global_position)
	_two_shot(a.global_position, player.global_position, Vector3(-2.6, 1.5, 3.4))
	await UI.fade_in(1.2)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch7_end")
	if aborted: return
	await _finish_chapter(7, "The Crossing", "ch8")
