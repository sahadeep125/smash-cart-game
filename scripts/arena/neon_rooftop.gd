## "Neon Rooftops": a night-time city roof with four raised corner decks, glowing
## grid lines, boost pads on the central cross lanes and billboards along the walls.
class_name NeonRooftop
extends ArenaBase

const MAP_NAME := "Neon Rooftops"
const DECK_HEIGHT := 2.2

const C_FLOOR_A := Color(0.17, 0.16, 0.24)
const C_FLOOR_B := Color(0.20, 0.19, 0.28)
const C_WALL_A := Color(0.24, 0.18, 0.34)
const C_WALL_B := Color(0.20, 0.15, 0.30)
const C_DECK := Color(0.30, 0.30, 0.38)
const C_DECK_TOP := Color(0.36, 0.36, 0.46)
const C_RAMP := Color(0.34, 0.34, 0.44)
const C_METAL := Color(0.55, 0.58, 0.64)
const C_DARK := Color(0.10, 0.10, 0.14)
const N_CYAN := Color(0.10, 0.95, 1.0)
const N_PINK := Color(1.0, 0.25, 0.75)
const N_YELLOW := Color(1.0, 0.85, 0.2)
const N_GREEN := Color(0.4, 1.0, 0.45)


func get_display_name() -> String:
	return MAP_NAME


func _build_layout() -> void:
	half_size = 45.0
	wall_height = 3.4
	ground_color = C_FLOOR_B
	wall_color = C_WALL_A
	_build_floor(10.0, C_FLOOR_A, C_FLOOR_B)
	_build_perimeter(C_WALL_A, C_WALL_B, C_DARK)
	_build_glow_lines()
	_build_decks()
	_build_centre()
	_build_obstacles()
	_build_backdrop()
	_build_markers()


func _build_glow_lines() -> void:
	_emit = true
	# Grid lines every 10 m and a glowing strip along the top of the walls.
	for i in 9:
		var v := -40.0 + i * 10.0
		_box(Vector3(0.12, 0.01, 90.0), Transform3D(Basis.IDENTITY, Vector3(v, 0.012, 0)), N_CYAN.darkened(0.55), false)
		_box(Vector3(90.0, 0.01, 0.12), Transform3D(Basis.IDENTITY, Vector3(0, 0.012, v)), N_CYAN.darkened(0.55), false)
	for side in 4:
		var basis := Basis(Vector3.UP, PI * 0.5 * side)
		_box(Vector3(half_size * 2.0, 0.12, 0.08), Transform3D(basis, basis * Vector3(0, wall_height - 0.4, -half_size + 0.05)), N_PINK, false)
	_emit = false


func _build_decks() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var ramps: Array = ["s" if sz > 0 else "n", "w" if sx > 0 else "e"]
			_platform_with_ramps(Vector2(sx * 27, sz * 27), Vector2(8, 8), DECK_HEIGHT, ramps, C_DECK, C_DECK_TOP, C_RAMP, 10.0, 8.0)
			# Glowing edge trim and a rooftop AC unit on each deck.
			var c := Vector3(sx * 27, DECK_HEIGHT, sz * 27)
			_emit = true
			_box(Vector3(16.1, 0.1, 0.12), Transform3D(Basis.IDENTITY, c + Vector3(0, -0.15, sz * 8.0)), N_PINK if sx * sz > 0 else N_CYAN, false)
			_box(Vector3(0.12, 0.1, 16.1), Transform3D(Basis.IDENTITY, c + Vector3(sx * 8.0, -0.15, 0)), N_PINK if sx * sz > 0 else N_CYAN, false)
			_emit = false
			_box(Vector3(3.0, 1.6, 2.2), Transform3D(Basis.IDENTITY, c + Vector3(sx * 4.0, 0.8, sz * 4.0)), C_METAL, true, C_METAL.lightened(0.1))
			_cylinder(0.8, 0.8, 0.2, c + Vector3(sx * 4.0, 1.6, sz * 4.0), C_DARK, 8, false)


func _build_centre() -> void:
	# Hologram plinth in the middle.
	_cylinder(3.0, 3.2, 1.0, Vector3.ZERO, C_DARK, 12, true)
	_emit = true
	_cylinder(3.05, 3.05, 0.12, Vector3(0, 0.7, 0), N_CYAN, 12, false)
	_cylinder(0.0, 1.4, 2.6, Vector3(0, 1.0, 0), N_PINK.darkened(0.2), 4, false)
	_emit = false
	# Boost pads on the four lanes into the centre.
	_boost_pad(Vector2(0, 16), Vector2(2.5, 3.0), Vector3(0, 0, -1))
	_boost_pad(Vector2(0, -16), Vector2(2.5, 3.0), Vector3(0, 0, 1))
	_boost_pad(Vector2(16, 0), Vector2(3.0, 2.5), Vector3(-1, 0, 0))
	_boost_pad(Vector2(-16, 0), Vector2(3.0, 2.5), Vector3(1, 0, 0))


