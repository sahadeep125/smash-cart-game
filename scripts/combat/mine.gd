## Proximity mine dropped behind a kart. Arms after a short delay, explodes when an
## enemy kart comes close (the owner never triggers it), fizzles out after its lifetime.
## Explosions nearby set it off too (chain reaction).
class_name Mine
extends Node3D

var owner_kart: Node3D
## Networked: id shared with clients; visual_only copies never trigger by themselves.
var net_id := -1
var visual_only := false
var weapon_id := "mine"
var damage := 50.0
var radius := 3.5
var trigger_radius := 1.8
var arm_time := 0.6
var lifetime := 25.0
var knockback_force := 9.0
var color := Color(0.95, 0.2, 0.55)

var _origin := Vector3.ZERO
var _age := 0.0
var _done := false
var _light_mat: StandardMaterial3D
var _body: Node3D


func setup(p_owner: Node3D, at: Vector3, data: Dictionary) -> void:
	owner_kart = p_owner
	_origin = at
	damage = float(data.get("damage", damage))
	radius = float(data.get("radius", radius))
	trigger_radius = float(data.get("trigger_radius", trigger_radius))
	arm_time = float(data.get("arm_time", arm_time))
	lifetime = float(data.get("lifetime", lifetime))
	knockback_force = float(data.get("knockback", knockback_force))
	color = data.get("color", color)


func is_armed() -> bool:
	return _age >= arm_time and not _done


func _ready() -> void:
	add_to_group("mines")
	global_position = _snap_to_ground(_origin)
	_build_visual()


func _snap_to_ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 6.0, CombatUtil.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var shell := MeshInstance3D.new()
	shell.mesh = CombatFx.shared_cylinder(0.38, 0.5, 0.2, 8)
	shell.position = Vector3(0, 0.1, 0)
	shell.material_override = CombatFx.flat_material(Color(0.16, 0.16, 0.2), 0.5)
	_body.add_child(shell)

	# Coloured stud ring in the owner's colour if available.
	var ring_color: Color = color
	if owner_kart != null and owner_kart.get("kart_color") is Color:
		ring_color = owner_kart.get("kart_color")
	for i in 6:
		var stud := MeshInstance3D.new()
		stud.mesh = CombatFx.shared_box(Vector3(0.12, 0.1, 0.12))
		var a := TAU * i / 6.0
		stud.position = Vector3(cos(a) * 0.42, 0.12, sin(a) * 0.42)
		stud.material_override = CombatFx.flat_material(ring_color)
		_body.add_child(stud)

	var light := MeshInstance3D.new()
	light.mesh = CombatFx.shared_sphere(0.12, 6, 3)
	light.position = Vector3(0, 0.24, 0)
	_light_mat = CombatFx.emissive_material(color, 0.5)
	light.material_override = _light_mat
	_body.add_child(light)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= lifetime:
		_fizzle()
		return
	if _age < arm_time or visual_only:
		return
	for k in CombatUtil.living_enemies(get_tree(), owner_kart):
		var d := k.global_position - global_position
		if absf(d.y) < 2.0 and Vector2(d.x, d.z).length() <= trigger_radius:
			detonate()
			return


func _process(_delta: float) -> void:
	if _light_mat == null:
		return
	# Slow blink while arming, fast bright blink once armed.
	var rate := 2.0 if _age < arm_time else 6.0
	var on := fmod(_age * rate, 1.0) < 0.5
	_light_mat.emission_energy_multiplier = (4.0 if is_armed() else 1.5) if on else 0.2


## Sets the mine off (from a kart or a nearby explosion).
func detonate() -> void:
	if _done or visual_only:
		return
	_done = true
	var src: Node3D = owner_kart if is_instance_valid(owner_kart) else null
	Explosion.spawn(get_parent(), global_position + Vector3.UP * 0.3, radius, damage, src, weapon_id, knockback_force, 0.55, color)
	queue_free()


## Chain reaction with a small delay so explosions ripple outward.
func trigger_chain(delay := 0.12) -> void:
	if _done or visual_only or not is_inside_tree():
		return
	get_tree().create_timer(delay, false).timeout.connect(detonate)


func _fizzle() -> void:
	_done = true
	CombatFx.burst(get_parent(), global_position + Vector3.UP * 0.2, Color(0.6, 0.6, 0.65), 8, 2.0, 0.12, 0.6, 1.0, false)
	queue_free()
