extends "res://scripts/chapters/chapter_base.gd"
## Chapter 4 — The Hidden Room.
##
## Inside Joseph's house at night. Gather food, blankets and water (the yard is
## visible through the gate bars to the men on the path), take medicine from
## Mama Beata at the back window, supply the storage room, hide every sign of
## the hidden people, then go inside while Joseph slides the cupboard across.
## Patrick and armed men come to the gate. The player stays silent and keeps the
## frightened calm while Joseph refuses them. Then the farewell: the shelter is no
## longer safe, and Joseph stays behind.
##
##   start / free_roam   preparation      silence   the search at the gate
##   farewell            leaving home

const Interactable := preload("res://scripts/world/interactable.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")

## Seconds of the search; the overheard exchange at the gate.
const GATE_LINES := [
	{"speaker": "narrator", "text": "[Fists on the gate. Torchlight through the bars.]", "wait": 3.0},
	{"speaker": "patrick", "text": "Joseph! We know what you're doing. Open the door!"},
	{"speaker": "joseph", "text": "There are no enemies in my house. Only people."},
	{"speaker": "patrick", "text": "You're putting everyone at risk."},
	{"speaker": "joseph", "text": "The risk is already here. I won't hand innocent people over."},
	{"speaker": "patrol", "text": "Somebody saw the girl on this path. The medical student."},
	{"speaker": "joseph", "text": "Patrick. You played football in this yard. You ate at my table. Look at me, and tell me what you have become."},
	{"speaker": "narrator", "text": "[A long silence at the gate.]", "wait": 5.0},
	{"speaker": "patrick", "text": "We'll be back tomorrow. Every house will be searched. Every room."},
	{"speaker": "narrator", "text": "[Footsteps going away down the path. Nobody in the storage room breathes until they are gone.]", "wait": 5.0},
]
const HEARD_LINES := [
	{"speaker": "patrick", "text": "What was that? Inside the house."},
	{"speaker": "joseph", "text": "My goats. Do you want to count my goats as well, Patrick?"},
]

var interactables := {}
var comfort: Node3D
var silence_active := false
var noise := 0.0
var fear := 0.0
var _heard_inserted := false
var _whimper_t := 0.0
var _played_into_room := false


func _data_path() -> String:
	return "res://data/chapters/ch4.json"


func _spawn_extras() -> void:
	_add_task("shelf", "Take food from the shelf", "ch4_take_food", [{"objective": "ch4_main:gather"}, {"not_flag": "ch4_got_food"}])
	_add_task("chest", "Take blankets from the chest", "ch4_take_blankets", [{"objective": "ch4_main:gather"}, {"not_flag": "ch4_got_blankets"}])
	_add_task("barrel", "Fill the jerrycans at the rain barrel", "ch4_take_water", [{"objective": "ch4_main:gather"}, {"not_flag": "ch4_got_water"}])
	_add_task("mats", "Roll up the extra sleeping mats", "ch4_mats", [{"objective": "ch4_main:conceal"}, {"not_flag": "ch4_hid_mats"}])
	_add_task("cups", "Put away the extra cups", "ch4_cups", [{"objective": "ch4_main:conceal"}, {"not_flag": "ch4_hid_cups"}])

	var marker := Node3D.new()
	marker.set_meta("marker_id", "storage")
	marker.add_to_group("markers")
	add_child(marker)
	marker.global_position = village.spots["storage"]

	var t := StoryTrigger.new()
	t.name = "StorageTrigger"
	t.setup(1.7)
	t.requires = [{"objective": "ch4_main:hide"}]
	t.once = false
	add_child(t)
	t.global_position = village.spots["storage"]
	t.triggered.connect(func(): _run_silence())

	# The person who needs calming during the search.
	var has_eric := bool(GameState.get_flag("ch3_sheltered_claudine"))
	if not has_eric:
		npcs["claudine"].hide()
		npcs["eric"].hide()
	var who: Node3D = npcs["eric"] if has_eric else npcs["solange"]
	comfort = Interactable.new()
	comfort.name = "Comfort"
	comfort.prompt = "Hold Eric close and whisper to him" if has_eric else "Take Solange's hand"
	comfort.interact_radius = 1.6
	comfort.enabled = false
	add_child(comfort)
	comfort.global_position = who.global_position
	comfort.used.connect(func(_by):
		fear = 0.0
		UI.bark("", "Eric goes still against you." if has_eric else "Solange squeezes your hand and steadies her breathing."))

	for id in ["patrick", "man_1", "man_2", "beata"]:
		npcs[id].hide()
	MissionManager.objective_changed.connect(_on_objective_changed)


func _add_task(spot: String, prompt: String, conv: String, requires: Array) -> void:
	var i := Interactable.new()
	i.name = spot.capitalize()
	i.prompt = prompt
	i.interact_radius = 1.8
	i.requires = requires
	i.effects = [{"start_dialogue": conv}]
	add_child(i)
	i.global_position = village.spots[spot]
	interactables[spot] = i


