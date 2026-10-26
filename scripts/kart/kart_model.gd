## Procedural low-poly kart: chassis, driver, spinning/steering wheels, spoiler,
## drift smoke and a boost flame. Built from primitive meshes; -Z is forward.
class_name KartModel
extends Node3D

const WHEEL_RADIUS := 0.33
const WHEEL_WIDTH := 0.3
const MAX_STEER_ANGLE := 0.45

var kart_color: Color = Color(0.9, 0.3, 0.2)

static var _shared: Dictionary = {}

var _body_mesh: MeshInstance3D
var _tilt: Node3D
var _front_pivots: Array[Node3D] = []
var _wheel_spinners: Array[MeshInstance3D] = []
var _smoke: Array[CPUParticles3D] = []
var _flame: MeshInstance3D
var _spin: float = 0.0
var _steer_vis: float = 0.0
var _last_speed: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0


func _ready() -> void:
	_build()


func set_color(c: Color) -> void:
	kart_color = c
	_rebuild_body()


func reset_pose() -> void:
	if _tilt:
		_tilt.transform = Transform3D.IDENTITY
	_pitch = 0.0
	_roll = 0.0
	for p in _smoke:
		p.emitting = false


## Called by the kart every physics frame.
func update_visual(delta: float, forward_speed: float, steer_input: float, is_drifting: bool,
		drift_charged: bool, floor_normal: Vector3, on_floor: bool, kart_basis: Basis) -> void:
	# Wheels.
	_spin -= forward_speed / WHEEL_RADIUS * delta
	_spin = fmod(_spin, TAU)
	for w in _wheel_spinners:
		w.rotation.x = _spin
	_steer_vis = lerpf(_steer_vis, -steer_input * MAX_STEER_ANGLE, clampf(delta * 12.0, 0.0, 1.0))
	for p in _front_pivots:
		p.rotation.y = _steer_vis

	# Body: align with the ground, lean into turns, pitch with acceleration.
	var accel := (forward_speed - _last_speed) / maxf(delta, 0.0001)
	_last_speed = forward_speed
	var target_pitch := clampf(accel * 0.004, -0.08, 0.08)
	var lean := 0.09 if is_drifting else 0.04
	var target_roll := steer_input * lean * clampf(absf(forward_speed) / 15.0, 0.0, 1.0)
	_pitch = lerpf(_pitch, target_pitch, clampf(delta * 6.0, 0.0, 1.0))
	_roll = lerpf(_roll, target_roll, clampf(delta * 6.0, 0.0, 1.0))

	var local_up := (kart_basis.inverse() * floor_normal).normalized() if on_floor else Vector3.UP
	var align := Quaternion(Vector3.UP, local_up) if local_up.dot(Vector3.UP) < 0.9999 else Quaternion.IDENTITY
	var extra := Quaternion(Vector3.RIGHT, _pitch) * Quaternion(Vector3.FORWARD, -_roll)
	var target := align * extra
	var cur := _tilt.quaternion
	_tilt.quaternion = cur.slerp(target, clampf(delta * 10.0, 0.0, 1.0))

	var smoke_on := is_drifting and on_floor
	for p in _smoke:
		p.emitting = smoke_on
		p.color = Color(1.0, 0.6, 0.15) if drift_charged else Color(0.85, 0.85, 0.85, 0.8)

	var k := get_parent()
	var boosting := k != null and k.has_method("is_boosting") and bool(k.call("is_boosting"))
	_flame.visible = boosting
	if boosting:
		var s := 0.8 + randf() * 0.5
		_flame.scale = Vector3(s, s, s)


# --- Building -------------------------------------------------------------------
# Static parts are merged into one vertex-coloured mesh (one draw call per kart body,
# one per wheel) to keep the draw-call count low on mobile / web.

