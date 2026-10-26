## Base class for battle maps built entirely in code.
## A map subclass fills in `_build_layout()` with the geometry helpers below; static
## geometry is merged into one vertex-coloured mesh (plus an optional unshaded "glow"
## surface) and one StaticBody3D on layer 1 with a collision shape per solid piece.
##
## Maps also provide spawn and crate markers, an AI routing hint (`get_waypoint`),
## special floor zones (ice, boost pads; see `surface_at`) and 2D footprints that the
## map preview in the Play screen draws.
class_name ArenaBase
extends Node3D

const C_WHITE := Color(0.95, 0.94, 0.90)
const C_TYRE := Color(0.13, 0.13, 0.15)
const C_HAZARD_Y := Color(0.95, 0.75, 0.15)
const C_HAZARD_K := Color(0.15, 0.14, 0.15)

## Walls sit at +/- half_size on X and Z.
var half_size := 45.0
var wall_height := 3.2
## Main floor colour, used by the map preview.
var ground_color := Color(0.8, 0.6, 0.45)
var wall_color := Color(0.6, 0.3, 0.2)
## 2D outlines for the map preview: {kind: "rect"|"circle"|"poly"|"zone", ...}.
var footprints: Array = []

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _glow_verts := PackedVector3Array()
var _glow_normals := PackedVector3Array()
var _glow_colors := PackedColorArray()
## While true, geometry goes to the unshaded glow surface (neon signs, lights).
var _emit := false
var _body: StaticBody3D
var _spawns: Array[Marker3D] = []
var _crate_spawns: Array[Marker3D] = []
## Raised areas for AI routing: {center: Vector2, half: Vector2, height: float, ramps: Array}.
## A ramp is {bottom: Vector3, top: Vector3, width: float}.
var _platforms: Array = []
## Floor zones: {type: "ice"|"boost", center: Vector2, half: Vector2} (axis-aligned rects).
var _zones: Array = []
var _built := false


func _ready() -> void:
	add_to_group("arena")
	build_layout()
	_commit_mesh()
	_build_lighting()


## Builds the geometry and markers once (the preview calls this outside the tree).
func build_layout() -> void:
	if _built:
		return
	_built = true
	_body = StaticBody3D.new()
	_body.name = "World"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_build_layout()


func get_display_name() -> String:
	return "Arena"


func get_spawn_points() -> Array[Marker3D]:
	return _spawns


func get_crate_spawn_points() -> Array[Marker3D]:
	return _crate_spawns


## Floor type under `pos`: "" (normal), "ice" or "boost".
func surface_at(pos: Vector3) -> String:
	for z in _zones:
		var c: Vector2 = z["center"]
		var h: Vector2 = z["half"]
		if absf(pos.x - c.x) <= h.x and absf(pos.z - c.y) <= h.y and pos.y < float(z.get("top", 0.6)):
			return str(z["type"])
	return ""


## Navigation hint for AI: where to drive next on the way from `from` to `to`.
## Targets on a raised platform are reached through the cheapest of its ramps.
func get_waypoint(from: Vector3, to: Vector3) -> Vector3:
	for p in _platforms:
		var h: float = p["height"]
		if not _on_platform(p, to) or to.y < h - 0.6:
			continue
		if from.y > h - 0.6 and _on_platform(p, from):
			return to
		var best: Dictionary = {}
		var best_cost := INF
		for r in p["ramps"]:
			var approach := _ramp_approach(r)
			var cost := _flat(from).distance_to(_flat(approach)) + _flat(r["top"]).distance_to(_flat(to))
			if cost < best_cost:
				best_cost = cost
				best = r
		if best.is_empty():
			return to
		var bottom: Vector3 = best["bottom"]
		var top: Vector3 = best["top"]
		var dir := _flat(top - bottom).normalized()
		var length := _flat(top - bottom).length()
		var rel := _flat(from - bottom)
		var t := rel.dot(dir)
		var lateral := absf(rel.cross(dir).y)
		var funnel := float(best["width"]) * 0.5 - 1.0 + maxf(-t, 0.0) * 0.8
		if t > -9.0 and t < length + 1.0 and lateral < funnel:
			var along := minf(t + 7.0, length + 2.0)
			return bottom + dir * along + Vector3.UP * h * clampf(along / length, 0.0, 1.0)
		return _ramp_approach(best)
	return to


func _ramp_approach(r: Dictionary) -> Vector3:
	var bottom: Vector3 = r["bottom"]
	var dir := _flat(Vector3(r["top"]) - bottom).normalized()
	return bottom - dir * 7.0


func _on_platform(p: Dictionary, pos: Vector3) -> bool:
	var c: Vector2 = p["center"]
	var h: Vector2 = p["half"]
	return absf(pos.x - c.x) < h.x and absf(pos.z - c.y) < h.y


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Overridables ---------------------------------------------------------------

