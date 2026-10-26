## "Temple Ruins": a jungle clearing around a stepped temple with ramps on all four
## sides, broken columns, stone heads, kicker jumps and shallow pools.
class_name TempleRuins
extends ArenaBase

const MAP_NAME := "Temple Ruins"
const TEMPLE_HALF := 7.0
const TEMPLE_HEIGHT := 3.0

const C_GRASS_A := Color(0.27, 0.43, 0.19)
const C_GRASS_B := Color(0.24, 0.39, 0.17)
const C_DIRT := Color(0.52, 0.39, 0.25)
const C_STONE := Color(0.55, 0.51, 0.43)
const C_STONE_TOP := Color(0.60, 0.56, 0.46)
const C_STONE_DARK := Color(0.42, 0.39, 0.33)
const C_MOSS := Color(0.36, 0.50, 0.26)
const C_WATER := Color(0.25, 0.60, 0.70)
const C_TRUNK := Color(0.45, 0.32, 0.20)
const C_LEAF_A := Color(0.22, 0.52, 0.22)
const C_LEAF_B := Color(0.30, 0.62, 0.25)
const C_GOLD := Color(1.0, 0.78, 0.25)


func get_display_name() -> String:
	return MAP_NAME


func _build_layout() -> void:
	half_size = 45.0
	wall_height = 3.0
	ground_color = C_GRASS_A
	wall_color = C_STONE
	_build_floor(10.0, C_GRASS_A, C_GRASS_B)
	_build_perimeter(C_STONE, C_STONE_DARK, C_MOSS)
	_build_paths()
	_build_temple()
	_build_obstacles()
	_build_props()
	_build_backdrop()
	_build_markers()


func _build_paths() -> void:
	# Dirt cross leading to the temple ramps, and shallow pools in the corners.
	_box(Vector3(6.0, 0.02, 80.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.01, 0)), C_DIRT, false)
	_box(Vector3(80.0, 0.02, 6.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.01, 0)), C_DIRT, false)
	for p: Vector3 in [Vector3(30, 0, 36), Vector3(-30, 0, -36)]:
		_box(Vector3(10.0, 0.03, 6.0), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.015, 0)), C_WATER, false)
		_box(Vector3(10.8, 0.02, 6.8), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.01, 0)), C_STONE_DARK, false)


func _build_temple() -> void:
	_platform_with_ramps(Vector2.ZERO, Vector2(TEMPLE_HALF, TEMPLE_HALF), TEMPLE_HEIGHT, ["n", "s", "e", "w"],
		C_STONE, C_STONE_TOP, C_STONE_DARK, 11.0, 7.0)
	# Step lines on the temple sides and a gold idol ring on top (visual only).
	for i in 3:
		var y := 0.8 + i * 0.8
		_box(Vector3(TEMPLE_HALF * 2.0 + 0.3, 0.12, TEMPLE_HALF * 2.0 + 0.3), Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), C_STONE_DARK, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(1.2, 1.4, 1.2), Transform3D(Basis.IDENTITY, Vector3(sx * (TEMPLE_HALF - 0.8), TEMPLE_HEIGHT + 0.7, sz * (TEMPLE_HALF - 0.8))), C_STONE_DARK, true, C_MOSS)
	_cylinder(1.6, 1.6, 0.08, Vector3(0, TEMPLE_HEIGHT, 0), C_GOLD, 12, false)


