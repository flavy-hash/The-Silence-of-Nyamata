extends "res://scripts/world/village_builder.gd"
## The river (Chapter 7). A wide river winds north–south through papyrus marsh.
## Most of it is too deep or too fast to cross; there is one shallow ford, where
## the water is wide and quiet. Invisible barriers in the channel leave only the
## ford open. Wading is slow (see chapter_7.gd).

const FORD_Z := 34.0
const WATER_Y := -0.15

const SPOTS_V := {
	"start": Vector2(-62, 2), "camp": Vector2(-22, 6),
	"test_north": Vector2(-7.0, -30), "test_mid": Vector2(-2.0, 0), "test_ford": Vector2(2.0, 34),
	"ford_west": Vector2(1.0, 34), "ford_east": Vector2(25.0, 34), "far_camp": Vector2(34, 38),
	"ridge": Vector2(-40, -40),
	"evening_joseph": Vector2(33, 37), "evening_player": Vector2(34.6, 38.4),
}

const PATHS_V := [
	[Vector2(-72, 2), Vector2(-40, 4), Vector2(-22, 6), Vector2(-8, 20), Vector2(1, 34)],
	[Vector2(25, 34), Vector2(34, 38), Vector2(60, 46)],
]


func _spot_defs() -> Dictionary:
	return SPOTS_V


func _paths() -> Array:
	return PATHS_V


## Centre line of the river at a given z.
func river_x(z: float) -> float:
	return 8.0 + 6.0 * sin(z * 0.03)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_Y + 0.05


func is_east_bank(x: float, z: float) -> bool:
	return x > river_x(z) + 9.0


func height_at(x: float, z: float) -> float:
	var h := 2.0 + 1.3 * sin(x * 0.03 + 0.5) + 0.9 * cos(z * 0.035)
	var r := Vector2(x, z).length()
	h += smoothstep(90.0, 150.0, r) * 24.0
	var d := absf(x - river_x(z))
	var carve := 1.0 - smoothstep(5.0, 11.0, d)
	h = lerp(h, -2.2, carve)
	# The ford: a broad shallow bar across the riverbed.
	var ford := 1.0 - smoothstep(1.8, 3.2, absf(z - FORD_Z))
	h = maxf(h, lerp(h, -0.45, ford * carve))
	return h


func _ground_tint(c: Color, x: float, z: float, h: float) -> Color:
	if h < 0.2:
		c = c.lerp(Color(0.32, 0.28, 0.2), 0.7)   # mud banks
	return c


func _build_structures() -> void:
	# Water surface.
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 360)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.25, 0.32, 0.3, 0.82)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	water.material_override = wm
	water.position = Vector3(8, WATER_Y, 0)
	add_child(water)
	# Barriers in the deep channel, everywhere except the ford.
	var z := -170.0
	while z < 170.0:
		if absf(z - FORD_Z) > 3.0:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(3.0, 8.0, 4.4)
			cs.shape = box
			body.add_child(cs)
			body.position = Vector3(river_x(z), -1.0, z)
			add_child(body)
		z += 4.0
	# Papyrus along both banks.
	for k in 420:
		var zz := _rng.randf_range(-120, 120)
		if absf(zz - FORD_Z) < 5.0:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var xx := river_x(zz) + side * _rng.randf_range(6.5, 11.0)
		var p := Vector2(xx, zz)
		var hh := _rng.randf_range(1.6, 2.6)
		_add_multi("papyrus", _cyl_mesh(0.02, 0.03, 1.0), Color(0.35, 0.45, 0.2),
			Transform3D(Basis().scaled(Vector3(1, hh, 1)), ground(p) + Vector3(0, hh / 2.0, 0)))
		_add_multi("papyrus_head", _sphere_mesh(), Color(0.42, 0.52, 0.22),
			Transform3D(Basis().scaled(Vector3(0.22, 0.12, 0.22)), ground(p) + Vector3(0, hh, 0)))
	# Stakes marking the three places to test the water.
	for s in ["test_north", "test_mid", "test_ford"]:
		_cyl(self, ground(spot_defs[s]) + Vector3(0.4, 0.5, 0.4), 0.04, 1.0, Color(0.4, 0.3, 0.2))
	# Embers of the camp.
	_cyl(self, ground(spot_defs["camp"]) + Vector3(0, 0.05, 0), 0.5, 0.1, Color(0.2, 0.18, 0.16))
	_keep_out.append([spot_defs["camp"], 6.0])
	_keep_out.append([spot_defs["far_camp"], 6.0])
	# Keep vegetation off the channel.
	z = -170.0
	while z < 170.0:
		_keep_out.append([Vector2(river_x(z), z), 12.0])
		z += 8.0


func _vegetation_clusters() -> Array:
	return [Vector2(-40, 20), Vector2(-30, -20), Vector2(50, 50), Vector2(44, 10), Vector2(-50, -10)]
