extends Node3D
## Builds the Chapter 1 village from placeholder primitives: rolling-hill terrain
## with collision, red-earth footpaths, homes, Mama Beata's shop, market stalls,
## the school, a football field, Gasana's bean field and storehouse, banana groves,
## trees, and Aline's hill. Also owns the sky, sun and time-of-day lighting.
##
## Everything here is a stand-in. To replace with real art, swap individual
## builders (e.g. _house) for instanced .glb scenes at the same positions;
## gameplay code only depends on `spots`, `height_at()` and the nodes it is given.
##
## Coordinates: metres, +X east, -Z north. The village square is at the origin.

const HILL := Vector2(42, -66)
const WORLD_HALF := 180.0       # visual terrain half-size
const PLAY_RADIUS := 100.0      # invisible boundary
const MESH_STEP := 2.0
const COL_HALF := 110           # collision heightmap half-size (1 m spacing)

# Named positions used by the chapter director (x, z). Heights come from height_at().
const SPOTS := {
	"start": Vector2(1.5, 62), "bicycle": Vector2(2.8, 63.5), "aline_intro": Vector2(3.6, 56.5),
	"gasana": Vector2(-35, -21), "storehouse": Vector2(-24, -38),
	"sack_1": Vector2(-37.5, -25), "sack_2": Vector2(-36.4, -26.4), "sack_3": Vector2(-38.2, -26.9),
	"beata": Vector2(10.45, 0.8), "uwase": Vector2(23.5, 5.5), "claudine": Vector2(-10, -2.4),
	"patrick": Vector2(34.5, 16.5), "kids": Vector2(42, 23),
	"joseph": Vector2(-30.5, 19.5), "home_door": Vector2(-34, 18.6),
	"aline_hill": Vector2(37.5, -58.5), "hill_view": Vector2(36.0, -56.5),
	"evening_player": Vector2(-31.4, 21.6), "evening_joseph": Vector2(-33.2, 20.4),
	"radio": Vector2(-32.4, 20.1),
	# Chapter 2
	"bosco": Vector2(-6, -6.4), "radio_stall": Vector2(-5.3, -5.1),
	"notice": Vector2(22.0, 7.4), "kids_apart": Vector2(31.5, 27.5),
	"stranger_1": Vector2(31.2, 13.6), "stranger_2": Vector2(32.4, 12.6),
	# Chapter 3 (night)
	"sandal": Vector2(45.5, 27.5), "claudine_hide": Vector2(-22.5, -6.2), "gasana_hide": Vector2(-21.6, -40.5),
	"beata_window": Vector2(17.2, 0.8), "home_inside": Vector2(-34, 16.5),
	"field_cover": Vector2(36.0, 34.0), "shop_back": Vector2(19.5, -3.0),
	# Chapter 8
	"memorial": Vector2(-2.5, -1.5), "aline_return": Vector2(2.5, 30), "olivier": Vector2(11.4, 2.2),
}

# Footpaths as polylines.
const PATHS := [
	[Vector2(0, 175), Vector2(1, 60), Vector2(0, 30), Vector2(0, 0), Vector2(4, -22), Vector2(16, -38), Vector2(30, -52), Vector2(37, -58)],
	[Vector2(0, 6), Vector2(-18, 10), Vector2(-33, 17)],
	[Vector2(2, -4), Vector2(-18, -12), Vector2(-33, -20), Vector2(-26, -35)],
	[Vector2(3, -3), Vector2(12, -5), Vector2(22, -4), Vector2(23, 8), Vector2(34, 14)],
]

# Areas kept free of scattered vegetation.
var _keep_out: Array = []   # [Vector2 centre, radius]
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _multi := {}            # key -> {mesh, color, transforms}

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var spots := {}             # name -> Vector3 on the ground
var spot_defs := {}         # name -> Vector2 (x, z)
var paths: Array = []       # footpath polylines
## Chapter 8: the village after the genocide (damaged homes, empty market).
var damaged := false
## Optional extra positions (name -> Vector2) for a chapter to use.
var extra_spots := {}


## Overridable layout hooks for other maps (road, river, interior).
func _spot_defs() -> Dictionary:
	return SPOTS


func _paths() -> Array:
	return PATHS


func _build_structures() -> void:
	_build_village()


