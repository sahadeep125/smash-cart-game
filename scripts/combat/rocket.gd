## Rocket with a smoke trail and gentle homing toward a kart in a narrow forward cone.
## Explodes on world or kart contact, or at the end of its lifetime.
class_name RocketProjectile
extends Node3D

const HIT_RADIUS := 1.1

var owner_kart: Node3D
var weapon_id := "rocket"
var speed := 34.0
var damage := 45.0
var radius := 4.0
var knockback_force := 10.0
var lifetime := 3.0
var homing_cos := cos(deg_to_rad(16.0))
var homing_range := 45.0
var homing_turn := 2.0
var color := Color(1.0, 0.42, 0.12)

var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD
var _age := 0.0
var _exploded := false
var _trail: CPUParticles3D
var _flame: MeshInstance3D


func setup(p_owner: Node3D, origin: Vector3, direction: Vector3, data: Dictionary, extra_speed := 0.0) -> void:
	owner_kart = p_owner
	_origin = origin
	_dir = direction.normalized()
	speed = float(data.get("speed", speed)) + extra_speed
	damage = float(data.get("damage", damage))
	radius = float(data.get("radius", radius))
	knockback_force = float(data.get("knockback", knockback_force))
	lifetime = float(data.get("lifetime", lifetime))
	homing_cos = cos(deg_to_rad(float(data.get("homing_angle", 16.0))))
	homing_range = float(data.get("homing_range", homing_range))
	homing_turn = float(data.get("homing_turn", homing_turn))
	color = data.get("color", color)


func _ready() -> void:
	global_position = _origin
	_build_visual()
	_face_dir()


func _build_visual() -> void:
	var body := MeshInstance3D.new()
	body.mesh = CombatFx.shared_cylinder(0.13, 0.13, 0.75)
	body.rotation_degrees = Vector3(90, 0, 0)  # cylinder axis along Z
	body.material_override = CombatFx.flat_material(Color(0.92, 0.92, 0.95), 0.4)
	add_child(body)

	var nose := MeshInstance3D.new()
	nose.mesh = CombatFx.shared_cylinder(0.0, 0.13, 0.3)
	nose.rotation_degrees = Vector3(-90, 0, 0)  # tip toward -Z (forward)
	nose.position = Vector3(0, 0, -0.52)
	nose.material_override = CombatFx.emissive_material(color, 1.5)
	add_child(nose)

	for i in 3:  # three little fins
		var fin := MeshInstance3D.new()
		fin.mesh = CombatFx.shared_box(Vector3(0.03, 0.22, 0.22))
		fin.material_override = CombatFx.flat_material(color.darkened(0.2))
		fin.position = Vector3(0, 0.15, 0.3)
		var pivot := Node3D.new()
		pivot.rotation = Vector3(0, 0, TAU * i / 3.0)
		pivot.add_child(fin)
		add_child(pivot)

	_flame = MeshInstance3D.new()
	_flame.mesh = CombatFx.shared_sphere(0.16, 6, 3)
	_flame.position = Vector3(0, 0, 0.48)
	_flame.material_override = CombatFx.emissive_material(Color(1.0, 0.75, 0.2), 5.0)
	add_child(_flame)

	_trail = CombatFx.smoke_trail()
	_trail.position = Vector3(0, 0, 0.55)
	add_child(_trail)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	if _age >= lifetime:
		_explode(global_position)
		return
	_steer(delta)
	var from := global_position
	var to := from + _dir * speed * delta
	var hit := CombatUtil.sweep(self, from, to, HIT_RADIUS, owner_kart)
	if not hit.is_empty():
		_explode(hit.position - _dir * 0.15)
		return
	global_position = to
	_face_dir()
	if _flame != null:
		_flame.scale = Vector3.ONE * randf_range(0.8, 1.3)


func _steer(delta: float) -> void:
	var best: Node3D = null
	var best_dot := homing_cos
	for k in CombatUtil.living_karts(get_tree(), owner_kart):
		var to_k := CombatUtil.kart_center(k) - global_position
		var d := to_k.length()
		if d < 0.5 or d > homing_range:
			continue
		var dot := _dir.dot(to_k / d)
		if dot > best_dot:
			best_dot = dot
			best = k
	if best == null:
		return
	var desired := (CombatUtil.kart_center(best) - global_position).normalized()
	var angle := _dir.angle_to(desired)
	if angle < 0.0001:
		return
	_dir = _dir.slerp(desired, minf(1.0, homing_turn * delta / angle)).normalized()


func _face_dir() -> void:
	var up := Vector3.UP if absf(_dir.y) < 0.99 else Vector3.FORWARD
	look_at(global_position + _dir, up)


func _explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	var root := get_parent()
	CombatFx.detach_trail(_trail, root)
	_trail = null
	Explosion.spawn(root, at, radius, damage, owner_kart, weapon_id, knockback_force, 0.6, color)
	queue_free()