static func _shared_mat(key: String, color: Color = Color.WHITE, unshaded: bool = false) -> StandardMaterial3D:
	if _shared.has(key):
		return _shared[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = false
	_shared[key] = m
	return m


func _build() -> void:
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	add_child(_tilt)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.material_override = _shared_mat("vc")
	_tilt.add_child(_body_mesh)
	_rebuild_body()

	# Wheels: pivot (steers) -> spinner (rolls) -> mesh. One shared mesh for all wheels.
	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_RADIUS
	tyre.bottom_radius = WHEEL_RADIUS
	tyre.height = WHEEL_WIDTH
	tyre.radial_segments = 10
	tyre.rings = 1
	var cap := CylinderMesh.new()
	cap.top_radius = WHEEL_RADIUS * 0.5
	cap.bottom_radius = WHEEL_RADIUS * 0.5
	cap.height = WHEEL_WIDTH + 0.04
	cap.radial_segments = 6
	cap.rings = 1
	var spoke := BoxMesh.new()
	spoke.size = Vector3(WHEEL_WIDTH + 0.06, WHEEL_RADIUS * 1.5, 0.08)
	var roll := Basis(Vector3.FORWARD, PI * 0.5)
	var wheel_parts: Array = [
		[tyre, Transform3D(roll, Vector3.ZERO), Color(0.1, 0.1, 0.12)],
		[cap, Transform3D(roll, Vector3.ZERO), Color(0.9, 0.82, 0.3)],
		[spoke, Transform3D.IDENTITY, Color(0.75, 0.68, 0.25)],
	]
	var wheel_mesh := _merge(wheel_parts)
	for wz: float in [-0.8, 0.8]:
		for wx: float in [-0.72, 0.72]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, WHEEL_RADIUS, wz)
			_tilt.add_child(pivot)
			var spinner := MeshInstance3D.new()
			spinner.mesh = wheel_mesh
			spinner.material_override = _shared_mat("vc")
			pivot.add_child(spinner)
			_wheel_spinners.append(spinner)
			if wz < 0.0:
				_front_pivots.append(pivot)

	# Boost flame (hidden until boosting).
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.17
	cone.height = 0.6
	cone.radial_segments = 6
	cone.rings = 1
	_flame.mesh = cone
	_flame.material_override = _shared_mat("flame", Color(1.0, 0.55, 0.1), true)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0, 0.45, 1.6)
	_flame.rotation = Vector3(PI * 0.5, 0, 0)
	_flame.visible = false
	_tilt.add_child(_flame)

	# Drift smoke / sparks at the rear wheels (CPU particles: web-compatible).
	var puff: BoxMesh
	if _shared.has("puff_mesh"):
		puff = _shared["puff_mesh"] as BoxMesh
	else:
		puff = BoxMesh.new()
		puff.size = Vector3(0.22, 0.22, 0.22)
		var puff_mat := StandardMaterial3D.new()
		puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_mat.vertex_color_use_as_albedo = true
		puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material = puff_mat
		_shared["puff_mesh"] = puff
	for sx: float in [-0.72, 0.72]:
		var p := CPUParticles3D.new()
		p.mesh = puff
		p.amount = 12
		p.lifetime = 0.45
		p.emitting = false
		p.local_coords = false
		p.direction = Vector3(0, 1, 1)
		p.spread = 35.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.5
		p.gravity = Vector3(0, 1.5, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		p.position = Vector3(sx, 0.1, 0.95)
		_tilt.add_child(p)
		_smoke.append(p)


func _rebuild_body() -> void:
	if _body_mesh == null:
		return
	var body := kart_color
	var accent := kart_color.lightened(0.35)
	var dark := Color(0.13, 0.13, 0.15)
	var metal := Color(0.62, 0.64, 0.68)
	var seat := Color(0.2, 0.17, 0.22)
	var suit := Color(0.95, 0.95, 0.92)
	var visor := Color(0.08, 0.1, 0.2)
	var parts: Array = []
	# Chassis and bodywork.
	parts.append(_p(_box(Vector3(1.25, 0.18, 2.3)), Vector3(0, 0.3, 0), Vector3.ZERO, dark))
	parts.append(_p(_box(Vector3(1.05, 0.32, 1.5)), Vector3(0, 0.52, 0.15), Vector3.ZERO, body))
	parts.append(_p(_box(Vector3(0.9, 0.22, 0.8)), Vector3(0, 0.48, -0.95), Vector3(-0.22, 0, 0), body))
	parts.append(_p(_box(Vector3(1.4, 0.16, 0.22)), Vector3(0, 0.32, -1.25), Vector3.ZERO, accent))
	parts.append(_p(_box(Vector3(0.28, 0.26, 1.1)), Vector3(0.68, 0.44, 0.1), Vector3.ZERO, accent))
	parts.append(_p(_box(Vector3(0.28, 0.26, 1.1)), Vector3(-0.68, 0.44, 0.1), Vector3.ZERO, accent))
	parts.append(_p(_prism(Vector3(0.7, 0.2, 0.5)), Vector3(0, 0.77, -0.5), Vector3.ZERO, accent))
	# Seat and driver.
	parts.append(_p(_box(Vector3(0.6, 0.12, 0.55)), Vector3(0, 0.72, 0.4), Vector3.ZERO, seat))
	parts.append(_p(_box(Vector3(0.6, 0.55, 0.12)), Vector3(0, 0.98, 0.7), Vector3(0.15, 0, 0), seat))
	parts.append(_p(_cyl(0.2, 0.24, 0.5, 8), Vector3(0, 1.02, 0.42), Vector3.ZERO, suit))
	parts.append(_p(_sphere(0.24), Vector3(0, 1.43, 0.38), Vector3.ZERO, accent))
	parts.append(_p(_box(Vector3(0.36, 0.12, 0.1)), Vector3(0, 1.46, 0.17), Vector3.ZERO, visor))
	parts.append(_p(_cyl(0.16, 0.16, 0.04, 8), Vector3(0, 0.95, -0.02), Vector3(deg_to_rad(65), 0, 0), dark))
	# Spoiler and exhausts.
	parts.append(_p(_box(Vector3(0.07, 0.42, 0.12)), Vector3(0.42, 0.78, 1.05), Vector3.ZERO, metal))
	parts.append(_p(_box(Vector3(0.07, 0.42, 0.12)), Vector3(-0.42, 0.78, 1.05), Vector3.ZERO, metal))
	parts.append(_p(_box(Vector3(1.4, 0.06, 0.38)), Vector3(0, 1.0, 1.1), Vector3(0.12, 0, 0), body))
	parts.append(_p(_box(Vector3(0.06, 0.22, 0.42)), Vector3(0.7, 1.05, 1.1), Vector3.ZERO, accent))
	parts.append(_p(_box(Vector3(0.06, 0.22, 0.42)), Vector3(-0.7, 1.05, 1.1), Vector3.ZERO, accent))
	for sx: float in [-0.22, 0.22]:
		parts.append(_p(_cyl(0.07, 0.08, 0.35, 6), Vector3(sx, 0.45, 1.2), Vector3(PI * 0.5, 0, 0), metal))
	_body_mesh.mesh = _merge(parts)


static func _p(mesh: PrimitiveMesh, pos: Vector3, rot: Vector3, color: Color) -> Array:
	return [mesh, Transform3D(Basis.from_euler(rot), pos), color]


## Merges [mesh, transform, color] entries into one vertex-coloured ArrayMesh.
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var mesh := part[0] as PrimitiveMesh
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var arr := mesh.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi_: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((nb * pn[i]).normalized())
			colors.append(col)
		for idx in pi_:
			indices.append(base + idx)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 5
	return m
