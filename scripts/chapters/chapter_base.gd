extends Node3D
## Shared chapter "director" logic. Each chapter script extends this and implements:
##   _data_path()                       path to data/chapters/<id>.json
##   _spawn_extras()                    chapter-specific objects (tasks, triggers…)
##   _on_checkpoint(name, world)        where to begin for "start" / saved checkpoints
##   _on_story_event(name, data)        react to {"event": ...} effects from dialogue/missions
##
## Chapter JSON keys used here:
##   dialogue, time_of_day, ambience, player_start {spot, yaw},
##   npcs {id: {name, spot, face | yaw, look, voice, conversations, barks}},
##   kids [{name, look, barks, conversations}],
##   world ("village" | "road" | "river" | "compound"), damaged (bool),
##   cover [{at, radius}]            tall grass the player can crouch in,
##   watchers [{route: [points], facing, view, barks}]   patrols / guards
## A "point" is a spot name or an [x, z] pair.

signal finished
signal caught

const WORLDS := {
	"village": "res://scripts/world/village_builder.gd",
	"road": "res://scripts/world/road_builder.gd",
	"river": "res://scripts/world/river_builder.gd",
	"compound": "res://scripts/world/compound_builder.gd",
}
const Player := preload("res://scripts/player/player.gd")
const Npc := preload("res://scripts/world/npc.gd")
const Watcher := preload("res://scripts/world/watcher.gd")
const CoverZone := preload("res://scripts/world/cover_zone.gd")

var data: Dictionary
var village: Node3D
var player: CharacterBody3D
var npcs := {}                 # id -> npc node
var kids: Array = []
var running_sequence := ""
## Set by Router when leaving the chapter; scripted sequences stop at their next step.
var aborted := false
## Indexes of children who are playing; the rest stand at the "kids_apart" spot.
var kids_playing: Array = []
## Optional per-child idle position (index -> Vector3) for children not playing.
var kid_idle_spots := {}

# Stealth and companions.
var watchers: Array = []
var followers: Array = []
var respawn := {"pos": Vector3.ZERO, "yaw": 0.0}
var caught_count := 0
## Tests switch this off to check story flow without patrols interfering.
var stealth_enabled := true
var _catching := false

var _skip := false
var _skip_hold := 0.0
var _kid_t := 0.0
var _ball: Node3D


func _data_path() -> String:
	return ""


func _ready() -> void:
	add_to_group("chapter")
	data = DataLoader.load_json(_data_path(), {})
	MissionManager.register_missions(data.get("missions", {}))
	DialogueManager.load_file(data["dialogue"])
	GameState.story_event.connect(_on_story_event)

	village = load(WORLDS[data.get("world", "village")]).new()
	village.name = "World"
	village.damaged = data.get("damaged", false)
	add_child(village)
	village.build()
	_spawn_cover()
	village.set_time_of_day(data.get("time_of_day", "morning"))
	_ball = village.get_node_or_null("Ball")

	_spawn_player()
	_spawn_npcs()
	_spawn_watchers()
	_spawn_extras()
	village.flush()
	set_respawn(player.global_position, player.model.rotation.y)

	UI.clear_meters()
	UI.set_gameplay(true)
	UI.set_black(false)
	AudioManager.play_ambience(data.get("ambience", "village_day"))
	_enter.call_deferred()


func _exit_tree() -> void:
	if GameState.story_event.is_connected(_on_story_event):
		GameState.story_event.disconnect(_on_story_event)
	GameState.unlock("cinematic")


## Decide where to begin based on the checkpoint (new game or loaded save).
func _enter() -> void:
	var world: Dictionary = Router.pending_world
	Router.pending_world = {}
	_on_checkpoint(GameState.checkpoint, world)


func _spawn_extras() -> void:
	pass


func _on_checkpoint(_checkpoint: String, _world: Dictionary) -> void:
	pass


func _on_story_event(_event_name: String, _data: Dictionary) -> void:
	pass


# =============================================================================
# Spawning
# =============================================================================

func _spawn_player() -> void:
	player = Player.new()
	player.name = "Emmanuel"
	add_child(player)
	var start: Dictionary = data.get("player_start", {})
	player.place_at(village.spots[start.get("spot", "start")], float(start.get("yaw", PI)))


