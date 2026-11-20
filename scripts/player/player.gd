extends CharacterBody3D
## Emmanuel: third-person movement, stamina, interaction and carrying.
##
## Movement is camera-relative. Sprinting drains stamina; once fully drained the
## player must recover to 30% before sprinting again. Carrying a load is slower
## and prevents sprinting.

const CharacterModel := preload("res://scripts/world/character_model.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")

@export var walk_speed := 3.4
@export var run_speed := 6.2
@export var carry_speed := 2.5
@export var acceleration := 10.0
@export var turn_speed := 10.0
@export var max_stamina := 100.0
@export var stamina_drain := 20.0
@export var stamina_regen := 15.0

var stamina := 100.0
var exhausted := false
var carried_item := ""        # item id currently held (e.g. "bean_sack"), "" if none
var model: Node3D
var camera_rig: Node3D
var focus: Node = null        # interactable currently in reach

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("player")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.75
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.875
	add_child(col)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)

	model = CharacterModel.new()
	model.shirt = Color(0.93, 0.92, 0.87)
	model.pants = Color(0.2, 0.22, 0.28)
	add_child(model)

	camera_rig = CameraRig.new()
	camera_rig.target = self
	add_child(camera_rig)
	camera_rig.camera.current = true
	UI.carrying_text = func(): return "Carrying: %s" % GameState.item_name(carried_item) if carried_item != "" else ""


func can_control() -> bool:
	return not GameState.is_locked() and not get_tree().paused


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if can_control():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir: Vector3 = camera_rig.get_yaw_basis() * Vector3(input.x, 0, input.y)
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()

	# Sprint and stamina.
	var wants_sprint := can_control() and Input.is_action_pressed("sprint") and dir.length() > 0.1 \
		and carried_item == "" and not exhausted
	if wants_sprint:
		stamina = max(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = min(stamina + stamina_regen * delta, max_stamina)
		if exhausted and stamina >= max_stamina * 0.3:
			exhausted = false
	UI.set_stamina(stamina, max_stamina)

	var speed := walk_speed
	if carried_item != "":
		speed = carry_speed
	elif wants_sprint:
		speed = run_speed

	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(dir * speed, acceleration * speed * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	if dir.length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), turn_speed * delta)
	model.set_motion(Vector3(velocity.x, 0, velocity.z).length())

	_update_focus()
	if can_control() and Input.is_action_just_pressed("interact"):
		interact()


## Picks the nearest usable interactable in reach, preferring ones in front.
func _update_focus() -> void:
	var best: Node = null
	var best_score := INF
	if can_control():
		var fwd := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
		for n in get_tree().get_nodes_in_group("interactable"):
			if not n.is_interactable(self):
				continue
			var to: Vector3 = n.get_interact_position() - global_position
			to.y = 0
			var d := to.length()
			if d > n.interact_radius:
				continue
			var facing := fwd.dot(to.normalized()) if d > 0.01 else 1.0
			var score := d - facing * 0.8
			if score < best_score:
				best_score = score
				best = n
	focus = best
	UI.set_prompt("[E]  %s" % best.get_prompt(self) if best else "")


func interact() -> bool:
	_update_focus()
	if focus == null:
		return false
	face_towards(focus.get_interact_position())
	focus.interact(self)
	return true


func face_towards(pos: Vector3) -> void:
	var to := pos - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		model.rotation.y = atan2(to.x, to.z)


func pick_up(item_id: String) -> bool:
	if carried_item != "":
		return false
	carried_item = item_id
	model.set_carrying(true)
	return true


func drop_carried() -> String:
	var id := carried_item
	carried_item = ""
	model.set_carrying(false)
	return id


## Teleport (spawns, checkpoints, cutscenes).
func place_at(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	model.rotation.y = yaw
	camera_rig.snap(yaw + PI)
