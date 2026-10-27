## "Frostbite Harbor": a snowy harbour with a frozen pond in the middle (slippery),
## two raised docks with ramps, ice blocks, frozen-in boats and a lighthouse.
class_name FrostHarbor
extends ArenaBase

const MAP_NAME := "Frostbite Harbor"
const DOCK_HEIGHT := 2.0

const C_SNOW_A := Color(0.58, 0.65, 0.77)
const C_SNOW_B := Color(0.54, 0.61, 0.74)
const C_ICE := Color(0.38, 0.64, 0.86)
const C_ICE_DARK := Color(0.24, 0.46, 0.70)
const C_STONE_A := Color(0.46, 0.52, 0.62)
const C_STONE_B := Color(0.40, 0.45, 0.55)
const C_TRIM := Color(0.20, 0.24, 0.32)
const C_DOCK := Color(0.50, 0.36, 0.24)
const C_DOCK_TOP := Color(0.62, 0.46, 0.30)
const C_RAMP := Color(0.44, 0.50, 0.58)
const C_PINE := Color(0.20, 0.40, 0.34)
const C_TRUNK := Color(0.36, 0.24, 0.16)
const C_RED := Color(0.82, 0.20, 0.20)


func get_display_name() -> String:
	return MAP_NAME


func _build_layout() -> void:
	half_size = 45.0
	wall_height = 3.0
	ground_color = C_SNOW_A
	wall_color = C_STONE_A
	_build_floor(10.0, C_SNOW_A, C_SNOW_B)
	_build_perimeter(C_STONE_A, C_STONE_B, C_TRIM)
	_build_pond()
	_build_docks()
	_build_obstacles()
	_build_props()
	_build_backdrop()
	_build_markers()


func _build_pond() -> void:
	_ice_patch(Vector2.ZERO, Vector2(11, 14), C_ICE)
	# Cracks and a darker rim so the slippery area reads clearly.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		var p := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-12, 12))
		var a := rng.randf_range(0, PI)
		_box(Vector3(rng.randf_range(2.0, 4.5), 0.02, 0.12), Transform3D(Basis(Vector3.UP, a), p + Vector3(0, 0.02, 0)), C_ICE_DARK, false)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.4, 0.04, 28.4), Transform3D(Basis.IDENTITY, Vector3(sx * 11.2, 0.02, 0)), C_ICE_DARK, false)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(22.8, 0.04, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, 0.02, sz * 14.2)), C_ICE_DARK, false)


func _build_docks() -> void:
	_platform_with_ramps(Vector2(31, 0), Vector2(6, 9), DOCK_HEIGHT, ["w", "n"], C_DOCK, C_DOCK_TOP, C_RAMP, 10.0, 7.0)
	_platform_with_ramps(Vector2(-31, 0), Vector2(6, 9), DOCK_HEIGHT, ["e", "s"], C_DOCK, C_DOCK_TOP, C_RAMP, 10.0, 7.0)
	# Plank lines and bollards on the docks.
	for sx: float in [-1.0, 1.0]:
		for i in 6:
			var x := sx * (26.0 + i * 2.0)
			_box(Vector3(0.1, 0.02, 18.0), Transform3D(Basis.IDENTITY, Vector3(x, DOCK_HEIGHT + 0.01, 0)), C_DOCK, false)
		for z: float in [-7.5, 7.5]:
			_cylinder(0.3, 0.35, 0.8, Vector3(sx * 36.3, DOCK_HEIGHT, z), C_TRIM, 6, true)


func _build_obstacles() -> void:
	# Ice blocks.
	var blocks: Array[Vector3] = [Vector3(0, 0, 22), Vector3(0, 0, -22), Vector3(-14, 0, 26),
		Vector3(14, 0, -26), Vector3(15, 0, 20), Vector3(-15, 0, -20)]
	for i in blocks.size():
		var p := blocks[i]
		var yaw := 0.4 * i
		_box(Vector3(2.6, 2.2, 2.6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 1.1, 0)), C_ICE, true, Color(0.85, 0.95, 1.0))
		_box(Vector3(1.4, 1.2, 1.4), Transform3D(Basis(Vector3.UP, yaw + 0.6), p + Vector3(0.4, 2.8, 0.2)), C_ICE_DARK, false)
	# Frozen-in fishing boats.
	_boat(Vector3(-26, 0, 30), 0.5, C_RED)
	_boat(Vector3(26, 0, -30), PI + 0.5, Color(0.20, 0.45, 0.70))
	# Lighthouse in the north-east corner.
	var lh := Vector3(39, 0, 39)
	for i in 5:
		var c := C_RED if i % 2 == 0 else C_WHITE
		_cylinder(1.9 - i * 0.12, 2.0 - i * 0.12, 2.0, lh + Vector3(0, i * 2.0, 0), c, 10, i == 0)
	_cylinder(1.3, 1.3, 1.4, lh + Vector3(0, 10.0, 0), C_TRIM, 10, false)
	var was := _emit
	_emit = true
	_cylinder(1.0, 1.0, 1.0, lh + Vector3(0, 10.2, 0), Color(1.0, 0.92, 0.55), 10, false)
	_emit = was
	_cylinder(0.0, 1.6, 1.2, lh + Vector3(0, 11.4, 0), C_RED, 10, false)
	# Crate stacks.
	for s: float in [-1.0, 1.0]:
		var base := Vector3(-36, 0, -38) if s < 0 else Vector3(36, 0, 22)
		_box(Vector3(2, 2, 2), Transform3D(Basis(Vector3.UP, 0.1), base + Vector3(0, 1, 0)), C_DOCK_TOP, true)
		_box(Vector3(2, 2, 2), Transform3D(Basis(Vector3.UP, -0.2), base + Vector3(2.2, 1, 0.4)), C_DOCK, true)