func build() -> void:
	_rng.seed = 1993
	spot_defs = _spot_defs().duplicate()
	spot_defs.merge(extra_spots)
	paths = _paths()
	for k in spot_defs:
		spots[k] = ground(spot_defs[k])
	_build_environment()
	_build_terrain()
	_build_boundary()
	_build_structures()
	# Never grow bushes or trees on top of a story location.
	for k in spot_defs:
		_keep_out.append([spot_defs[k], 2.5])
	_build_vegetation()
	_flush_multimeshes()
	set_time_of_day("morning")


# =============================================================================
# Terrain
# =============================================================================

## Terrain height at (x, z). Pure function: the mesh and collision both use it.
func height_at(x: float, z: float) -> float:
	var h := 2.4 * sin(x * 0.043 + 0.6) + 1.9 * cos(z * 0.051 - 0.3) + 1.3 * sin((x - z) * 0.031)
	var r := Vector2(x, z).length()
	h += smoothstep(80.0, 150.0, r) * 26.0          # surrounding hills frame the valley
	var dh := Vector2(x, z).distance_to(HILL)
	h += 15.0 * exp(-dh * dh / (2.0 * 19.0 * 19.0))  # Aline's hill
	h = _flatten(h, x, z, Vector2(0, 0), 30.0, 50.0, 0.0)
	h = _flatten(h, x, z, Vector2(40, 22), 13.0, 24.0, 0.2)
	h = _flatten(h, x, z, Vector2(-34, 16), 7.0, 15.0, 0.4)
	h = _flatten(h, x, z, Vector2(-44, -28), 11.0, 21.0, 0.6)
	return h


func _flatten(h: float, x: float, z: float, c: Vector2, r_in: float, r_out: float, target: float) -> float:
	var w := 1.0 - smoothstep(r_in, r_out, Vector2(x, z).distance_to(c))
	return lerp(h, target, w)


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)


func _path_distance(p: Vector2) -> float:
	var best := INF
	for path in paths:
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = min(best, p.distance_to(a + ab * t))
	return best


func _ground_color(x: float, z: float, h: float) -> Color:
	var grass := Color(0.26, 0.4, 0.18)
	var grass_dry := Color(0.4, 0.42, 0.21)
	var dirt := Color(0.5, 0.27, 0.16)       # red laterite earth
	var n := sin(x * 0.21) * cos(z * 0.17) * 0.5 + sin(x * 0.07 + z * 0.09) * 0.5
	var c := grass.lerp(grass_dry, clampf(0.35 + n * 0.35 + h * 0.01, 0.0, 1.0))
	c = _ground_tint(c, x, z, h)
	if abs(x) < 120 and abs(z) < 180:
		var pd := _path_distance(Vector2(x, z))
		c = c.lerp(dirt, 1.0 - smoothstep(1.2, 2.6, pd))
	return c


## Layout-specific ground colouring (village square, fields...).
func _ground_tint(c: Color, x: float, z: float, _h: float) -> Color:
	var dirt := Color(0.5, 0.27, 0.16)
	# Bare packed earth around the square and the farm.
	var square := 1.0 - smoothstep(9.0, 16.0, Vector2(x, z).length())
	c = c.lerp(dirt.lightened(0.08), square * 0.75)
	if x > -56 and x < -36 and z > -35 and z < -21:
		c = c.lerp(Color(0.42, 0.25, 0.15), 0.85)    # tilled bean field
	if abs(x - 40) < 15 and abs(z - 22) < 9:
		c = c.lerp(Color(0.42, 0.52, 0.24), 0.6)     # worn football pitch
	return c


func _build_terrain() -> void:
	var n := int(WORLD_HALF * 2.0 / MESH_STEP) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for j in n:
		for i in n:
			var x := -WORLD_HALF + i * MESH_STEP
			var z := -WORLD_HALF + j * MESH_STEP
			var h := height_at(x, z)
			var k := j * n + i
			verts[k] = Vector3(x, h, z)
			var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			normals[k] = Vector3(-dx, 1.0, -dz).normalized()
			colors[k] = _ground_color(x, z, h)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	# Collision: heightmap at 1 m spacing around the playable area.
	var cn := COL_HALF * 2 + 1
	var data := PackedFloat32Array()
	data.resize(cn * cn)
	for j in cn:
		for i in cn:
			data[j * cn + i] = height_at(i - COL_HALF, j - COL_HALF)
	var hm := HeightMapShape3D.new()
	hm.map_width = cn
	hm.map_depth = cn
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var cs := CollisionShape3D.new()
	cs.shape = hm
	body.add_child(cs)
	add_child(body)


