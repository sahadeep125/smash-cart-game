## "Sunset Scrapyard": a walled 90 x 90 m battle arena built entirely in code
## (geometry helpers in ArenaBase).
class_name Arena
extends ArenaBase

const ARENA_NAME := "Sunset Scrapyard"
const HALF_SIZE := 45.0
const PLATFORM_HALF := 8.0
const PLATFORM_HEIGHT := 2.4
const WALL_HEIGHT := 3.2
const RAMP_WIDTH := 8.0

# Palette (sRGB).
const C_GROUND_A := Color(0.80, 0.62, 0.44)
const C_GROUND_B := Color(0.74, 0.56, 0.40)
const C_OIL := Color(0.30, 0.25, 0.24)
const C_WALL_A := Color(0.62, 0.32, 0.20)
const C_WALL_B := Color(0.52, 0.27, 0.19)
const C_TRIM := Color(0.20, 0.18, 0.20)
const C_CONCRETE := Color(0.66, 0.64, 0.62)
const C_CONCRETE_TOP := Color(0.55, 0.58, 0.62)
const C_RAMP := Color(0.42, 0.46, 0.52)
const C_WOOD_A := Color(0.70, 0.48, 0.25)
const C_WOOD_B := Color(0.56, 0.37, 0.19)
const C_CONE := Color(1.0, 0.45, 0.10)
const C_RED := Color(0.85, 0.20, 0.18)
const C_TRUNK := Color(0.42, 0.28, 0.18)
const C_LEAF_A := Color(0.36, 0.50, 0.26)
const C_LEAF_B := Color(0.46, 0.58, 0.28)
const C_MESA_A := Color(0.55, 0.32, 0.33)
const C_MESA_B := Color(0.45, 0.27, 0.32)


func get_display_name() -> String:
	return ARENA_NAME


func _build_layout() -> void:
	half_size = HALF_SIZE
	wall_height = WALL_HEIGHT
	ground_color = C_GROUND_A
	wall_color = C_WALL_A
	_build_ground()
	_build_walls()
	_build_platform()
	_build_ramps()
	_build_obstacles()
	_build_props()
	_build_backdrop()
	_build_markers()


## Hand-tuned routing for this map's single platform (north / south ramps).
func get_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var target_on_top := to.y > PLATFORM_HEIGHT - 0.6 and absf(to.x) < PLATFORM_HALF and absf(to.z) < PLATFORM_HALF
	if not target_on_top or from.y > PLATFORM_HEIGHT - 0.6:
		return to
	var side := 1.0 if from.z >= 0.0 else -1.0
	if absf(from.z) < PLATFORM_HALF + 2.0:
		# Beside the platform: pick the ramp that is cheaper to reach.
		side = 1.0 if from.z + to.z >= 0.0 else -1.0
	var entry := Vector3(0, 0, side * (PLATFORM_HALF + 17.0))
	var dz := absf(from.z)
	var ramp_bottom := PLATFORM_HALF + 10.0
	# Funnel in front of the ramp: narrow at the ramp, wider further out.
	var funnel := RAMP_WIDTH * 0.5 - 1.0 + maxf(dz - ramp_bottom, 0.0) * 0.8
	var in_funnel := signf(from.z) == side and dz > PLATFORM_HALF - 1.0 and dz < ramp_bottom + 9.0 and absf(from.x) < funnel
	if in_funnel:
		# Carrot on the ramp's centre line, a few metres ahead.
		return Vector3(0, PLATFORM_HEIGHT, maxf(dz - 7.0, 0.0) * side)
	return entry


# --- Layout -------------------------------------------------------------------