func _build_obstacles() -> void:
	# Broken columns.
	var heights := [4.5, 2.2, 3.4, 1.6]
	var i := 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 18.0, 0, sz * 18.0)
			var h: float = heights[i]
			_cylinder(1.2, 1.35, h, p, C_STONE, 8, true)
			_cylinder(1.5, 1.5, 0.4, p, C_STONE_DARK, 8, false)
			_cylinder(1.0, 1.2, 0.3, p + Vector3(0, h, 0), C_MOSS, 8, false)
			i += 1
	# Fallen columns in two corners.
	_box(Vector3(7.0, 1.6, 1.6), Transform3D(Basis(Vector3.UP, 0.35), Vector3(-22, 0.8, 30)), C_STONE, true, C_MOSS)
	_box(Vector3(7.0, 1.6, 1.6), Transform3D(Basis(Vector3.UP, 0.35), Vector3(22, 0.8, -30)), C_STONE, true, C_MOSS)
	# Stone heads facing the temple.
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * 36.0, 0, 0)
		var b := Basis(Vector3.UP, -sx * PI * 0.5)
		_box(Vector3(4.0, 4.6, 3.6), Transform3D(b, p + Vector3(0, 2.3, 0)), C_STONE, true, C_MOSS)
		_box(Vector3(3.0, 0.5, 0.4), Transform3D(b, p + b * Vector3(0, 3.2, 1.85)), C_STONE_DARK, false)
		_box(Vector3(1.6, 0.4, 0.4), Transform3D(b, p + b * Vector3(0, 1.4, 1.85)), C_STONE_DARK, false)
		for ex: float in [-0.8, 0.8]:
			_box(Vector3(0.6, 0.4, 0.2), Transform3D(b, p + b * Vector3(ex, 2.6, 1.85)), C_GOLD, false)
	# Kicker jumps on the north / south paths, launching towards the walls' corners.
	_wedge(Vector3(5.0, 1.5, 5.5), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 30)), C_STONE_DARK)
	_wedge(Vector3(5.0, 1.5, 5.5), Transform3D(Basis.IDENTITY, Vector3(0, 0, -30)), C_STONE_DARK)


func _build_props() -> void:
	var trees: Array[Vector3] = [Vector3(41, 0, 41), Vector3(-41, 0, 41), Vector3(41, 0, -41), Vector3(-41, 0, -41),
		Vector3(41, 0, 20), Vector3(-41, 0, -20), Vector3(14, 0, 41), Vector3(-14, 0, -41), Vector3(41, 0, -22), Vector3(-41, 0, 22)]
	for p in trees:
		_cylinder(0.35, 0.5, 4.0, p, C_TRUNK, 6, false)
		for k in 5:
			var a := TAU * k / 5.0
			var leaf := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35)
			_box(Vector3(0.9, 0.12, 3.2), Transform3D(leaf, p + Vector3(0, 4.0, 0) + Vector3(cos(a), 0, sin(a)) * 0.2 + leaf * Vector3(0, 0, 1.4)), C_LEAF_A if k % 2 == 0 else C_LEAF_B, false)
		_collider_cylinder(0.6, 4.0, p + Vector3(0, 2.0, 0))
	# Bushes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 12:
		var a := TAU * k / 12.0 + 0.2
		var p := Vector3(cos(a) * 42.5, 0, sin(a) * 42.5)
		_cylinder(0.6, 1.3, 1.2, p, C_LEAF_B.darkened(rng.randf_range(0.0, 0.25)), 7, false)


func _build_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 30:
		var a := TAU * i / 30.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(58.0, 90.0)
		var h := rng.randf_range(10.0, 22.0)
		var base := Vector3(cos(a) * r, -0.5, sin(a) * r)
		_cylinder(0.0, rng.randf_range(5.0, 9.0), h, base, C_LEAF_A.darkened(rng.randf_range(0.1, 0.35)), 6, false)
	_quad_up(Vector3(-170, 0, -170), Vector3(170, 0, 170), -0.05, Color(0.28, 0.45, 0.22))


func _build_markers() -> void:
	_ring_spawns(8, 36.0)
	_add_crate_spawn(Vector3(0, TEMPLE_HEIGHT + 0.8, 0))
	for p: Vector3 in [Vector3(24, 0.8, 4), Vector3(-24, 0.8, -4), Vector3(4, 0.8, -24), Vector3(-4, 0.8, 24),
			Vector3(26, 0.8, 26), Vector3(-26, 0.8, 26), Vector3(26, 0.8, -26), Vector3(-26, 0.8, -26)]:
		_add_crate_spawn(p)


func _build_lighting() -> void:
	_add_environment({
		"sun_color": Color(1.0, 0.94, 0.80), "sun_energy": 1.15,
		"sun_rotation": Vector3(deg_to_rad(-50.0), deg_to_rad(-140.0), 0.0),
		"sky_top": Color(0.22, 0.50, 0.78), "sky_horizon": Color(0.78, 0.90, 0.80),
		"ground_bottom": Color(0.18, 0.25, 0.14), "ground_horizon": Color(0.6, 0.75, 0.55),
		"ambient": 0.38,
	})