func _build_boundary() -> void:
	# Invisible ring of walls; the surrounding hills make it feel natural.
	var count := 40
	for i in count:
		var a := TAU * i / count
		var p := Vector2(cos(a), sin(a)) * PLAY_RADIUS
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * PLAY_RADIUS / count + 2.0, 60, 2)
		cs.shape = box
		body.add_child(cs)
		body.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		body.rotation.y = -a + PI / 2
		add_child(body)


# =============================================================================
# Environment and lighting
# =============================================================================

func _build_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


## "morning" for exploration, "overcast" for uneasy days, "dusk" for evenings at home.
func set_time_of_day(mode: String) -> void:
	env.fog_density = 0.0016
	sun.shadow_enabled = true
	if mode == "night":
		# Moonlight: dark enough to hide in, light enough to play.
		sun.rotation_degrees = Vector3(-50, 40, 0)
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.62
		sky_mat.sky_top_color = Color(0.04, 0.06, 0.14)
		sky_mat.sky_horizon_color = Color(0.14, 0.17, 0.3)
		sky_mat.ground_horizon_color = Color(0.08, 0.1, 0.16)
		sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
		env.ambient_light_energy = 1.1
		env.fog_light_color = Color(0.1, 0.12, 0.2)
		env.fog_density = 0.005
	elif mode == "overcast":
		sun.rotation_degrees = Vector3(-55, -20, 0)
		sun.light_color = Color(0.86, 0.87, 0.9)
		sun.light_energy = 0.55
		sky_mat.sky_top_color = Color(0.42, 0.45, 0.5)
		sky_mat.sky_horizon_color = Color(0.62, 0.63, 0.64)
		sky_mat.ground_horizon_color = Color(0.45, 0.46, 0.45)
		sky_mat.ground_bottom_color = Color(0.18, 0.2, 0.17)
		env.ambient_light_energy = 0.5
		env.fog_light_color = Color(0.58, 0.6, 0.62)
		env.fog_density = 0.0035
	elif mode == "dusk":
		sun.rotation_degrees = Vector3(-9, 115, 0)
		sun.light_color = Color(1.0, 0.62, 0.38)
		sun.light_energy = 0.75
		sky_mat.sky_top_color = Color(0.17, 0.2, 0.36)
		sky_mat.sky_horizon_color = Color(0.93, 0.55, 0.36)
		sky_mat.ground_horizon_color = Color(0.45, 0.3, 0.25)
		sky_mat.ground_bottom_color = Color(0.1, 0.08, 0.08)
		env.ambient_light_energy = 0.4
		env.fog_light_color = Color(0.55, 0.38, 0.32)
	else:
		sun.rotation_degrees = Vector3(-42, -35, 0)
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 1.0
		sky_mat.sky_top_color = Color(0.26, 0.45, 0.74)
		sky_mat.sky_horizon_color = Color(0.66, 0.74, 0.8)
		sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.5)
		sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.18)
		env.ambient_light_energy = 0.42
		env.fog_light_color = Color(0.6, 0.68, 0.74)


# =============================================================================
# Village structures
# =============================================================================