## Subclasses build geometry, markers, platforms and zones here.
func _build_layout() -> void:
	pass


## Subclasses override to set the sun, sky and fog.
func _build_lighting() -> void:
	_add_environment({})


# --- Shared builders ----------------------------------------------------------------

## Checkerboard floor plus a thick collider.
func _build_floor(tile: float, col_a: Color, col_b: Color) -> void:
	var n := int(ceil(half_size * 2.0 / tile))
	for ix in n:
		for iz in n:
			var c := col_a if (ix + iz) % 2 == 0 else col_b
			var x0 := -half_size + ix * tile
			var z0 := -half_size + iz * tile
			_quad_up(Vector3(x0, 0, z0), Vector3(minf(x0 + tile, half_size), 0, minf(z0 + tile, half_size)), 0.0, c)
	_collider_box(Vector3(half_size * 2.0 + 10.0, 2.0, half_size * 2.0 + 10.0), Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))


## Perimeter walls in alternating segments, a trim on top and a tall invisible collider.
func _build_perimeter(col_a: Color, col_b: Color, trim: Color, seg := 6.0) -> void:
	var t := 1.5
	var count := int(half_size * 2.0 / seg)
	for side in 4:
		var basis := Basis(Vector3.UP, PI * 0.5 * side)
		for i in count + 1:
			var along := -half_size + i * seg
			var c := col_a if i % 2 == 0 else col_b
			var local := Vector3(along, wall_height * 0.5, -half_size - t * 0.5)
			_box(Vector3(seg, wall_height, t), Transform3D(basis, basis * local), c, false)
		_box(Vector3(half_size * 2.0 + t * 2.0, 0.3, t + 0.3), Transform3D(basis, basis * Vector3(0, wall_height + 0.15, -half_size - t * 0.5)), trim, false)
		_collider_box(Vector3(half_size * 2.0 + t * 4.0, 12.0, t), Transform3D(basis, basis * Vector3(0, 6.0, -half_size - t * 0.5)))


## `count` spawn points on a ring, each facing the centre.
func _ring_spawns(count: int, radius: float, y := 0.15, phase := 0.5) -> void:
	for i in count:
		var a := TAU * (i + phase) / count
		_add_spawn(Vector3(cos(a) * radius, y, sin(a) * radius))


func _add_spawn(pos: Vector3, look_at_point := Vector3.ZERO) -> void:
	var root := get_node_or_null("SpawnPoints")
	if root == null:
		root = Node3D.new()
		root.name = "SpawnPoints"
		add_child(root)
	var m := Marker3D.new()
	m.name = "Spawn%d" % _spawns.size()
	var dir := Vector3(look_at_point.x - pos.x, 0, look_at_point.z - pos.z)
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	m.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pos)
	m.add_to_group("spawn_points")
	root.add_child(m)
	_spawns.append(m)


func _add_crate_spawn(pos: Vector3) -> void:
	var root := get_node_or_null("CrateSpawns")
	if root == null:
		root = Node3D.new()
		root.name = "CrateSpawns"
		add_child(root)
	var m := Marker3D.new()
	m.name = "Crate%d" % _crate_spawns.size()
	m.position = pos
	m.add_to_group("crate_spawns")
	root.add_child(m)
	_crate_spawns.append(m)


## Raised platform with ramps, registered for AI routing. `ramp_sides` lists the
## directions the ramps come down towards ("n" = +Z, "s" = -Z, "e" = +X, "w" = -X).
func _platform_with_ramps(center: Vector2, half: Vector2, height: float, ramp_sides: Array,
		col: Color, top_col: Color, ramp_col: Color, ramp_len := 10.0, ramp_w := 8.0) -> void:
	_box(Vector3(half.x * 2.0, height, half.y * 2.0), Transform3D(Basis.IDENTITY, Vector3(center.x, height * 0.5, center.y)), col, true, top_col)
	var ramps: Array = []
	for s in ramp_sides:
		var out := Vector3.ZERO
		var yaw := 0.0
		var edge := 0.0
		match str(s):
			"n":
				out = Vector3(0, 0, 1)
				yaw = 0.0
				edge = half.y
			"s":
				out = Vector3(0, 0, -1)
				yaw = PI
				edge = half.y
			"e":
				out = Vector3(1, 0, 0)
				yaw = PI * 0.5
				edge = half.x
			"w":
				out = Vector3(-1, 0, 0)
				yaw = -PI * 0.5
				edge = half.x
		var c3 := Vector3(center.x, 0, center.y)
		_wedge(Vector3(ramp_w, height, ramp_len), Transform3D(Basis(Vector3.UP, yaw), c3 + out * (edge + ramp_len * 0.5)), ramp_col)
		ramps.append({"bottom": c3 + out * (edge + ramp_len), "top": c3 + out * edge + Vector3.UP * height, "width": ramp_w})
	_platforms.append({"center": center, "half": half, "height": height, "ramps": ramps})