func _build_obstacles() -> void:
	# Billboards on posts along the walls (signs are visual, posts are solid).
	var boards := [[Vector3(22, 0, 43.2), 0.0, N_YELLOW], [Vector3(-22, 0, -43.2), PI, N_GREEN],
		[Vector3(43.2, 0, 24), PI * 0.5, N_PINK], [Vector3(-43.2, 0, -24), -PI * 0.5, N_CYAN]]
	for b in boards:
		var p: Vector3 = b[0]
		var basis := Basis(Vector3.UP, float(b[1]))
		for off: float in [-3.0, 3.0]:
			_cylinder(0.2, 0.2, 5.0, p + basis * Vector3(off, 0, 0), C_METAL, 6, true)
		_box(Vector3(8.0, 3.0, 0.3), Transform3D(basis, p + Vector3(0, 6.2, 0)), C_DARK, false)
		_emit = true
		_box(Vector3(7.4, 2.4, 0.32), Transform3D(basis, p + Vector3(0, 6.2, 0)), (b[2] as Color).darkened(0.3), false)
		_box(Vector3(5.0, 0.4, 0.34), Transform3D(basis, p + Vector3(0, 6.6, 0)), Color(1, 1, 1), false)
		_box(Vector3(3.5, 0.3, 0.34), Transform3D(basis, p + Vector3(-0.7, 5.8, 0)), Color(1, 1, 1, 1).darkened(0.1), false)
		_emit = false
	# Vents and crates on the lanes between the decks.
	for p: Vector3 in [Vector3(36, 0, 10), Vector3(-36, 0, -10), Vector3(10, 0, -36), Vector3(-10, 0, 36)]:
		_box(Vector3(2.4, 1.2, 2.4), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6, 0)), C_METAL, true, C_METAL.darkened(0.2))
		_box(Vector3(1.6, 0.1, 1.6), Transform3D(Basis.IDENTITY, p + Vector3(0, 1.25, 0)), C_DARK, false)
	# Antenna masts in the narrow corners.
	for p: Vector3 in [Vector3(40, 0, 40), Vector3(-40, 0, -40), Vector3(40, 0, -40), Vector3(-40, 0, 40)]:
		_cylinder(0.25, 0.4, 8.0, p, C_METAL, 6, true)
		_emit = true
		_cylinder(0.3, 0.3, 0.4, p + Vector3(0, 8.0, 0), Color(1, 0.2, 0.2), 6, false)
		_emit = false


func _build_backdrop() -> void:
	# Skyscrapers around the roof with glowing windows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 22:
		var a := TAU * i / 22.0 + rng.randf_range(-0.08, 0.08)
		var r := rng.randf_range(70.0, 110.0)
		var w := rng.randf_range(10.0, 18.0)
		var h := rng.randf_range(18.0, 60.0)
		var pos := Vector3(cos(a) * r, -12.0, sin(a) * r)
		var basis := Basis(Vector3.UP, PI * 0.5 - a)  # -Z faces the arena
		_box(Vector3(w, h, w), Transform3D(basis, pos + Vector3(0, h * 0.5, 0)), Color(0.08, 0.08, 0.13), false)
		_emit = true
		var col: Color = [N_CYAN, N_PINK, N_YELLOW][i % 3]
		var rows := int(h / 5.0)
		for row in rows:
			if rng.randf() < 0.35:
				continue
			var y := -12.0 + 3.0 + row * 5.0
			# Window band on the side facing the arena.
			_box(Vector3(w * 0.8, 0.8, 0.1), Transform3D(basis, Vector3(pos.x, y, pos.z) + basis * Vector3(0, 0, -w * 0.5 - 0.05)), col.darkened(0.5), false)
		_emit = false
	_quad_up(Vector3(-170, 0, -170), Vector3(170, 0, 170), -12.0, Color(0.05, 0.05, 0.08))


func _build_markers() -> void:
	for p: Vector3 in [Vector3(0, 0.15, 38), Vector3(0, 0.15, -38), Vector3(38, 0.15, 0), Vector3(-38, 0.15, 0),
			Vector3(40, 0.15, -12), Vector3(12, 0.15, 40), Vector3(-40, 0.15, 12), Vector3(-12, 0.15, -40)]:
		_add_spawn(p)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_crate_spawn(Vector3(sx * 27 - sx * 2.0, DECK_HEIGHT + 0.8, sz * 27 - sz * 2.0))
			_add_crate_spawn(Vector3(sx * 8, 0.8, sz * 8))
	_add_crate_spawn(Vector3(30, 0.8, 0))
	_add_crate_spawn(Vector3(-30, 0.8, 0))


func _build_lighting() -> void:
	_add_environment({
		"sun_color": Color(0.65, 0.70, 1.0), "sun_energy": 0.6,
		"sun_rotation": Vector3(deg_to_rad(-55.0), deg_to_rad(-30.0), 0.0),
		"sky_top": Color(0.03, 0.02, 0.09), "sky_horizon": Color(0.30, 0.10, 0.36),
		"ground_bottom": Color(0.02, 0.02, 0.04), "ground_horizon": Color(0.22, 0.08, 0.28),
		"ambient": 1.0, "fog_color": Color(0.25, 0.10, 0.35), "fog_density": 0.0035,
	})