func _build_village() -> void:
	# Emmanuel and Joseph's home.
	_house(Vector2(-34, 15), 0.0, Vector2(7, 5.5), Color(0.72, 0.5, 0.33), Color(0.45, 0.47, 0.5))
	_bench(Vector2(-33.4, 20.9), 0.0)
	_box(self, ground(spot_defs["radio"]) + Vector3(0, 0.5, 0), Vector3(0.36, 0.22, 0.16), Color(0.2, 0.17, 0.14))  # radio on a stool
	_cyl(self, ground(spot_defs["radio"]) + Vector3(0, 0.2, 0), 0.18, 0.4, Color(0.4, 0.28, 0.18))

	# Neighbours' homes.
	var homes := [
		[Vector2(-20, 18), 0.3], [Vector2(-22, -2), -0.2], [Vector2(-12, 26), 0.1],
		[Vector2(16, -16), 0.4], [Vector2(18, 22), -0.3], [Vector2(-8, -24), 0.2],
		[Vector2(-46, 2), 0.5], [Vector2(8, 38), 0.0], [Vector2(-18, 44), -0.4],
		[Vector2(26, 40), 0.2], [Vector2(-50, 30), -0.1], [Vector2(-4, -40), 0.3],
	]
	var walls := [Color(0.7, 0.47, 0.3), Color(0.78, 0.6, 0.42), Color(0.62, 0.4, 0.27), Color(0.85, 0.78, 0.65)]
	var roofs := [Color(0.45, 0.47, 0.5), Color(0.55, 0.27, 0.18), Color(0.38, 0.4, 0.42)]
	for i in homes.size():
		_house(homes[i][0], homes[i][1], Vector2(_rng.randf_range(5.5, 7.5), _rng.randf_range(4.5, 5.5)),
			walls[i % walls.size()], roofs[i % roofs.size()])

	# Mama Beata's shop, facing the road.
	_house(Vector2(13.5, 0.8), -PI / 2, Vector2(6, 5), Color(0.86, 0.8, 0.66), Color(0.55, 0.27, 0.18))
	var awn := _box(self, ground(Vector2(10.2, 0.8)) + Vector3(0, 2.3, 0), Vector3(1.8, 0.08, 5.4), Color(0.22, 0.42, 0.55))
	awn.rotation.z = 0.25
	_box(self, ground(Vector2(9.6, 0.8)) + Vector3(0, 0.5, 0), Vector3(0.7, 1.0, 3.2), Color(0.42, 0.3, 0.2), true)  # counter
	for k in 5:
		_box(self, ground(Vector2(9.6, -0.5 + k * 0.6)) + Vector3(0, 1.1, 0), Vector3(0.25, 0.2, 0.25),
			[Color(0.9, 0.8, 0.3), Color(0.8, 0.3, 0.2), Color(0.9, 0.9, 0.9), Color(0.3, 0.5, 0.8), Color(0.6, 0.4, 0.2)][k])

	# Market stalls around the square.
	var cloth := [Color(0.85, 0.55, 0.15), Color(0.3, 0.55, 0.35), Color(0.75, 0.25, 0.2), Color(0.25, 0.4, 0.65)]
	var stalls := [Vector2(-6, -5), Vector2(-7, 2.5), Vector2(6, -8), Vector2(-5, 12)]
	for i in stalls.size():
		_stall(stalls[i], cloth[i], i)

	# Water point with jerrycans.
	_cyl(self, ground(Vector2(-12, -4)) + Vector3(0, 0.5, 0), 0.6, 1.0, Color(0.55, 0.55, 0.52), true)
	for k in 3:
		_box(self, ground(Vector2(-10.9 + k * 0.45, -4.8)) + Vector3(0, 0.25, 0), Vector3(0.3, 0.5, 0.2), Color(0.9, 0.75, 0.15))

	# School: long classroom block.
	_house(Vector2(28, -2), -PI / 2, Vector2(18, 7), Color(0.88, 0.84, 0.72), Color(0.4, 0.5, 0.58))
	_box(self, ground(Vector2(22.0, 6.5)) + Vector3(0, 1.2, 0), Vector3(1.6, 1.0, 0.1), Color(0.15, 0.22, 0.17))  # notice board
	_cyl(self, ground(Vector2(21.4, 6.5)) + Vector3(0, 0.6, 0), 0.05, 1.2, Color(0.4, 0.3, 0.2))
	_cyl(self, ground(Vector2(22.6, 6.5)) + Vector3(0, 0.6, 0), 0.05, 1.2, Color(0.4, 0.3, 0.2))

	# Football pitch: two goals and a ball.
	for gx in [27.0, 53.0]:
		for gz in [-1.6, 1.6]:
			_cyl(self, ground(Vector2(gx, 22 + gz)) + Vector3(0, 1.0, 0), 0.06, 2.0, Color(0.92, 0.92, 0.9))
		var bar := _cyl(self, ground(Vector2(gx, 22)) + Vector3(0, 2.0, 0), 0.06, 3.2, Color(0.92, 0.92, 0.9))
		bar.rotation.x = PI / 2
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	ball.mesh = bm
	ball.material_override = _mat(Color(0.85, 0.85, 0.8))
	ball.position = ground(Vector2(41, 21)) + Vector3(0, 0.12, 0)
	ball.name = "Ball"
	add_child(ball)

	# Gasana's bean field: rows of low plants.
	for row in 7:
		var z := -33.0 + row * 1.7
		var x := -55.0
		while x < -39.0:
			_add_multi("bean", _bush_mesh(), Color(0.27, 0.48, 0.2),
				Transform3D(Basis().scaled(Vector3(0.35, 0.28, 0.35)), ground(Vector2(x, z)) + Vector3(0, 0.12, 0)))
			x += 0.9 + _rng.randf() * 0.2
	_keep_out.append([Vector2(-47, -28), 13.0])

	# Storehouse: round granary hut with a conical roof.
	var sp := ground(spot_defs["storehouse"])
	_cyl(self, sp + Vector3(0, 1.0, 0), 1.6, 2.4, Color(0.66, 0.46, 0.3), true)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 2.3
	roof.height = 1.6
	roof.radial_segments = 16
	var rmi := MeshInstance3D.new()
	rmi.mesh = roof
	rmi.material_override = _mat(Color(0.62, 0.52, 0.3))
	rmi.position = sp + Vector3(0, 2.9, 0)
	add_child(rmi)
	_box(self, sp + Vector3(0, 0.85, 1.58), Vector3(0.9, 1.7, 0.1), Color(0.18, 0.12, 0.08))  # doorway
	_keep_out.append([spot_defs["storehouse"], 5.0])

	# Bicycle by the road at the start.
	_bicycle(spot_defs["bicycle"], 0.3)

	# Aline's hill: one broad tree and a flat rock to sit on.
	_tree_broad(HILL + Vector2(1, -1), 1.3)
	_box(self, ground(spot_defs["aline_hill"]) + Vector3(0.6, 0.2, -0.6), Vector3(1.3, 0.45, 0.8), Color(0.4, 0.38, 0.35), true)
	_keep_out.append([HILL, 6.0])
	_keep_out.append([spot_defs["aline_hill"], 4.0])


