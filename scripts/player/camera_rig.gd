extends Node3D
## Third-person orbit camera. A SpringArm3D keeps the camera from clipping
## into walls and terrain. Mouse / right stick rotate it; it follows the target smoothly.

@export var distance := 4.2
@export var height := 1.55
@export var min_pitch := -1.1
@export var max_pitch := 0.35
@export var follow_sharpness := 12.0
@export var stick_speed := 2.6

var target: Node3D
var yaw := 0.0
var pitch := -0.28
var camera: Camera3D
var spring: SpringArm3D
var _shake := 0.0


func _ready() -> void:
	top_level = true
	spring = SpringArm3D.new()
	spring.spring_length = distance
	spring.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.position.x = 0.35   # slight over-the-shoulder offset
	spring.add_child(camera)
	if target is CollisionObject3D:
		spring.add_excluded_object(target.get_rid())
	if target:
		global_position = target.global_position + Vector3(0, height, 0)


func _controls_enabled() -> bool:
	return not GameState.is_locked() and not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _controls_enabled():
		var s := Settings.mouse_sensitivity * 0.01
		yaw -= event.relative.x * s
		pitch -= event.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, min_pitch, max_pitch)


func _process(delta: float) -> void:
	if _controls_enabled():
		var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.15:
			yaw -= look.x * stick_speed * delta
			pitch -= look.y * stick_speed * delta * (-1.0 if Settings.invert_y else 1.0)
			pitch = clampf(pitch, min_pitch, max_pitch)
	if target:
		var goal := target.global_position + Vector3(0, height, 0)
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(pitch, yaw, 0)

	# Camera shake, disabled entirely by the "reduced screen shake" setting.
	if _shake > 0.0 and not Settings.reduced_shake:
		camera.h_offset = randf_range(-1, 1) * _shake * 0.08
		camera.v_offset = randf_range(-1, 1) * _shake * 0.08
		_shake = max(_shake - delta * 2.0, 0.0)
	else:
		_shake = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func shake(amount: float = 0.5) -> void:
	_shake = max(_shake, amount)


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Snap behind the target, facing the given yaw.
func snap(new_yaw: float, new_pitch: float = -0.28) -> void:
	yaw = new_yaw
	pitch = new_pitch
	if target:
		global_position = target.global_position + Vector3(0, height, 0)
	rotation = Vector3(pitch, yaw, 0)