func _build_ground() -> void:
	var tile := 10.0
	var n := int(HALF_SIZE * 2.0 / tile)
	for ix in n:
		for iz in n:
			var c := C_GROUND_A if (ix + iz) % 2 == 0 else C_GROUND_B
			var x0 := -HALF_SIZE + ix * tile
			var z0 := -HALF_SIZE + iz * tile
			_quad_up(Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0 + tile), 0.0, c)
	# Floor collider (thick, so fast karts never tunnel through).
	_collider_box(Vector3(HALF_SIZE * 2.0 + 10.0, 2.0, HALF_SIZE * 2.0 + 10.0), Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))
	# Oil stains and painted ring around the platform.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var p := Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40))
		if absf(p.x) < 12.0 and absf(p.z) < 20.0:
			continue
		var s := rng.randf_range(1.2, 3.0)
		_quad_up(p - Vector3(s, 0, s * 0.7), p + Vector3(s, 0, s * 0.7), 0.012, C_OIL)
	var ring_r := 11.0
	for i in 24:
		var a := TAU * i / 24.0
		if i % 2 == 0:
			var p := Vector3(cos(a), 0, sin(a)) * ring_r
			_box(Vector3(1.6, 0.02, 0.5), Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, 0.01, 0)), C_WHITE, false)


func _build_walls() -> void:
	var t := 1.5
	var seg := 6.0
	var count := int(HALF_SIZE * 2.0 / seg)
	for side in 4:
		var basis := Basis(Vector3.UP, PI * 0.5 * side)
		for i in count + 1:
			var along := -HALF_SIZE + i * seg
			var c := C_WALL_A if i % 2 == 0 else C_WALL_B
			var local := Vector3(along, WALL_HEIGHT * 0.5, -HALF_SIZE - t * 0.5)
			_box(Vector3(seg, WALL_HEIGHT, t), Transform3D(basis, basis * local), c, false)
		_box(Vector3(HALF_SIZE * 2.0 + t * 2.0, 0.3, t + 0.3), Transform3D(basis, basis * Vector3(0, WALL_HEIGHT + 0.15, -HALF_SIZE - t * 0.5)), C_TRIM, false)
		# Tall invisible collider so jumping karts can't leave the arena.
		_collider_box(Vector3(HALF_SIZE * 2.0 + t * 4.0, 12.0, t), Transform3D(basis, basis * Vector3(0, 6.0, -HALF_SIZE - t * 0.5)))


func _build_platform() -> void:
	var size := Vector3(PLATFORM_HALF * 2.0, PLATFORM_HEIGHT, PLATFORM_HALF * 2.0)
	_box(size, Transform3D(Basis.IDENTITY, Vector3(0, PLATFORM_HEIGHT * 0.5, 0)), C_CONCRETE, true, C_CONCRETE_TOP)
	# Hazard trim along the top edges of the east/west drops.
	for sx: float in [-1.0, 1.0]:
		for i in 8:
			var z := -PLATFORM_HALF + 1.0 + i * 2.0
			var c := C_HAZARD_Y if i % 2 == 0 else C_HAZARD_K
			_box(Vector3(0.5, 0.03, 2.0), Transform3D(Basis.IDENTITY, Vector3(sx * (PLATFORM_HALF - 0.25), PLATFORM_HEIGHT + 0.015, z)), c, false)
	# Corner bollards.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cylinder(0.35, 0.35, 1.0, Vector3(sx * (PLATFORM_HALF - 0.6), PLATFORM_HEIGHT, sz * (PLATFORM_HALF - 0.6)), C_HAZARD_Y, 6, true)


func _build_ramps() -> void:
	# Ramps up to the centre platform (north and south).
	var ramp_len := 10.0
	var ramp_w := RAMP_WIDTH
	_wedge(Vector3(ramp_w, PLATFORM_HEIGHT, ramp_len), Transform3D(Basis.IDENTITY, Vector3(0, 0, PLATFORM_HALF + ramp_len * 0.5)), C_RAMP)
	_wedge(Vector3(ramp_w, PLATFORM_HEIGHT, ramp_len), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -PLATFORM_HALF - ramp_len * 0.5)), C_RAMP)
	for sz: float in [-1.0, 1.0]:
		for i in 4:
			var z := sz * (PLATFORM_HALF + ramp_len + 0.4)
			var x := -3.0 + i * 2.0
			var c := C_HAZARD_Y if i % 2 == 0 else C_HAZARD_K
			_box(Vector3(2.0, 0.02, 0.6), Transform3D(Basis.IDENTITY, Vector3(x, 0.01, z)), c, false)
	# Free-standing kicker ramps for jumps (east lane drives north, west lane south).
	_wedge(Vector3(5.0, 1.5, 5.5), Transform3D(Basis.IDENTITY, Vector3(26, 0, 4)), C_HAZARD_Y)
	_wedge(Vector3(5.0, 1.5, 5.5), Transform3D(Basis(Vector3.UP, PI), Vector3(-26, 0, -4)), C_HAZARD_Y)