## Speed pad: the kart gets a drift-style boost while driving over it.
func _boost_pad(center: Vector2, half: Vector2, yaw_dir: Vector3) -> void:
	_zones.append({"type": "boost", "center": center, "half": half})
	footprints.append({"kind": "zone", "type": "boost", "center": center, "half": half})
	var was := _emit
	_emit = true
	var base := Vector3(center.x, 0.02, center.y)
	_quad_up(base - Vector3(half.x, 0, half.y), base + Vector3(half.x, 0, half.y), 0.02, Color(0.1, 0.9, 1.0))
	# Chevrons pointing along yaw_dir.
	var f := yaw_dir.normalized()
	var r := Vector3(-f.z, 0, f.x)
	var span := minf(half.x, half.y)
	for i in 3:
		var p := base + f * (-span * 0.6 + i * span * 0.6) + Vector3.UP * 0.02
		var w := span * 0.7
		var tip := p + f * span * 0.35
		_tri(p - r * w, tip, p - r * w + f * 0.35, Vector3.UP, Color(1, 1, 1))
		_tri(p - r * w + f * 0.35, tip, tip + f * 0.35, Vector3.UP, Color(1, 1, 1))
		_tri(p + r * w, tip, p + r * w + f * 0.35, Vector3.UP, Color(1, 1, 1))
		_tri(p + r * w + f * 0.35, tip, tip + f * 0.35, Vector3.UP, Color(1, 1, 1))
	_emit = was


## Slippery patch (lower grip).
func _ice_patch(center: Vector2, half: Vector2, col: Color) -> void:
	_zones.append({"type": "ice", "center": center, "half": half})
	footprints.append({"kind": "zone", "type": "ice", "center": center, "half": half})
	var base := Vector3(center.x, 0, center.y)
	_quad_up(base - Vector3(half.x, 0, half.y), base + Vector3(half.x, 0, half.y), 0.015, col)


func _add_environment(o: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = o.get("sun_color", Color(1.0, 0.95, 0.85))
	sun.light_energy = float(o.get("sun_energy", 1.1))
	sun.rotation = o.get("sun_rotation", Vector3(deg_to_rad(-45.0), deg_to_rad(-125.0), 0.0))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.08
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = o.get("sky_top", Color(0.3, 0.5, 0.85))
	sky_mat.sky_horizon_color = o.get("sky_horizon", Color(0.75, 0.85, 0.95))
	sky_mat.sky_curve = float(o.get("sky_curve", 0.12))
	sky_mat.ground_bottom_color = o.get("ground_bottom", Color(0.2, 0.2, 0.22))
	sky_mat.ground_horizon_color = o.get("ground_horizon", Color(0.7, 0.75, 0.8))
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(o.get("ambient", 0.7))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if o.has("fog_color"):
		env.fog_enabled = true
		env.fog_light_color = o["fog_color"]
		env.fog_density = float(o.get("fog_density", 0.004))
		env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# --- Geometry helpers ---------------------------------------------------------


## Adds a triangle; winding is fixed up so the face points along n (Godot: clockwise front).
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	if _emit:
		_glow_verts.append_array([a, b, c])
		_glow_normals.append_array([n, n, n])
		_glow_colors.append_array([col, col, col])
		return
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
		footprints.append({"kind": "rect", "center": Vector2(center.x, center.z), "half": Vector2(h.x, h.z),
			"yaw": atan2(xform.basis.x.z, xform.basis.x.x), "color": top, "height": center.y + h.y})


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
		footprints.append({"kind": "circle", "center": Vector2(base_pos.x, base_pos.z), "radius": maxf(top_r, bottom_r),
			"color": col, "height": base_pos.y + height})


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
	var poly := PackedVector2Array()
	for i in [0, 1, 3, 2]:
		poly.append(Vector2(w[i].x, w[i].z))
	footprints.append({"kind": "poly", "points": poly, "color": col, "height": size.y})
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
	var mesh := ArrayMesh.new()
	if not _verts.is_empty():
		_add_surface(mesh, _verts, _normals, _colors)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.95
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	if not _glow_verts.is_empty():
		_add_surface(mesh, _glow_verts, _glow_normals, _glow_colors)
		var glow := StandardMaterial3D.new()
		glow.vertex_color_use_as_albedo = true
		glow.vertex_color_is_srgb = true
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow)
	var mi := MeshInstance3D.new()
	mi.name = "ArenaMesh"
	mi.mesh = mesh
	add_child(mi)
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_glow_verts = PackedVector3Array()
	_glow_normals = PackedVector3Array()
	_glow_colors = PackedColorArray()


static func _add_surface(mesh: ArrayMesh, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