func _look(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var v = src[k]
		out[k] = Color(v) if v is String and v.begins_with("#") else v
	return out


func _make_npc(id: String, d: Dictionary) -> Node3D:
	var n := Npc.new()
	n.setup(id, d["name"], _look(d.get("look", {})))
	n.voice_id = d.get("voice", id)
	n.conversations = d.get("conversations", [])
	n.barks = d.get("barks", [])
	n.name = id.capitalize()
	add_child(n)
	if d.has("spot"):
		n.global_position = pt(d["spot"])
	_apply_facing(n, d)
	return n


func _apply_facing(n: Node3D, d: Dictionary) -> void:
	if d.has("yaw"):
		n.set_facing(float(d["yaw"]))
	elif d.has("face"):
		n.face(pt(d["face"]))
		n.set_facing(n.model.rotation.y)


## A spot name or [x, z] pair -> point on the ground.
func pt(v) -> Vector3:
	if v is String:
		return village.spots[v]
	return village.ground(Vector2(v[0], v[1]))


func _spawn_npcs() -> void:
	for id in data.get("npcs", {}):
		npcs[id] = _make_npc(id, data["npcs"][id])
	var kid_data: Array = data.get("kids", [])
	for i in kid_data.size():
		var kd: Dictionary = kid_data[i].duplicate()
		kd["spot"] = "kids"
		if not kd.has("voice"):
			kd["voice"] = "child"
		var k := _make_npc("kid_%d" % i, kd)
		kids.append(k)
		kids_playing.append(i)


func _spawn_cover() -> void:
	for c in data.get("cover", []):
		add_cover(pt(c["at"]), float(c.get("radius", 4.0)))


## Tall grass the player can hide in (visual + cover zone).
func add_cover(at: Vector3, radius: float) -> void:
	village.tall_grass(Vector2(at.x, at.z), radius, int(radius * radius * 3.0))
	var z := CoverZone.new()
	z.setup(radius)
	add_child(z)
	z.global_position = at


func _spawn_watchers() -> void:
	for w in data.get("watchers", []):
		var points := []
		for p in w["route"]:
			points.append(pt(p))
		add_watcher(points, float(w.get("facing", 0.0)), w.get("barks", []), float(w.get("view", 13.0)))


func add_watcher(points: Array, facing := 0.0, barks: Array = [], view := 13.0) -> Node3D:
	var w := Watcher.new()
	w.view_distance = view
	w.setup(points, village.height_at, data.get("time_of_day", "") == "night", facing)
	w.barks = barks
	add_child(w)
	watchers.append(w)
	return w


# =============================================================================
# Companions
# =============================================================================

func add_follower(n: Node3D) -> void:
	if n in followers:
		return
	followers.append(n)
	n.show()
	n.start_following(player, followers.size() - 1, village.height_at)


func remove_follower(n: Node3D) -> void:
	followers.erase(n)
	n.stop_following()
	for i in followers.size():
		followers[i].follow_slot = i


## Who is travelling with Emmanuel, from the choices made so far (Chapters 5–7).
## Aline, Gasana and Solange always; Claudine and Eric if sheltered in Chapter 3;
## Innocent if his wound was treated in Chapter 5.
func group_ids() -> Array:
	var ids := ["aline", "gasana", "solange"]
	if GameState.get_flag("ch3_sheltered_claudine"):
		ids += ["claudine", "eric"]
	if GameState.get_flag("ch5_treated_innocent"):
		ids.append("innocent")
	return ids


## Makes the travelling group follow the player; hides group members who are not here.
func spawn_group(exclude: Array = []) -> void:
	for id in ["aline", "gasana", "solange", "claudine", "eric", "innocent"]:
		if not npcs.has(id) or id in exclude:
			continue
		if id in group_ids():
			add_follower(npcs[id])
		elif id != "innocent":
			npcs[id].hide()
	gather_followers()


## Puts every follower right behind the player (after a teleport or retry).
func gather_followers() -> void:
	var back := -Vector3(sin(player.model.rotation.y), 0, cos(player.model.rotation.y))
	for i in followers.size():
		var p: Vector3 = player.global_position + back * (1.5 + i * 0.9)
		p.y = village.height_at(p.x, p.z)
		followers[i].global_position = p


# =============================================================================
# Stealth
# =============================================================================

func set_respawn(pos: Vector3, yaw: float) -> void:
	respawn = {"pos": pos, "yaw": yaw}


func set_respawn_spot(spot, yaw: float) -> void:
	set_respawn(pt(spot), yaw)


func _physics_process(delta: float) -> void:
	if aborted:
		return
	_update_stealth(delta)


func _update_stealth(delta: float) -> void:
	if watchers.is_empty() or not stealth_enabled:
		return
	if GameState.is_locked() or get_tree().paused or _catching:
		UI.set_status("")
		return
	var top := 0.0
	for w in watchers:
		if w.visible and w.is_inside_tree():
			w.sense(player, delta)
			top = maxf(top, w.awareness)
	if top > 0.02:
		UI.set_meter("seen", "Someone is looking this way", top, Color(0.85, 0.35 + 0.4 * (1.0 - top), 0.2))
	else:
		UI.clear_meter("seen")
	UI.set_status("Hidden" if player.is_concealed() else ("Crouching" if player.crouched else ""))
	if top >= 1.0:
		_on_caught()


## Being seen never leads to violence on screen: Emmanuel slips away and the
## player tries again from the last safe point.
func _on_caught() -> void:
	if _catching:
		return
	_catching = true
	caught_count += 1
	GameState.lock("caught")
	UI.clear_meter("seen")
	caught.emit()
	await UI.fade_out(0.8)
	if aborted: return
	UI.caption("You were seen, and had to slip away into the dark.\nYou make your way back and try again.")
	for w in watchers:
		w.reset_to_start()
	player.place_at(respawn["pos"] + Vector3(0, 0.1, 0), respawn["yaw"])
	player.set_crouched(true)
	gather_followers()
	await _wait(2.5)
	if aborted: return
	UI.caption("")
	await UI.fade_in(0.8)
	GameState.unlock("caught")
	_catching = false


## Lines heard but not taken part in (voices through a wall, outside the door).
## The player keeps control. Each entry: {speaker, text, wait}.
func _overhear(lines: Array) -> void:
	for l in lines:
		if aborted:
			return
		var text: String = l["text"]
		if Settings.intensity == "reduced" and l.has("text_reduced"):
			text = l["text_reduced"]
		UI.bark(DialogueManager.speaker_name(l["speaker"]), text)
		AudioManager.speak(l["speaker"], text)
		var t := 0.0
		var dur := float(l.get("wait", maxf(2.5, text.length() * 0.075)))
		while t < dur and not aborted:
			await get_tree().process_frame
			if not get_tree().paused:
				t += get_process_delta_time()


# =============================================================================
# Cinematics
# =============================================================================

func _begin_cinematic() -> void:
	_skip = false
	_skip_hold = 0.0
	GameState.lock("cinematic")
	UI.set_cinematic(true)
	UI.set_skip_progress(0.0)


func _end_cinematic() -> void:
	GameState.unlock("cinematic")
	UI.set_cinematic(false)
	_skip = false


## Waits `t` seconds of unpaused game time; returns early if the player skips.
func _wait(t: float) -> void:
	var elapsed := 0.0
	while elapsed < t and not _skip and is_inside_tree():
		await get_tree().process_frame
		if not get_tree().paused:
			elapsed += get_process_delta_time()


## On-screen narration caption, also read aloud by the narrator voice.
func _narrate(text: String) -> void:
	UI.caption(text)
	if text != "":
		AudioManager.speak("narrator", text)


func _bezier_xf(a: Transform3D, b: Transform3D, c: Transform3D, t: float) -> Transform3D:
	var ab := a.interpolate_with(b, t)
	var bc := b.interpolate_with(c, t)
	return ab.interpolate_with(bc, t)


## Plays a curved camera move; returns when finished or skipped.
func _camera_move(cam: Camera3D, from: Transform3D, mid: Transform3D, to: Transform3D, duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(t: float): cam.global_transform = _bezier_xf(from, mid, to, t), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while tw.is_running() and not _skip and not aborted:
		await get_tree().process_frame
	tw.kill()


## A fixed side-on camera framing two characters (used for quiet conversations at home).
func _two_shot(a: Vector3, b: Vector3, offset := Vector3(-2.3, 1.5, 3.9)) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	var mid := (a + b) / 2.0
	cam.global_transform = Transform3D(Basis(), mid + offset).looking_at(mid + Vector3(0, 1.05, 0))
	cam.current = true
	return cam


## Moves Emmanuel and Joseph to the bench outside their home for an evening scene.
func _stage_evening_at_home() -> Camera3D:
	village.set_time_of_day("dusk")
	AudioManager.play_ambience("village_dusk")
	for id in npcs:
		if id != "joseph":
			npcs[id].hide()
	for k in kids:
		k.hide()
	if _ball:
		_ball.hide()
	player.drop_carried()
	var joseph: Node3D = npcs["joseph"]
	joseph.global_position = village.spots["evening_joseph"]
	player.place_at(village.spots["evening_player"], -2.4)
	player.face_towards(joseph.global_position)
	joseph.face(player.global_position)
	return _two_shot(village.spots["evening_joseph"], village.spots["evening_player"])


## Title card, unlock the next chapter, autosave there, and return to the title screen.
func _finish_chapter(number: int, title: String, next_id: String, show_game_title := false) -> void:
	await UI.fade_out(2.5)
	if aborted: return
	if show_game_title:
		UI.show_title_card("THE SILENCE OF NYAMATA")
		await _wait(5.0)
		if aborted: return
		UI.hide_title_card(1.2)
		await _wait(1.5)
		if aborted: return
	GameState.set_flag("%s_complete" % data["id"])
	SaveManager.unlock_chapter(next_id)
	GameState.current_chapter = next_id
	GameState.checkpoint = "start"
	SaveManager.save_game("auto")
	UI.show_title_card("Chapter %d complete" % number, title)
	await _wait(3.5)
	if aborted: return
	UI.hide_title_card(0.8)
	await _wait(1.0)
	if aborted: return
	running_sequence = ""
	_end_cinematic()
	finished.emit()
	UI.set_black(false)
	Router.go_to_title()


func _restore_player(world: Dictionary) -> void:
	var p = world.get("player")
	if p is Array and p.size() == 3:
		player.place_at(Vector3(p[0], p[1] + 0.1, p[2]), float(world.get("yaw", PI)))


# =============================================================================
# Per-frame
# =============================================================================

func _process(delta: float) -> void:
	if aborted:
		return
	_update_skip(delta)
	_animate_kids(delta)


func _update_skip(delta: float) -> void:
	if not GameState.is_locked("cinematic") or DialogueManager.is_active() or get_tree().paused:
		_skip_hold = 0.0
		return
	if Input.is_action_pressed("advance"):
		_skip_hold += delta
		UI.set_skip_progress(min(_skip_hold / 1.0, 1.0))
		if _skip_hold >= 1.0:
			_skip = true
			AudioManager.stop_voice()
	elif _skip_hold > 0.0:
		_skip_hold = 0.0
		UI.set_skip_progress(0.0)


## Children kick the ball around the pitch in loose loops. Those not in
## `kids_playing` stand quietly to one side at the "kids_apart" spot.
func _animate_kids(delta: float) -> void:
	if kids.is_empty() or not kids[0].visible:
		return
	_kid_t += delta
	var c: Vector3 = village.spots["kids"]
	var n := kids_playing.size()
	for i in kids.size():
		var k: Node3D = kids[i]
		var p: Vector3
		var slot := kids_playing.find(i)
		if slot >= 0:
			var w := 0.35 + slot * 0.07
			var a := _kid_t * w + slot * TAU / maxi(n, 1)
			var r := 5.0 + 2.0 * sin(_kid_t * 0.3 + slot)
			p = Vector3(c.x + cos(a) * r * 1.4, 0, c.z + sin(a) * r * 0.7)
		else:
			p = kid_idle_spots.get(i, village.spots["kids_apart"] + Vector3((i % 2) * 0.9, 0, 0))
		p.y = village.height_at(p.x, p.z)
		var prev := k.global_position
		var target := prev.move_toward(p, (7.0 if slot >= 0 else 2.0) * delta)
		target.y = village.height_at(target.x, target.z)
		k.global_position = target
		var v := (target - prev) / maxf(delta, 0.0001)
		if v.length() > 0.1:
			k.model.rotation.y = atan2(v.x, v.z)
		elif slot < 0:
			k.face(c)
		k.model.set_motion(v.length())
	if _ball and n > 0:
		var lead: Vector3 = kids[kids_playing[int(_kid_t / 3.0) % n]].global_position
		var bp := _ball.global_position.lerp(lead + Vector3(0.4, 0, 0.4), 1.0 - exp(-2.0 * delta))
		bp.y = village.height_at(bp.x, bp.z) + 0.12
		_ball.global_position = bp


# =============================================================================
# Save support
# =============================================================================

func get_world_state() -> Dictionary:
	var p := player.global_position
	return {"player": [p.x, p.y, p.z], "yaw": player.model.rotation.y}