func _build_obstacles() -> void:
	# Concrete pillars.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 18.0, 0, sz * 18.0)
			_cylinder(1.2, 1.2, 5.0, p, C_CONCRETE, 8, true)
			_cylinder(1.25, 1.25, 0.5, p + Vector3(0, 3.6, 0), C_HAZARD_K, 8, false)
	# Crate stacks in two corners.
	for s: float in [-1.0, 1.0]:
		var base := Vector3(30, 0, 30) * s
		_crate(base + Vector3(0, 1, 0), 0.0, C_WOOD_A)
		_crate(base + Vector3(2.2 * s, 1, 0), 0.2, C_WOOD_B)
		_crate(base + Vector3(0, 1, 2.2 * s), -0.15, C_WOOD_B)
		_crate(base + Vector3(1.1 * s, 3, 1.1 * s), 0.4, C_WOOD_A)
	# Shipping containers in the other two corners.
	_container(Vector3(-30, 0, 30), deg_to_rad(30.0), Color(0.70, 0.25, 0.20))
	_container(Vector3(30, 0, -30), deg_to_rad(30.0), Color(0.22, 0.40, 0.62))
	# Low red/white barriers.
	for sz: float in [-1.0, 1.0]:
		for i in 5:
			var c := C_RED if i % 2 == 0 else C_WHITE
			_box(Vector3(2.0, 1.0, 0.8), Transform3D(Basis.IDENTITY, Vector3(-4.0 + i * 2.0, 0.5, sz * 31.0)), c, false)
		_collider_box(Vector3(10.0, 1.0, 0.8), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, sz * 31.0)))
	# Wrecked car bodies against the north/south walls.
	_wreck(Vector3(0, 0, 41.5), 0.15, Color(0.36, 0.48, 0.42))
	_wreck(Vector3(0, 0, -41.5), PI - 0.2, Color(0.62, 0.52, 0.30))


func _build_props() -> void:
	# Tyre stacks.
	for p: Vector3 in [Vector3(10, 0, 24), Vector3(-10, 0, -24), Vector3(20, 0, -28), Vector3(-20, 0, 28)]:
		for i in 3:
			var off := Vector3(0.08 * (i % 2), 0.4 * i, -0.06 * (i % 2))
			_cylinder(0.6, 0.6, 0.38, p + off, C_TYRE, 8, false)
			_cylinder(0.3, 0.3, 0.39, p + off, C_HAZARD_K, 6, false)
		_collider_cylinder(0.65, 1.2, p + Vector3(0, 0.6, 0))
	# Traffic cones around the wrecks and in the quiet corners (out of the driving lines).
	var cones: Array[Vector3] = [
		Vector3(4.0, 0, 39.0), Vector3(-4.5, 0, 39.5), Vector3(4.5, 0, -39.5), Vector3(-4.0, 0, -39.0),
		Vector3(37.0, 0, -37.0), Vector3(-37.0, 0, 37.0), Vector3(37.5, 0, 36.0), Vector3(-36.0, 0, -37.5),
	]
	for p in cones:
		_cylinder(0.32, 0.32, 0.06, p, C_HAZARD_K, 6, false)
		_cylinder(0.04, 0.26, 0.7, p + Vector3(0, 0.06, 0), C_CONE, 6, false)
		_cylinder(0.15, 0.19, 0.12, p + Vector3(0, 0.35, 0), C_WHITE, 6, false)
		_collider_cylinder(0.25, 0.8, p + Vector3(0, 0.4, 0))
	# Low-poly pines along the walls.
	var trees: Array[Vector3] = [
		Vector3(40, 0, 40), Vector3(-40, 0, 40), Vector3(40, 0, -40), Vector3(-40, 0, -40),
		Vector3(41, 0, 20), Vector3(-41, 0, -20), Vector3(20, 0, 41.5), Vector3(-20, 0, -41.5),
	]
	for p in trees:
		_cylinder(0.35, 0.45, 1.6, p, C_TRUNK, 6, false)
		_cylinder(0.0, 2.1, 2.6, p + Vector3(0, 1.3, 0), C_LEAF_A, 7, false)
		_cylinder(0.0, 1.5, 2.2, p + Vector3(0, 2.9, 0), C_LEAF_B, 7, false)
		_collider_cylinder(1.0, 4.0, p + Vector3(0, 2.0, 0))


