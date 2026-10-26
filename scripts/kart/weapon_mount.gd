## Visible weapon hardware on a kart: rocket pods, twin guns, a mine rack or a shield
## emitter, plus an underglow in the weapon's colour. Ammo is shown on the model
## (rockets / mines disappear as they are used). Child of KartModel's tilt node.
class_name WeaponMount
extends Node3D

const METAL := Color(0.55, 0.57, 0.62)
const DARK := Color(0.16, 0.16, 0.19)

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

var weapon_id: String = ""

var _rig: Node3D
var _ammo_items: Array[Node3D] = []
var _spinner: Node3D
var _orb: MeshInstance3D
var _glow: MeshInstance3D
var _flash: MeshInstance3D
var _pop: float = 1.0
var _recoil: float = 0.0
var _spin_speed: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_glow = MeshInstance3D.new()
	_glow.name = "Underglow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.7, 2.7)
	_glow.mesh = plane
	_glow.position = Vector3(0, 0.06, 0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	add_child(_glow)


## Shows the hardware for `id` ("" removes it). Safe to call every time ammo changes.
func show_weapon(id: String, ammo: int, color: Color) -> void:
	if id != weapon_id:
		weapon_id = id
		_build_rig(id, color)
		_pop = 0.0
	_update_ammo(ammo)


## Visual kick when the weapon fires.
func on_fired(id: String) -> void:
	if id != weapon_id:
		return
	_recoil = 1.0
	if id == "machine_gun":
		_spin_speed = 28.0
	if _flash:
		_flash.visible = true
		_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)


func _process(delta: float) -> void:
	_time += delta
	if _rig == null:
		return
	if _pop < 1.0:
		_pop = minf(_pop + delta * 4.0, 1.0)
		# Overshooting pop-in so picking up a weapon reads clearly.
		var s := 1.0 + sin(_pop * PI) * 0.35
		_rig.scale = Vector3.ONE * lerpf(0.2, 1.0, _pop) * s
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_rig.position.z = _recoil * 0.12
	if _spinner:
		_spin_speed = move_toward(_spin_speed, 0.0, delta * 30.0)
		_spinner.rotate_z(_spin_speed * delta)
	if _flash and _recoil < 0.6:
		_flash.visible = false
	if _orb:
		var p := 1.0 + sin(_time * 5.0) * 0.12
		_orb.scale = Vector3(p, p, p)
	if _glow.visible:
		var m := _glow.material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = 0.32 + sin(_time * 4.0) * 0.08


func _build_rig(id: String, color: Color) -> void:
	if _rig:
		_rig.queue_free()
	_rig = null
	_ammo_items.clear()
	_spinner = null
	_orb = null
	_flash = null
	_glow.visible = id != ""
	if id == "":
		return
	_glow.material_override = _glow_material(color)
	_rig = Node3D.new()
	_rig.name = "Rig_" + id
	add_child(_rig)
	match id:
		"rocket":
			_build_rocket_pods(color)
		"machine_gun":
			_build_guns(color)
		"mine":
			_build_mine_rack(color)
		"shield":
			_build_shield(color)
		_:
			_add(_rig, _cached("generic", func() -> Array:
				return [[_box(Vector3(0.4, 0.3, 0.4)), Transform3D(Basis(), Vector3(0, 1.0, 0.8)), color]]), Vector3.ZERO)


func _update_ammo(ammo: int) -> void:
	for i in _ammo_items.size():
		_ammo_items[i].visible = i < ammo


# --- Rigs ------------------------------------------------------------------------

func _build_rocket_pods(color: Color) -> void:
	# Two side pods beside the driver, each holding one visible rocket.
	var pod := _cached("rocket_pod", func() -> Array:
		var r := Basis(Vector3.RIGHT, PI * 0.5)
		return [
			[_cyl(0.23, 0.23, 1.05, 8), Transform3D(r, Vector3.ZERO), color.darkened(0.25)],
			[_cyl(0.25, 0.25, 0.14, 8), Transform3D(r, Vector3(0, 0, -0.48)), METAL],
			[_cyl(0.25, 0.25, 0.14, 8), Transform3D(r, Vector3(0, 0, 0.45)), DARK],
			[_box(Vector3(0.1, 0.36, 0.34)), Transform3D(Basis(), Vector3(0, -0.24, 0.1)), METAL],
		])
	var rocket := _cached("rocket_tip", func() -> Array:
		var r := Basis(Vector3.RIGHT, -PI * 0.5)
		return [
			[_cyl(0.0, 0.16, 0.36, 8), Transform3D(r, Vector3(0, 0, -0.72)), Color(1.0, 0.95, 0.85)],
			[_cyl(0.16, 0.16, 0.2, 8), Transform3D(r, Vector3(0, 0, -0.46)), Color(1.0, 0.3, 0.15)],
		])
	for side: float in [-1.0, 1.0]:
		var base := Vector3(side * 0.68, 1.05, 0.05)
		_add(_rig, pod, base)
		var tip := _add(_rig, rocket, base)
		_ammo_items.append(tip)
	_add(_rig, _cached("rocket_bar", func() -> Array:
		return [[_box(Vector3(1.3, 0.08, 0.14)), Transform3D(Basis(), Vector3(0, 0.78, 0.15)), color]]), Vector3.ZERO)


