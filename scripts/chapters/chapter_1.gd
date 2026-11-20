extends "res://scripts/chapters/chapter_base.gd"
## Chapter 1 — The Days of Friendship (Rural Rwanda, 1993).
##
##   start      opening narration, flyover, Aline's greeting
##   free_roam  exploration; Gasana's harvest (main), Market Day and Good Neighbours (side)
##   evening    dusk at home, the radio, Joseph's words, title card, chapter complete
## Checkpoints are autosaved at "free_roam" and "evening".

const CarryItem := preload("res://scripts/world/carry_item.gd")
const DropZone := preload("res://scripts/world/drop_zone.gd")
const StoryTrigger := preload("res://scripts/world/story_trigger.gd")
const SACK_COUNT := 3

var sacks: Array = []
var storehouse: Node3D
var farm_marker: Node3D        # moves between the next sack and the storehouse
var _stored_visuals: Array = []


func _data_path() -> String:
	return "res://data/chapters/ch1.json"


func _on_checkpoint(checkpoint: String, world: Dictionary) -> void:
	match checkpoint:
		"evening":
			_run_evening()
		"free_roam":
			_place_aline_on_hill()
			_sync_sacks()
			_restore_player(world)
			UI.refresh_objectives()
		_:
			_run_opening()


func _on_story_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "ch1_evening":
		_run_evening()


# =============================================================================
# Gasana's harvest and the hill
# =============================================================================

func _spawn_extras() -> void:
	var on_task := [{"objective": "ch1_main:carry_sacks"}]
	for i in SACK_COUNT:
		var s := CarryItem.new()
		s.name = "Sack%d" % (i + 1)
		s.item_id = "bean_sack"
		s.prompt = "Lift the sack of beans"
		s.interact_radius = 1.8
		s.requires = on_task
		s.visual = _sack_mesh()
		add_child(s)
		s.global_position = village.spots["sack_%d" % (i + 1)]
		sacks.append(s)

	storehouse = DropZone.new()
	storehouse.name = "Storehouse"
	storehouse.accepts = "bean_sack"
	storehouse.prompt = "Put the sack in the storehouse"
	storehouse.interact_radius = 3.2
	storehouse.requires = on_task
	storehouse.effects = [{"progress": "ch1_main:carry_sacks"}]
	add_child(storehouse)
	storehouse.global_position = village.spots["storehouse"] + Vector3(0, 0, 1.9)
	storehouse.delivered.connect(func(_id): _refresh_stored_sacks())

	farm_marker = Node3D.new()
	farm_marker.name = "FarmTaskMarker"
	farm_marker.set_meta("marker_id", "farm_task")
	farm_marker.add_to_group("markers")
	add_child(farm_marker)

	var t := StoryTrigger.new()
	t.name = "HillTrigger"
	t.setup(4.5)
	t.requires = [{"objective": "ch1_main:meet_aline"}]
	add_child(t)
	t.global_position = village.spots["aline_hill"]
	t.triggered.connect(func():
		if not DialogueManager.is_active():
			npcs["aline"].interact(player))


func _sack_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.24
	m.height = 0.75
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.6, 0.4)
	mi.material_override = mat
	mi.position.y = 0.3
	mi.scale = Vector3(1, 0.75, 1)
	return mi


## Sacks already delivered (from a save or this session) appear stacked by the storehouse.
func _refresh_stored_sacks() -> void:
	var delivered := MissionManager.objective_amount_done("ch1_main", "carry_sacks")
	while _stored_visuals.size() < delivered:
		var v := _sack_mesh()
		add_child(v)
		var i := _stored_visuals.size()
		v.global_position = village.spots["storehouse"] + Vector3(-1.0 + i * 0.55, 0.0, 2.0)
		v.rotation.y = i * 0.7
		_stored_visuals.append(v)


func _sync_sacks() -> void:
	# Remaining sacks = total minus delivered (a sack being carried at save time respawns).
	var delivered := MissionManager.objective_amount_done("ch1_main", "carry_sacks")
	for i in sacks.size():
		sacks[i].visible = i >= delivered
	_refresh_stored_sacks()


func _process(delta: float) -> void:
	super(delta)
	if player.carried_item == "bean_sack":
		farm_marker.global_position = storehouse.global_position
		return
	for s in sacks:
		if s.visible:
			farm_marker.global_position = s.global_position
			return
	farm_marker.global_position = storehouse.global_position


# =============================================================================
# Sequences
# =============================================================================

func _run_opening() -> void:
	running_sequence = "opening"
	_begin_cinematic()
	UI.set_black(true)
	await _wait(1.0)
	if aborted: return
	for line in data.get("opening_captions", []):
		_narrate(line)
		await _wait(maxf(4.2, line.length() * 0.075))
		if aborted: return
	_narrate("")
	await _wait(0.5)
	if aborted: return

	# Flyover: from high above the southern road, gliding down towards Emmanuel.
	var cam := Camera3D.new()
	cam.fov = 60
	add_child(cam)
	cam.current = true
	var start_pos: Vector3 = village.spots["start"]
	var from := Transform3D(Basis(), Vector3(-30, 38, -50)).looking_at(Vector3(0, 2, 0))
	var mid := Transform3D(Basis(), Vector3(28, 22, 20)).looking_at(Vector3(0, 0, 0))
	var to := Transform3D(Basis(), start_pos + Vector3(-1.5, 2.6, 6.0)).looking_at(start_pos + Vector3(1.0, 1.4, -4.0))
	UI.fade_in(2.5)
	_narrate(data.get("setting", ""))
	get_tree().create_timer(4.0, false).timeout.connect(func(): UI.caption(""))
	await _camera_move(cam, from, mid, to, 13.0)
	if aborted: return
	UI.caption("")
	UI.set_black(false)
	player.camera_rig.camera.current = true
	cam.queue_free()

	# Aline calls out from beside the road.
	npcs["aline"].face(player.global_position)
	player.face_towards(npcs["aline"].global_position)
	_end_cinematic()
	await DialogueManager.play("aline_intro")
	if aborted: return

	_aline_walk_to_hill()
	GameState.checkpoint = "free_roam"
	_sync_sacks()
	SaveManager.save_game("auto")
	running_sequence = ""


## Aline walks up the road to her hill so she is there when Emmanuel arrives.
func _aline_walk_to_hill() -> void:
	var aline: Node3D = npcs["aline"]
	aline.enabled = false
	var route := [Vector2(1, 50), Vector2(0, 30), Vector2(0, 0), Vector2(4, -22), Vector2(16, -38), Vector2(30, -52)]
	for p in route:
		if not is_inside_tree() or aline.global_position.distance_to(village.spots["aline_hill"]) < 1.0:
			break
		await aline.walk_to(village.ground(p), 1.7, village.height_at)
		if aborted: return
	_place_aline_on_hill()


func _place_aline_on_hill() -> void:
	var aline: Node3D = npcs["aline"]
	aline.global_position = village.spots["aline_hill"]
	aline.face(village.ground(Vector2(0, 0)))
	aline.enabled = true


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
	_narrate("That evening.")
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(1.5)
	if aborted: return
	_skip = false  # never let a held skip run into dialogue
	await DialogueManager.play("evening_radio")
	if aborted: return
	await _finish_chapter(1, "The Days of Friendship", "ch2", true)