func _build_backdrop() -> void:
	# Distant mesas outside the walls (visual only).
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(85.0, 120.0)
		var w := rng.randf_range(10.0, 22.0)
		var h := rng.randf_range(8.0, 22.0)
		var c := C_MESA_A if i % 2 == 0 else C_MESA_B
		_cylinder(w * 0.65, w, h, Vector3(cos(a) * r, -0.5, sin(a) * r), c, 7, false)
	# Ground beyond the walls.
	_quad_up(Vector3(-160, 0, -160), Vector3(160, 0, 160), -0.05, Color(0.62, 0.42, 0.32))


func _build_markers() -> void:
	var spawn_root := Node3D.new()
	spawn_root.name = "SpawnPoints"
	add_child(spawn_root)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var pos := Vector3(cos(a) * 36.0, 0.15, sin(a) * 36.0)
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.transform = Transform3D(Basis.looking_at(Vector3(-pos.x, 0, -pos.z).normalized(), Vector3.UP), pos)
		m.add_to_group("spawn_points")
		spawn_root.add_child(m)
		_spawns.append(m)

	var crate_root := Node3D.new()
	crate_root.name = "CrateSpawns"
	add_child(crate_root)
	var crate_points: Array[Vector3] = [
		Vector3(0, PLATFORM_HEIGHT + 0.8, 0),
		Vector3(13, 0.8, 0), Vector3(-13, 0.8, 0),
		Vector3(0, 0.8, 23), Vector3(0, 0.8, -23),
		Vector3(25, 0.8, 25), Vector3(-25, 0.8, 25), Vector3(25, 0.8, -25), Vector3(-25, 0.8, -25),
		Vector3(38, 0.8, 0), Vector3(-38, 0.8, 0),
	]
	for i in crate_points.size():
		var m := Marker3D.new()
		m.name = "Crate%d" % i
		m.position = crate_points[i]
		m.add_to_group("crate_spawns")
		crate_root.add_child(m)
		_crate_spawns.append(m)


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.84, 0.66)
	sun.light_energy = 1.15
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-125.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.08
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.26, 0.27, 0.55)
	sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.38)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.28, 0.18, 0.16)
	sky_mat.ground_horizon_color = Color(0.95, 0.58, 0.38)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# --- Composite props ----------------------------------------------------------

func _crate(center: Vector3, yaw: float, c: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	_box(Vector3(2, 2, 2), Transform3D(b, center), c, true)
	# Darker frame strips on the sides.
	for sy: float in [-0.85, 0.85]:
		_box(Vector3(2.04, 0.25, 2.04), Transform3D(b, center + Vector3(0, sy, 0)), C_WOOD_B.darkened(0.2), false)


func _container(base: Vector3, yaw: float, c: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var size := Vector3(2.5, 2.6, 6.0)
	_box(size, Transform3D(b, base + Vector3(0, size.y * 0.5, 0)), c, true, c.lightened(0.1))
	for i in 5:
		var z := -2.4 + i * 1.2
		_box(Vector3(2.56, 2.3, 0.12), Transform3D(b, base + b * Vector3(0, 1.3, z)), c.darkened(0.25), false)


func _wreck(base: Vector3, yaw: float, c: Color) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, 0.08)
	_box(Vector3(4.2, 1.0, 2.0), Transform3D(b, base + Vector3(0, 0.6, 0)), c, true)
	_box(Vector3(2.2, 0.8, 1.8), Transform3D(b, base + b * Vector3(-0.3, 1.5, 0)), c.darkened(0.15), true)
	_box(Vector3(2.3, 0.5, 1.6), Transform3D(b, base + b * Vector3(-0.3, 1.5, 0)), Color(0.2, 0.25, 0.3), false)
	for wx: float in [-1.4, 1.4]:
		_cylinder(0.45, 0.45, 0.3, base + b * Vector3(wx, 0.0, 1.05), C_TYRE, 8, false)
