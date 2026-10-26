## Fast machine-gun tracer. Moves with a per-frame sweep so it never tunnels.
class_name BulletProjectile
extends Node3D

const HIT_RADIUS := 0.75

var owner_kart: Node3D
## Networked client copy: shows impacts but deals no damage.
var visual_only := false
var weapon_id := "machine_gun"
var damage := 4.0
var knockback_force := 0.6
var lifetime := 0.55
var velocity := Vector3.ZERO
var color := Color(1.0, 0.9, 0.25)

var _origin := Vector3.ZERO
var _age := 0.0
var _done := false


func setup(p_owner: Node3D, origin: Vector3, direction: Vector3, data: Dictionary, extra_speed := 0.0) -> void:
	owner_kart = p_owner
	_origin = origin
	damage = float(data.get("damage", damage))
	knockback_force = float(data.get("knockback", knockback_force))
	lifetime = float(data.get("lifetime", lifetime))
	color = data.get("color", color)
	velocity = direction.normalized() * (float(data.get("speed", 110.0)) + extra_speed)


func _ready() -> void:
	global_position = _origin
	_face_velocity()
	var mesh := MeshInstance3D.new()
	mesh.mesh = CombatFx.shared_box(Vector3(0.07, 0.07, 0.9))
	mesh.material_override = CombatFx.emissive_material(color, 4.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= lifetime:
		_finish()
		return
	var from := global_position
	var to := from + velocity * delta
	var hit := CombatUtil.sweep(self, from, to, HIT_RADIUS, owner_kart)
	if hit.is_empty():
		global_position = to
		return
	var kart: Node3D = hit.kart
	if kart != null:
		if not visual_only:
			CombatUtil.knockback(kart, velocity.normalized() * knockback_force)
			CombatUtil.deal_damage(kart, damage, owner_kart, weapon_id)
		CombatFx.burst(get_parent(), hit.position, color, 6, 5.0, 0.1, 0.25, -6.0)
	else:
		CombatFx.burst(get_parent(), hit.position, Color(1.0, 0.75, 0.4), 5, 4.0, 0.08, 0.3, -12.0)
	_finish()


func _face_velocity() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD
	look_at(global_position + velocity, up)


func _finish() -> void:
	_done = true
	queue_free()
