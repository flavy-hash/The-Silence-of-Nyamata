extends "res://scripts/chapters/chapter_base.gd"
## Chapter 8 — The End of the Silence.
##
## Weeks later. Emmanuel returns with Aline to the damaged village. Mama Beata
## tells him his father did not survive, and reunites Aline with Olivier. A slow,
## reflective walk through places from Chapter 1, the memorial in the square,
## a final choice about what Emmanuel will help rebuild, then the ending, a
## memorial scene with the names of those lost, and the historical remembrance.
## There is no triumphant framing; survivors are not "rewarded".
##
## ENDINGS (decided by choices across the whole game; see ending_id()):
##   long_road  A Long Road Home        the group was separated at the river (Ch. 7)
##   names      The Names We Remember   someone Emmanuel tried to help did not survive:
##                                      Gasana, if his fever went untreated (Ch. 7), or
##                                      Innocent, if he was given water but left (Ch. 5)
##   seeds      The Seeds of Tomorrow   otherwise

const Interactable := preload("res://scripts/world/interactable.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")

var memorial: Node3D
var home_flowers: Node3D
var ending := ""


func _data_path() -> String:
	return "res://data/chapters/ch8.json"


## Which ending this playthrough has earned. Pure function of the story flags.
static func compute_ending() -> String:
	if GameState.get_flag("ch7_group_separated"):
		return "long_road"
	if lost_gasana() or lost_innocent():
		return "names"
	return "seeds"


static func lost_gasana() -> bool:
	return not GameState.get_flag("ch7_cared_gasana") and not GameState.get_flag("ch7_separated_gasana")


static func lost_innocent() -> bool:
	return bool(GameState.get_flag("ch5_helped_innocent")) and not GameState.get_flag("ch5_treated_innocent")


func _survivor(id: String) -> bool:
	if GameState.get_flag("ch7_separated_" + id):
		return false
	match id:
		"claudine", "eric":
			return bool(GameState.get_flag("ch3_sheltered_claudine"))
		"gasana":
			return not lost_gasana()
		"innocent":
			return bool(GameState.get_flag("ch5_treated_innocent"))
	return true


func _spawn_extras() -> void:
	GameState.set_flag("ch8_lost_gasana", lost_gasana())
	GameState.set_flag("ch8_lost_innocent", lost_innocent())
	for id in ["claudine", "eric", "gasana", "solange", "innocent"]:
		if not _survivor(id):
			npcs[id].hide()
	npcs["olivier"].hide()

	# The memorial: a low wall of gathered stones, flowers, candles in tins.
	memorial = Interactable.new()
	memorial.name = "Memorial"
	memorial.prompt = "Light a candle"
	memorial.marker_id = "memorial"
	memorial.interact_radius = 3.0
	memorial.requires = [{"objective": "ch8_main:memorial"}]
	memorial.effects = [{"start_dialogue": "ch8_memorial"}]
	add_child(memorial)
	memorial.global_position = village.spots["memorial"]
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.5, 0.48, 0.45)
	for k in 7:
		var s := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(randf_range(0.4, 0.7), randf_range(0.35, 0.6), 0.45)
		s.mesh = b
		s.material_override = stone_mat
		s.position = Vector3(-1.5 + k * 0.5, b.size.y / 2.0, 0)
		memorial.add_child(s)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.75, 0.35)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.6, 0.2)
	flame_mat.emission_energy_multiplier = 2.5
	for k in 5:
		var c := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.1
		c.mesh = sm
		c.material_override = flame_mat
		c.position = Vector3(-1.2 + k * 0.6, 0.12, 0.45)
		memorial.add_child(c)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 0.8
	glow.omni_range = 4.0
	glow.position = Vector3(0, 0.5, 0.6)
	memorial.add_child(glow)

	home_flowers = Interactable.new()
	home_flowers.name = "HomeStep"
	home_flowers.prompt = "Lay flowers on the step"
	home_flowers.marker_id = "home"
	home_flowers.interact_radius = 2.4
	home_flowers.requires = [{"objective": "ch8_main:remember"}, {"not_flag": "ch8_visited_home"}]
	home_flowers.effects = [{"start_dialogue": "ch8_home"}]
	add_child(home_flowers)
	home_flowers.global_position = village.spots["home_door"]

	var ball := Interactable.new()
	ball.name = "OldBall"
	ball.prompt = "Look at the old football"
	ball.interact_radius = 2.0
	ball.effects = [{"start_dialogue": "ch8_ball"}]
	add_child(ball)
	ball.global_position = village.spots["kids"]

	var hill := StoryTrigger.new()
	hill.setup(5.0)
	hill.once = false
	hill.requires = [{"objective": "ch8_main:remember"}, {"not_flag": "ch8_visited_hill"}]
	add_child(hill)
	hill.global_position = village.spots["aline_hill"]
	hill.triggered.connect(func():
		if not DialogueManager.is_active() and not GameState.is_locked():
			DialogueManager.start("ch8_hill"))

	MissionManager.objective_changed.connect(func(_id): _on_objective())