func _on_objective_changed(id: String) -> void:
	if id != "ch4_main":
		return
	var obj := MissionManager.current_objective_id("ch4_main")
	npcs["beata"].visible = obj == "beata"
	if obj == "hide" and not _played_into_room:
		_played_into_room = true
		while DialogueManager.is_active():
			await DialogueManager.ended
			if aborted: return
		DialogueManager.start("ch4_into_room")


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"farewell":
			_run_farewell()
		"silence":
			_run_silence()
		"free_roam":
			_restore_player(world)
			_on_objective_changed("ch4_main")
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "ch4_leave":
		_run_farewell()


func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	_narrate("Days later.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	npcs["joseph"].face(player.global_position)
	player.face_towards(npcs["joseph"].global_position)
	_end_cinematic()
	await DialogueManager.play("ch4_opening")
	if aborted: return
	GameState.checkpoint = "free_roam"
	set_respawn_spot("start", PI)
	SaveManager.save_game("auto")
	running_sequence = ""


## The search at the gate. Emmanuel is in the storage room with the others.
func _run_silence() -> void:
	if running_sequence == "silence":
		return
	running_sequence = "silence"
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	if MissionManager.current_objective_id("ch4_main") == "hide":
		MissionManager.progress("ch4_main", "hide")
	GameState.checkpoint = "silence"
	SaveManager.save_game("auto")
	_begin_cinematic()
	await UI.fade_out(1.0)
	if aborted: return
	for w in watchers:
		w.hide()
	village.set_cupboard_closed(true, 0.01)
	village.lamp.light_energy = 0.0
	player.place_at(village.spots["storage"] + Vector3(-0.4, 0.1, 0.6), PI / 2)
	player.set_crouched(true)
	var j: Node3D = npcs["joseph"]
	j.global_position = village.spots["joseph_gate"]
	j.set_facing(0.0)
	for id in ["patrick", "man_1", "man_2"]:
		npcs[id].show()
	_narrate("The cupboard scrapes across the doorway. Darkness. Breathing.")
	await _wait(3.0)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.0)
	if aborted: return
	_end_cinematic()
	UI.toast("Stay still. Moving makes noise. Calm anyone who is frightened (E).")
	noise = 0.0
	fear = 0.2
	comfort.enabled = true
	for id in npcs:
		npcs[id].enabled = false
	silence_active = true
	await _overhear(GATE_LINES)
	if aborted: return
	silence_active = false
	comfort.enabled = false
	for id in npcs:
		npcs[id].enabled = true
	UI.clear_meter("noise")
	UI.clear_meter("fear")
	for id in ["patrick", "man_1", "man_2"]:
		npcs[id].hide()
	GameState.set_flag("ch4_shelter_kept_quiet", not GameState.get_flag("ch4_noise_heard"))
	MissionManager.progress("ch4_main", "silence")
	running_sequence = ""


func _process(delta: float) -> void:
	super(delta)
	if aborted or not silence_active or GameState.is_locked() or get_tree().paused:
		return
	if noise >= 0.995 and not _heard_inserted:
		_on_heard()
		return
	var moving := Vector3(player.velocity.x, 0, player.velocity.z).length() > 0.3
	if moving:
		noise += player.noise_level() * 0.9 * delta
	else:
		noise -= 0.08 * delta
	fear += 0.045 * delta
	if fear > 0.6:
		noise += 0.12 * delta
		_whimper_t -= delta
		if _whimper_t <= 0.0:
			UI.bark("", "A small, frightened sound in the dark.")
			_whimper_t = 6.0
	noise = clampf(noise, 0.0, 1.0)
	fear = clampf(fear, 0.0, 1.0)
	UI.set_meter("noise", "Noise", noise, Color(0.85, 0.5, 0.3))
	UI.set_meter("fear", "Fear in the room", fear, Color(0.6, 0.6, 0.85))
	if noise >= 0.995 and not _heard_inserted:
		_on_heard()


## The noise carried to the gate. Joseph covers for it; the search goes on.
func _on_heard() -> void:
	_heard_inserted = true
	GameState.set_flag("ch4_noise_heard")
	noise = 0.3
	_overhear(HEARD_LINES)


func _run_farewell() -> void:
	if running_sequence == "farewell":
		return
	running_sequence = "farewell"
	while DialogueManager.is_active():
		await DialogueManager.ended
		if aborted: return
	GameState.checkpoint = "farewell"
	SaveManager.save_game("auto")
	_begin_cinematic()
	await UI.fade_out(1.5)
	if aborted: return
	village.set_cupboard_closed(false, 0.01)
	village.lamp.light_energy = 0.8
	npcs["beata"].show()
	var j: Node3D = npcs["joseph"]
	j.global_position = village.spots["evening_joseph"]
	player.set_crouched(false)
	player.place_at(village.spots["evening_player"] + Vector3(0, 0.1, 0), PI)
	player.face_towards(j.global_position)
	j.face(player.global_position)
	_two_shot(j.global_position, player.global_position, Vector3(1.8, 1.4, 2.6))
	await UI.fade_in(1.2)
	if aborted: return
	_skip = false
	await DialogueManager.play("ch4_farewell")
	if aborted: return
	await _finish_chapter(4, "The Hidden Room", "ch5")