func _build_guns(color: Color) -> void:
	# Twin rotary barrels on the hood.
	_add(_rig, _cached("gun_base", func() -> Array:
		return [
			[_box(Vector3(0.62, 0.16, 0.5)), Transform3D(Basis(), Vector3(0, 0.82, -0.55)), DARK],
			[_box(Vector3(0.5, 0.08, 0.3)), Transform3D(Basis(), Vector3(0, 0.94, -0.5)), color],
		]), Vector3.ZERO)
	_spinner = Node3D.new()
	_spinner.position = Vector3(0, 0.95, -0.85)
	_rig.add_child(_spinner)
	_add(_spinner, _cached("gun_barrels", func() -> Array:
		var r := Basis(Vector3.RIGHT, PI * 0.5)
		var parts: Array = []
		for i in 3:
			var a := TAU * float(i) / 3.0
			var off := Vector3(cos(a), sin(a), 0) * 0.07
			for sx: float in [-0.16, 0.16]:
				parts.append([_cyl(0.035, 0.035, 0.75, 6), Transform3D(r, off + Vector3(sx, 0, -0.3)), METAL])
		for sx: float in [-0.16, 0.16]:
			parts.append([_cyl(0.11, 0.11, 0.16, 8), Transform3D(r, Vector3(sx, 0, -0.62)), DARK])
		return parts), Vector3.ZERO)
	_flash = MeshInstance3D.new()
	var quad := SphereMesh.new()
	quad.radius = 0.16
	quad.height = 0.32
	quad.radial_segments = 6
	quad.rings = 3
	_flash.mesh = quad
	_flash.material_override = _unshaded(Color(1.0, 0.85, 0.3))
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = Vector3(0, 0.95, -1.62)
	_flash.visible = false
	_rig.add_child(_flash)


func _build_mine_rack(color: Color) -> void:
	# A rack above the exhausts carrying the remaining mines.
	_add(_rig, _cached("mine_rack", func() -> Array:
		return [
			[_box(Vector3(0.9, 0.06, 0.5)), Transform3D(Basis(), Vector3(0, 0.72, 1.18)), DARK],
			[_box(Vector3(0.06, 0.4, 0.06)), Transform3D(Basis(), Vector3(0.42, 0.9, 1.18)), METAL],
			[_box(Vector3(0.06, 0.4, 0.06)), Transform3D(Basis(), Vector3(-0.42, 0.9, 1.18)), METAL],
		]), Vector3.ZERO)
	var mine := _cached("mine_disc", func() -> Array:
		return [
			[_cyl(0.2, 0.2, 0.1, 10), Transform3D(), DARK],
			[_cyl(0.07, 0.07, 0.06, 6), Transform3D(Basis(), Vector3(0, 0.07, 0)), Color(1.0, 0.25, 0.2)],
		])
	for i in 3:
		var item := _add(_rig, mine, Vector3((float(i) - 1.0) * 0.27, 0.82, 1.18))
		_ammo_items.append(item)
	_add(_rig, _cached("mine_stripe", func() -> Array:
		return [[_box(Vector3(0.95, 0.06, 0.06)), Transform3D(Basis(), Vector3(0, 0.75, 0.93)), color]]), Vector3.ZERO)


func _build_shield(color: Color) -> void:
	# Mast with a glowing emitter orb behind the driver.
	_add(_rig, _cached("shield_mast", func() -> Array:
		return [
			[_cyl(0.04, 0.05, 0.9, 6), Transform3D(Basis(), Vector3(0, 1.45, 0.92)), METAL],
			[_cyl(0.28, 0.12, 0.1, 10), Transform3D(Basis(), Vector3(0, 1.88, 0.92)), DARK],
		]), Vector3.ZERO)
	_orb = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.18
	s.height = 0.36
	s.radial_segments = 10
	s.rings = 5
	_orb.mesh = s
	_orb.material_override = _emissive(color)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.position = Vector3(0, 2.05, 0.92)
	_rig.add_child(_orb)
	_ammo_items.append(_orb)


# --- Helpers -----------------------------------------------------------------------

func _add(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = KartModel._shared_mat("vc")
	mi.position = pos
	parent.add_child(mi)
	return mi


## Builds (once per colour) a merged mesh from [mesh, transform, color] parts.
func _cached(key: String, parts_fn: Callable) -> Mesh:
	var full_key := key
	if _mesh_cache.has(full_key):
		return _mesh_cache[full_key] as Mesh
	var parts: Array = parts_fn.call()
	var mesh := KartModel._merge(parts)
	_mesh_cache[full_key] = mesh
	return mesh


static func _glow_material(color: Color) -> StandardMaterial3D:
	var key := "glow_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mat_cache[key] = m
	return m


static func _emissive(color: Color) -> StandardMaterial3D:
	var key := "emit_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	_mat_cache[key] = m
	return m


static func _unshaded(color: Color) -> StandardMaterial3D:
	var key := "unshaded_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	_mat_cache[key] = m
	return m


static func _box(size: Vector3) -> BoxMesh:
	return KartModel._box(size)


static func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	return KartModel._cyl(top, bottom, height, segments)
