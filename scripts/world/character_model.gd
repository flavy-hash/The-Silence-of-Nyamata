extends Node3D
## Placeholder humanoid built from primitives, with a simple procedural walk cycle.
##
## TO REPLACE WITH REAL ART: set `model_scene` to an imported character (.glb/.tscn)
## facing +Z. The placeholder is then skipped. Wire your AnimationPlayer to
## set_motion() / set_carrying() if you want animation to follow gameplay.

@export var model_scene: PackedScene
@export var skin := Color(0.33, 0.21, 0.14)
@export var shirt := Color(0.92, 0.9, 0.84)
@export var pants := Color(0.18, 0.18, 0.2)
@export var hair := Color(0.06, 0.05, 0.04)
@export var dress := false
@export var headwrap := false
@export var headwrap_color := Color(0.8, 0.45, 0.15)
@export var hat := false
@export var body_scale := 1.0

var _t := 0.0
var _speed := 0.0
var _carrying := false
var _l_leg: Node3D
var _r_leg: Node3D
var _l_arm: Node3D
var _r_arm: Node3D
var _torso: Node3D
var _load: Node3D
var _mats := {}


func _ready() -> void:
	if model_scene:
		add_child(model_scene.instantiate())
		return
	_build()


func set_motion(speed: float) -> void:
	_speed = speed


## Shows a load (sack) balanced on the head, arms raised to steady it.
func set_carrying(on: bool) -> void:
	_carrying = on
	if _load:
		_load.visible = on


func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[c] = m
	return _mats[c]


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _build() -> void:
	var root := Node3D.new()
	root.scale = Vector3.ONE * body_scale
	add_child(root)

	# Legs pivot at the hip so they can swing.
	_l_leg = Node3D.new()
	_l_leg.position = Vector3(-0.1, 0.9, 0)
	_r_leg = Node3D.new()
	_r_leg.position = Vector3(0.1, 0.9, 0)
	for leg in [_l_leg, _r_leg]:
		root.add_child(leg)
		_part(leg, _capsule(0.085, 0.92), pants if not dress else skin, Vector3(0, -0.45, 0))
		_part(leg, BoxMesh.new(), Color(0.12, 0.1, 0.08), Vector3(0, -0.9, 0.05), Vector3(0.12, 0.06, 0.24))

	_torso = Node3D.new()
	root.add_child(_torso)
	_part(_torso, _capsule(0.21, 0.72), shirt, Vector3(0, 1.22, 0), Vector3(1, 1, 0.72))
	if dress:
		var skirt := CylinderMesh.new()
		skirt.top_radius = 0.2
		skirt.bottom_radius = 0.33
		skirt.height = 0.62
		skirt.radial_segments = 14
		_part(_torso, skirt, shirt, Vector3(0, 0.74, 0))

	# Arms pivot at the shoulder.
	_l_arm = Node3D.new()
	_l_arm.position = Vector3(-0.27, 1.47, 0)
	_r_arm = Node3D.new()
	_r_arm.position = Vector3(0.27, 1.47, 0)
	for arm in [_l_arm, _r_arm]:
		_torso.add_child(arm)
		_part(arm, _capsule(0.06, 0.62), shirt, Vector3(0, -0.24, 0))
		_part(arm, _sphere(0.055), skin, Vector3(0, -0.56, 0))

	# Head, hair and a hint of a face so facing direction reads clearly.
	_part(_torso, _capsule(0.06, 0.16), skin, Vector3(0, 1.6, 0))
	_part(_torso, _sphere(0.13), skin, Vector3(0, 1.73, 0), Vector3(1, 1.1, 1))
	if headwrap:
		_part(_torso, _sphere(0.145), headwrap_color, Vector3(0, 1.81, -0.02), Vector3(1.05, 0.75, 1.05))
	else:
		_part(_torso, _sphere(0.135), hair, Vector3(0, 1.77, -0.015), Vector3(1, 0.72, 1))
	if hat:
		var brim := CylinderMesh.new()
		brim.top_radius = 0.24
		brim.bottom_radius = 0.24
		brim.height = 0.02
		_part(_torso, brim, Color(0.72, 0.62, 0.42), Vector3(0, 1.86, 0))
		var crown := CylinderMesh.new()
		crown.top_radius = 0.11
		crown.bottom_radius = 0.13
		crown.height = 0.12
		_part(_torso, crown, Color(0.72, 0.62, 0.42), Vector3(0, 1.92, 0))
	for x in [-0.045, 0.045]:
		_part(_torso, _sphere(0.017), Color(0.05, 0.04, 0.03), Vector3(x, 1.75, 0.118))

	# Sack carried on the head (hidden until needed).
	_load = Node3D.new()
	_torso.add_child(_load)
	var sack := _part(_load, _capsule(0.2, 0.6), Color(0.72, 0.6, 0.4), Vector3(0, 2.02, 0), Vector3(1, 0.6, 1))
	sack.rotation.z = PI / 2
	_load.visible = false


func _process(delta: float) -> void:
	if _l_leg == null:
		return
	var move := clampf(_speed / 3.2, 0.0, 1.6)
	_t += delta * (2.0 + 5.5 * move)
	var swing := sin(_t) * 0.55 * clampf(move, 0.0, 1.0)
	_l_leg.rotation.x = swing
	_r_leg.rotation.x = -swing
	if _carrying:
		# Both hands up, steadying the load.
		_l_arm.rotation = Vector3(0, 0, -2.6)
		_r_arm.rotation = Vector3(0, 0, 2.6)
	else:
		_l_arm.rotation = Vector3(-swing * 0.8, 0, 0)
		_r_arm.rotation = Vector3(swing * 0.8, 0, 0)
	# Gentle breathing when idle, a little bounce when walking.
	_torso.position.y = abs(sin(_t)) * 0.03 * move + sin(_t * 0.5) * 0.005