func _house(c: Vector2, yaw: float, size: Vector2, wall: Color, roof: Color) -> void:
	var root := Node3D.new()
	var base := height_at(c.x, c.y)
	root.position = Vector3(c.x, base, c.y)
	root.rotation.y = yaw
	add_child(root)
	var wall_h := 2.7
	var ruined := damaged and _rng.randf() < 0.55
	if ruined:
		wall = wall.darkened(0.45)
	# Walls extend below ground so slopes never show a gap.
	_box(root, Vector3(0, wall_h / 2.0 - 0.5, 0), Vector3(size.x, wall_h + 1.0, size.y), wall, true)
	if ruined:
		# Roof gone; a few fallen sheets and beams lie beside the walls.
		for k in 3:
			var deb := _box(root, Vector3(_rng.randf_range(-size.x * 0.4, size.x * 0.4), 0.1, size.y / 2.0 + 1.2 + k * 0.4),
				Vector3(_rng.randf_range(0.8, 1.6), 0.08, 0.5), roof.darkened(0.4))
			deb.rotation.y = _rng.randf_range(-0.6, 0.6)
		_box(root, Vector3(0, 0.95, size.y / 2.0 + 0.02), Vector3(0.95, 1.9, 0.06), Color(0.05, 0.04, 0.03))
		_keep_out.append([c, max(size.x, size.y) * 0.75 + 2.0])
		return
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(size.x + 0.8, 1.4, size.y + 0.7)
	var rmi := MeshInstance3D.new()
	rmi.mesh = roof_mesh
	rmi.material_override = _mat(roof)
	rmi.position = Vector3(0, wall_h - 0.5 + 0.7 + 0.5, 0)
	root.add_child(rmi)
	# Door and windows on the +Z face.
	_box(root, Vector3(0, 0.95, size.y / 2.0 + 0.02), Vector3(0.95, 1.9, 0.06), Color(0.3, 0.2, 0.13))
	for wx in [-size.x * 0.3, size.x * 0.3]:
		_box(root, Vector3(wx, 1.5, size.y / 2.0 + 0.02), Vector3(0.8, 0.7, 0.06), Color(0.12, 0.1, 0.09))
	_keep_out.append([c, max(size.x, size.y) * 0.75 + 2.0])
	# A few banana plants beside most homes (banana groves are typical of the region).
	for k in 3:
		var a := _rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * (maxf(size.x, size.y) * 0.9 + _rng.randf_range(2.0, 4.0))
		if _path_distance(p) > 2.5:
			_banana(p)