func _build_props() -> void:
	var trees: Array[Vector3] = [Vector3(41, 0, -10), Vector3(-41, 0, 10), Vector3(10, 0, 41),
		Vector3(-10, 0, -41), Vector3(-30, 0, 41), Vector3(30, 0, -41), Vector3(-41, 0, -40)]
	for p in trees:
		_cylinder(0.3, 0.4, 1.2, p, C_TRUNK, 6, false)
		_cylinder(0.0, 2.0, 2.6, p + Vector3(0, 1.0, 0), C_PINE, 7, false)
		_cylinder(0.0, 1.5, 2.2, p + Vector3(0, 2.6, 0), C_PINE.lightened(0.1), 7, false)
		_cylinder(0.0, 0.8, 1.0, p + Vector3(0, 4.0, 0), C_SNOW_A, 7, false)
		_collider_cylinder(0.9, 4.0, p + Vector3(0, 2.0, 0))
	# Snowmen (decor, solid).
	for p: Vector3 in [Vector3(20, 0, 40), Vector3(-20, 0, -40)]:
		_cylinder(0.9, 1.0, 1.4, p, C_WHITE, 8, true)
		_cylinder(0.6, 0.7, 1.0, p + Vector3(0, 1.4, 0), C_WHITE, 8, false)
		_cylinder(0.0, 0.12, 0.5, p + Vector3(0, 1.9, 0.6), Color(1.0, 0.5, 0.1), 5, false)


func _build_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 16:
		var a := TAU * i / 16.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(90.0, 125.0)
		var w := rng.randf_range(14.0, 26.0)
		var h := rng.randf_range(16.0, 34.0)
		var base := Vector3(cos(a) * r, -0.5, sin(a) * r)
		_cylinder(0.0, w, h, base, C_STONE_B, 6, false)
		_cylinder(0.0, w * 0.35, h * 0.35, base + Vector3(0, h * 0.65, 0), C_SNOW_A, 6, false)
	_quad_up(Vector3(-170, 0, -170), Vector3(170, 0, 170), -0.05, Color(0.80, 0.85, 0.92))


func _build_markers() -> void:
	for p: Vector3 in [Vector3(0, 0.15, 38), Vector3(0, 0.15, -38), Vector3(24, 0.15, 36), Vector3(-24, 0.15, -36),
			Vector3(40, 0.15, -28), Vector3(-40, 0.15, 28), Vector3(-36, 0.15, -30), Vector3(36, 0.15, 30)]:
		_add_spawn(p)
	for p: Vector3 in [Vector3(0, 0.8, 0), Vector3(31, DOCK_HEIGHT + 0.8, 0), Vector3(-31, DOCK_HEIGHT + 0.8, 0),
			Vector3(0, 0.8, 30), Vector3(0, 0.8, -30), Vector3(20, 0.8, 10), Vector3(-20, 0.8, -10),
			Vector3(34, 0.8, -36), Vector3(-34, 0.8, 36), Vector3(-22, 0.8, 16), Vector3(22, 0.8, -16)]:
		_add_crate_spawn(p)


func _build_lighting() -> void:
	_add_environment({
		"sun_color": Color(0.95, 0.97, 1.0), "sun_energy": 0.85,
		"sun_rotation": Vector3(deg_to_rad(-40.0), deg_to_rad(-60.0), 0.0),
		"sky_top": Color(0.28, 0.46, 0.78), "sky_horizon": Color(0.74, 0.84, 0.95),
		"ground_bottom": Color(0.6, 0.66, 0.75), "ground_horizon": Color(0.85, 0.9, 0.98),
		"ambient": 0.32,
	})


func _boat(base: Vector3, yaw: float, c: Color) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, 0.1)
	_box(Vector3(3.0, 1.4, 6.5), Transform3D(b, base + Vector3(0, 0.6, 0)), c, true, C_DOCK_TOP)
	_box(Vector3(2.0, 1.4, 2.0), Transform3D(b, base + b * Vector3(0, 1.9, -1.0)), C_WHITE, false)
	_box(Vector3(2.1, 0.4, 2.1), Transform3D(b, base + b * Vector3(0, 2.7, -1.0)), C_TRIM, false)
	_cylinder(0.08, 0.08, 3.0, base + b * Vector3(0, 1.3, 1.5), C_TRIM, 4, false)
