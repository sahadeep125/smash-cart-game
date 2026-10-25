## "Sunset Scrapyard": a walled 90 x 90 m battle arena built entirely in code.
## All static geometry is merged into a single vertex-coloured mesh (one draw call)
## and one StaticBody3D on layer 1 with a collision shape per solid piece.
class_name Arena
extends Node3D

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
const C_HAZARD_Y := Color(0.95, 0.75, 0.15)
const C_HAZARD_K := Color(0.15, 0.14, 0.15)
const C_RAMP := Color(0.42, 0.46, 0.52)
const C_WOOD_A := Color(0.70, 0.48, 0.25)
const C_WOOD_B := Color(0.56, 0.37, 0.19)
const C_TYRE := Color(0.13, 0.13, 0.15)
const C_CONE := Color(1.0, 0.45, 0.10)
const C_WHITE := Color(0.95, 0.94, 0.90)
const C_RED := Color(0.85, 0.20, 0.18)
const C_TRUNK := Color(0.42, 0.28, 0.18)
const C_LEAF_A := Color(0.36, 0.50, 0.26)
const C_LEAF_B := Color(0.46, 0.58, 0.28)
const C_MESA_A := Color(0.55, 0.32, 0.33)
const C_MESA_B := Color(0.45, 0.27, 0.32)

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _body: StaticBody3D
var _spawns: Array[Marker3D] = []
var _crate_spawns: Array[Marker3D] = []


func _ready() -> void:
	add_to_group("arena")
	_body = StaticBody3D.new()
	_body.name = "World"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)

	_build_ground()
	_build_walls()
	_build_platform()
	_build_ramps()
	_build_obstacles()
	_build_props()
	_build_backdrop()
	_commit_mesh()
	_build_markers()
	_build_lighting()


func get_spawn_points() -> Array[Marker3D]:
	return _spawns


func get_crate_spawn_points() -> Array[Marker3D]:
	return _crate_spawns


## Navigation hint for AI: returns where to drive next on the way from `from` to `to`.
## Only the raised platform needs routing: line up with the north / south ramp first.
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


# --- Geometry helpers ---------------------------------------------------------

## Adds a triangle; winding is fixed up so the face points along n (Godot: clockwise front).
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	_verts.append_array([a, b, c])
	_normals.append_array([n, n, n])
	_colors.append_array([col, col, col])


func _quad_oriented(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(outward) < 0.0:
		n = -n
	_tri(a, b, c, n, col)
	_tri(a, c, d, n, col)


func _quad_up(p0: Vector3, p1: Vector3, y: float, col: Color) -> void:
	var a := Vector3(p0.x, y, p0.z)
	var b := Vector3(p1.x, y, p0.z)
	var c := Vector3(p1.x, y, p1.z)
	var d := Vector3(p0.x, y, p1.z)
	_tri(a, b, c, Vector3.UP, col)
	_tri(a, c, d, Vector3.UP, col)


## Box centred on xform.origin. Bottom face is skipped (never visible).
func _box(size: Vector3, xform: Transform3D, col: Color, collide: bool, top_col: Variant = null) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		var lp := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(xform * lp)
	var center := xform.origin
	var top: Color = top_col if top_col is Color else col
	# +Y
	_quad_oriented(corners[2], corners[3], corners[7], corners[6], xform.basis.y, top)
	# +X, -X, +Z, -Z
	_quad_oriented(corners[1], corners[3], corners[7], corners[5], xform.basis.x, col)
	_quad_oriented(corners[0], corners[2], corners[6], corners[4], -xform.basis.x, col)
	_quad_oriented(corners[4], corners[5], corners[7], corners[6], xform.basis.z, col)
	_quad_oriented(corners[0], corners[1], corners[3], corners[2], -xform.basis.z, col)
	if center.y - h.y > 0.05:
		_quad_oriented(corners[0], corners[1], corners[5], corners[4], -xform.basis.y, col)
	if collide:
		_collider_box(size, xform)


## Vertical cylinder / cone standing on base_pos (flat-shaded).
func _cylinder(top_r: float, bottom_r: float, height: float, base_pos: Vector3, col: Color, segments: int, collide: bool) -> void:
	var top_y := base_pos.y + height
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base_pos + d0 * bottom_r
		var b1 := base_pos + d1 * bottom_r
		var t0 := Vector3(base_pos.x, top_y, base_pos.z) + d0 * top_r
		var t1 := Vector3(base_pos.x, top_y, base_pos.z) + d1 * top_r
		var mid := (d0 + d1).normalized()
		var slope := (bottom_r - top_r) / maxf(height, 0.001)
		var n := (mid + Vector3.UP * slope).normalized()
		if top_r > 0.001:
			_tri(b0, b1, t1, n, col)
			_tri(b0, t1, t0, n, col)
			_tri(Vector3(base_pos.x, top_y, base_pos.z), t0, t1, Vector3.UP, col)
		else:
			_tri(b0, b1, t0, n, col)
	if collide:
		_collider_cylinder(maxf(top_r, bottom_r), height, base_pos + Vector3(0, height * 0.5, 0))


## Ramp wedge: top surface size.x wide and size.z long, rising toward local -Z to size.y.
## The sides slope outward (drivable, ~35 deg) so karts never snag on a low vertical edge.
## xform.origin is the centre of the footprint on the ground.
func _wedge(size: Vector3, xform: Transform3D, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var spread := size.y * 1.5
	var pts: Array[Vector3] = [
		Vector3(-hx, 0, hz), Vector3(hx, 0, hz),                       # low edge
		Vector3(-hx - spread, 0, -hz), Vector3(hx + spread, 0, -hz),   # back bottom
		Vector3(-hx, size.y, -hz), Vector3(hx, size.y, -hz),           # top edge
	]
	var w: Array[Vector3] = []
	for p in pts:
		w.append(xform * p)
	var b := xform.basis
	var slope_n := (b * Vector3(0, size.z, size.y)).normalized()
	_quad_oriented(w[0], w[1], w[5], w[4], slope_n, col)
	_quad_oriented(w[2], w[3], w[5], w[4], b * Vector3.FORWARD, col.darkened(0.2))
	var rn := (w[3] - w[1]).cross(w[5] - w[1]).normalized()
	if rn.dot(b * Vector3.RIGHT) < 0.0:
		rn = -rn
	_tri(w[1], w[3], w[5], rn, col.darkened(0.1))
	var ln := (w[2] - w[0]).cross(w[4] - w[0]).normalized()
	if ln.dot(b * Vector3.LEFT) < 0.0:
		ln = -ln
	_tri(w[0], w[2], w[4], ln, col.darkened(0.1))
	# Stripes on the slope.
	for i in 3:
		var t := (i + 0.5) / 3.0
		var z := lerpf(hz, -hz, t)
		var y := size.y * t + 0.02
		var dy := size.y / size.z * 0.3
		var la := xform * Vector3(-hx * 0.7, y - dy, z + 0.3)
		var lb := xform * Vector3(hx * 0.7, y - dy, z + 0.3)
		var lc := xform * Vector3(hx * 0.7, y + dy, z - 0.3)
		var ld := xform * Vector3(-hx * 0.7, y + dy, z - 0.3)
		_quad_oriented(la, lb, lc, ld, slope_n, C_WHITE)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(pts)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	_body.add_child(cs)


func _collider_box(size: Vector3, xform: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	_body.add_child(cs)


func _collider_cylinder(radius: float, height: float, center: Vector3) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	_body.add_child(cs)


func _commit_mesh() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.name = "ArenaMesh"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