func _stall(c: Vector2, cloth: Color, seed_i: int) -> void:
	var p := ground(c)
	for dx in [-1.0, 1.0]:
		for dz in [-0.7, 0.7]:
			_cyl(self, p + Vector3(dx, 1.0, dz), 0.05, 2.0, Color(0.42, 0.3, 0.2))
	if damaged:
		_box(self, p + Vector3(0, 0.8, 0), Vector3(2.0, 0.08, 1.2), Color(0.32, 0.25, 0.18), true)
		_keep_out.append([c, 2.6])
		return
	_box(self, p + Vector3(0, 2.05, 0), Vector3(2.4, 0.06, 1.8), cloth)
	_box(self, p + Vector3(0, 0.8, 0), Vector3(2.0, 0.08, 1.2), Color(0.5, 0.36, 0.22), true)
	var produce := [Color(0.95, 0.8, 0.2), Color(0.8, 0.2, 0.15), Color(0.35, 0.6, 0.25), Color(0.6, 0.4, 0.25)]
	for k in 6:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.22
		s.mesh = sm
		s.material_override = _mat(produce[(k + seed_i) % produce.size()])
		s.position = p + Vector3(-0.75 + (k % 3) * 0.75, 0.94, -0.3 + (k / 3) * 0.6)
		add_child(s)
	_keep_out.append([c, 2.6])


func _bench(c: Vector2, yaw: float) -> void:
	var b := _box(self, ground(c) + Vector3(0, 0.42, 0), Vector3(1.6, 0.08, 0.4), Color(0.45, 0.32, 0.2), true)
	b.rotation.y = yaw
	for dx in [-0.65, 0.65]:
		_box(self, ground(c) + Vector3(dx, 0.2, 0), Vector3(0.08, 0.4, 0.35), Color(0.4, 0.28, 0.18))


func _bicycle(c: Vector2, yaw: float) -> void:
	var root := Node3D.new()
	root.position = ground(c)
	root.rotation.y = yaw
	add_child(root)
	for wz in [-0.52, 0.52]:
		var w := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.3
		t.outer_radius = 0.34
		w.mesh = t
		w.material_override = _mat(Color(0.1, 0.1, 0.1))
		w.position = Vector3(0, 0.34, wz)
		w.rotation.z = PI / 2
		root.add_child(w)
	var frame := _box(root, Vector3(0, 0.55, 0), Vector3(0.05, 0.05, 1.0), Color(0.15, 0.25, 0.45))
	frame.rotation.x = 0.15
	_box(root, Vector3(0, 0.8, -0.22), Vector3(0.1, 0.05, 0.25), Color(0.1, 0.1, 0.1))  # saddle
	_box(root, Vector3(0, 0.95, 0.45), Vector3(0.55, 0.04, 0.04), Color(0.6, 0.6, 0.6))  # handlebar
	_keep_out.append([c, 2.0])


# =============================================================================
# Vegetation (MultiMesh-batched)
# =============================================================================

func _build_vegetation() -> void:
	# Banana groves in clusters.
	for cluster in _vegetation_clusters():
		for k in 9:
			var p: Vector2 = cluster + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-7, 7))
			if _free(p, 2.6):
				_banana(p)
	# Eucalyptus and broad trees scattered over the hills.
	var placed := 0
	var tries := 0
	while placed < 110 and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(-170, 170), _rng.randf_range(-170, 170))
		if p.length() < 14.0 or not _free(p, 3.5):
			continue
		if _rng.randf() < 0.65:
			_eucalyptus(p)
		else:
			_tree_broad(p, _rng.randf_range(0.8, 1.15))
		placed += 1
	# Low bushes for texture.
	for k in 260:
		var p := Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-120, 120))
		if _free(p, 1.8):
			var s := _rng.randf_range(0.4, 0.9)
			_add_multi("bush", _bush_mesh(), Color(0.24, 0.4, 0.18),
				Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s)), ground(p) + Vector3(0, s * 0.2, 0)))


func _vegetation_clusters() -> Array:
	return [Vector2(-28, 30), Vector2(-40, -6), Vector2(20, 30), Vector2(-14, -34), Vector2(30, -24), Vector2(-56, 14), Vector2(12, 54), Vector2(-24, 58)]