func _on_objective() -> void:
	if MissionManager.current_objective_id("ch8_main") == "memorial":
		# Everyone gathers in the square.
		var m: Vector3 = village.spots["memorial"]
		var i := 0
		for id in ["beata", "uwase", "olivier", "claudine", "eric", "gasana", "solange", "innocent"]:
			if npcs[id].visible or id == "olivier":
				var a := 0.6 + i * 0.45
				var p := m + Vector3(cos(a) * 3.2, 0, sin(a) * 3.2)
				p.y = village.height_at(p.x, p.z)
				npcs[id].global_position = p
				npcs[id].face(m)
				i += 1
		npcs["olivier"].visible = GameState.get_flag("ch8_olivier_found")


func _on_story_event(event_name: String, _d: Dictionary) -> void:
	match event_name:
		"ch8_olivier":
			GameState.set_flag("ch8_olivier_found")
			npcs["olivier"].show()
			npcs["olivier"].face(npcs["aline"].global_position)
		"ch8_ending":
			_run_ending()


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"ending":
			_run_ending()
		"free_roam":
			_restore_player(world)
			add_follower(npcs["aline"])
			gather_followers()
			if GameState.get_flag("ch8_olivier_found"):
				npcs["olivier"].show()
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
	for line in data.get("opening_captions", []):
		_narrate(line)
		await _wait(maxf(3.5, line.length() * 0.075))
		if aborted: return
	UI.caption("")
	add_follower(npcs["aline"])
	gather_followers()
	await UI.fade_in(2.0)
	if aborted: return
	_end_cinematic()
	await DialogueManager.play("ch8_arrival")
	if aborted: return
	GameState.checkpoint = "free_roam"
	SaveManager.save_game("auto")
	running_sequence = ""


## Epilogue, memorial, remembrance, credits.
func _run_ending() -> void:
	if running_sequence == "ending":
		return
	running_sequence = "ending"
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	ending = compute_ending()
	GameState.set_flag("ending", ending)
	GameState.checkpoint = "ending"
	SaveManager.save_game("auto")
	_begin_cinematic()
	await UI.fade_out(2.5)
	if aborted: return

	# The ending.
	var e: Dictionary = data["endings"][ending]
	UI.show_title_card(e["title"], "")
	await _wait(4.0)
	if aborted: return
	UI.hide_title_card(1.0)
	await _wait(1.2)
	if aborted: return
	var lines: Array = e["lines"].duplicate()
	var rebuild: String = str(GameState.get_flag("ch8_rebuild", ""))
	if data["rebuild"].has(rebuild):
		lines.insert(min(2, lines.size()), data["rebuild"][rebuild])
	lines.append(data["aftermath"]["patrick"])
	if GameState.get_flag("ch6_asked_patrick"):
		lines.append(data["aftermath"]["patrick_asked"])
	if GameState.flag_is("ch6_vestine_response", "understood") or GameState.flag_is("ch6_vestine_response", "invited"):
		lines.append(data["aftermath"]["vestine"])
	for l in lines:
		_narrate(l)
		await _wait(maxf(4.0, l.length() * 0.07))
		if aborted: return
	UI.caption("")
	await _wait(1.0)
	if aborted: return

	# The memorial: candlelight, and names.
	for w in followers.duplicate():
		remove_follower(w)
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	var m: Vector3 = village.spots["memorial"]
	cam.global_transform = Transform3D(Basis(), m + Vector3(0.3, 1.1, 3.4)).looking_at(m + Vector3(0, 0.3, 0))
	cam.current = true
	village.set_time_of_day("dusk")
	await UI.fade_in(2.0)
	if aborted: return
	var names := ["Joseph"]
	if lost_gasana():
		names.append("Gasana")
	if lost_innocent():
		names.append("Innocent")
	_narrate("In memory of " + ", ".join(names) + ".")
	await _wait(5.0)
	if aborted: return
	_narrate("And of all those murdered in the genocide against the Tutsi, from April to July 1994.\nTheir names are still being gathered.")
	await _wait(8.0)
	if aborted: return
	UI.caption("")
	await UI.fade_out(2.5)
	if aborted: return

	# The history this fiction is set within.
	UI.show_title_card("This story is fiction.", "The genocide against the Tutsi was not.")
	await _wait(5.0)
	if aborted: return
	UI.hide_title_card(1.0)
	await _wait(1.0)
	if aborted: return
	var waiting := [true]
	_end_cinematic()
	UI.open_message("Remember", TitleScreen.REMEMBRANCE, func(): waiting[0] = false, "Continue")
	while waiting[0] and not aborted and not Router.test_mode:
		await get_tree().process_frame
	UI.close_menu()
	if aborted: return
	_begin_cinematic()
	UI.show_title_card("THE SILENCE OF NYAMATA", "Thank you for playing.")
	await _wait(5.0)
	if aborted: return
	UI.hide_title_card(1.0)
	await _wait(1.2)
	if aborted: return

	GameState.set_flag("ch8_complete")
	if not ending in SaveManager.profile["endings_seen"]:
		SaveManager.profile["endings_seen"].append(ending)
		SaveManager._save_profile()
	GameState.checkpoint = "complete"
	SaveManager.save_game("auto")
	running_sequence = ""
	_end_cinematic()
	finished.emit()
	UI.set_black(false)
	Router.go_to_title()