## A patch of tall grass (visual only; pair with a cover zone for stealth).
func tall_grass(c: Vector2, radius: float, density: int = 60) -> void:
	for k in density * 3:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var p := c + Vector2(cos(a), sin(a)) * r
		var h := _rng.randf_range(0.9, 1.5)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		var xf := Transform3D(basis, ground(p) + basis * Vector3(0, h / 2.0, 0)).scaled_local(Vector3(1, h, 1))
		var key := "tall_grass_a" if k % 3 != 0 else "tall_grass_b"
		_add_multi(key, _grass_mesh(), Color(0.45, 0.48, 0.24) if key == "tall_grass_a" else Color(0.55, 0.52, 0.28), xf)
	_keep_out.append([c, radius])


func _grass_mesh() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.09, 1.0, 0.03)
	return m


func _free(p: Vector2, clearance: float) -> bool:
	if _path_distance(p) < clearance:
		return false
	for k in _keep_out:
		if p.distance_to(k[0]) < k[1]:
			return false
	return true


func _banana(p: Vector2) -> void:
	var g := ground(p)
	var h := _rng.randf_range(1.8, 2.6)
	_add_multi("banana_trunk", _cyl_mesh(0.11, 0.15, 1.0), Color(0.36, 0.42, 0.22),
		Transform3D(Basis().scaled(Vector3(1, h, 1)), g + Vector3(0, h / 2.0, 0)))
	var leaf_count := 6
	var rot0 := _rng.randf() * TAU
	for i in leaf_count:
		var yaw := rot0 + TAU * i / leaf_count
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.55 - _rng.randf() * 0.4)
		var pos := g + Vector3(0, h, 0) + b * Vector3(0, 0, 0.75)
		_add_multi("banana_leaf", _leaf_mesh(), Color(0.3, 0.55, 0.22), Transform3D(b, pos))
	_keep_out.append([p, 1.2])


func _eucalyptus(p: Vector2) -> void:
	var g := ground(p)
	var h := _rng.randf_range(9.0, 15.0)
	_add_multi("euc_trunk", _cyl_mesh(0.12, 0.22, 1.0), Color(0.75, 0.7, 0.62),
		Transform3D(Basis().scaled(Vector3(1, h, 1)), g + Vector3(0, h / 2.0, 0)))
	for k in 3:
		var s := _rng.randf_range(1.2, 2.0)
		_add_multi("euc_crown", _sphere_mesh(), Color(0.33, 0.45, 0.32),
			Transform3D(Basis().scaled(Vector3(s, s * 1.6, s)), g + Vector3(_rng.randf_range(-0.6, 0.6), h - 1.0 - k * 1.6, _rng.randf_range(-0.6, 0.6))))
	_keep_out.append([p, 1.5])


func _tree_broad(p: Vector2, scale_f: float) -> void:
	var g := ground(p)
	var h := 3.2 * scale_f
	_add_multi("broad_trunk", _cyl_mesh(0.2, 0.35, 1.0), Color(0.35, 0.26, 0.18),
		Transform3D(Basis().scaled(Vector3(scale_f, h, scale_f)), g + Vector3(0, h / 2.0, 0)))
	for k in 4:
		var s := _rng.randf_range(2.0, 2.8) * scale_f
		var off := Vector3(_rng.randf_range(-1.4, 1.4), 0, _rng.randf_range(-1.4, 1.4)) * scale_f
		_add_multi("broad_crown", _sphere_mesh(), Color(0.24, 0.4, 0.2),
			Transform3D(Basis().scaled(Vector3(s, s * 0.55, s)), g + Vector3(0, h + 0.6 * scale_f, 0) + off))
	_keep_out.append([p, 2.5 * scale_f])


func _add_multi(key: String, mesh: Mesh, color: Color, xf: Transform3D) -> void:
	if not _multi.has(key):
		_multi[key] = {"mesh": mesh, "color": color, "xf": []}
	_multi[key]["xf"].append(xf)


## Builds any vegetation added after build() (e.g. tall grass placed by a chapter).
func flush() -> void:
	_flush_multimeshes()


func _flush_multimeshes() -> void:
	for key in _multi:
		var entry: Dictionary = _multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = entry["xf"].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, entry["xf"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + key
		mmi.multimesh = mm
		mmi.material_override = _mat(entry["color"])
		add_child(mmi)
	_multi.clear()


# =============================================================================
# Primitive helpers
# =============================================================================

func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		_mats[c] = m
	return _mats[c]


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, color: Color, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl_mesh(r, r, h)
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = h
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _cyl_mesh(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return m


func _sphere_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 10
	m.rings = 6
	return m


func _bush_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


func _leaf_mesh() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.42, 0.03, 1.5)
	return m
