## Radial explosion: damage with distance falloff, knockback, camera shake, chain-detonates
## mines, then plays an expanding fireball + debris and frees itself.
class_name Explosion
extends Node3D

const DURATION := 1.6

var radius := 4.0
var damage := 45.0
var source: Node3D
var weapon_id := ""
var knockback_force := 10.0
var shake := 0.6
var color := Color(1.0, 0.5, 0.15)
## Fraction of damage dealt at the very edge of the radius.
var edge_damage := 0.35

var _origin := Vector3.ZERO
var _applied := false
var _age := 0.0
var _fireball: MeshInstance3D
var _fire_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D


## Creates and adds an explosion. damage 0 = visual-only (still shakes and knocks back
## when knockback > 0).
static func spawn(parent: Node, at: Vector3, p_radius: float, p_damage: float, p_source: Node3D,
		p_weapon_id: String, p_knockback := 10.0, p_shake := 0.6, p_color := Color(1.0, 0.5, 0.15)) -> Explosion:
	if parent == null:
		return null
	var e := Explosion.new()
	e._origin = at
	e.radius = p_radius
	e.damage = p_damage
	e.source = p_source
	e.weapon_id = p_weapon_id
	e.knockback_force = p_knockback
	e.shake = p_shake
	e.color = p_color
	parent.add_child(e)
	return e


func _ready() -> void:
	global_position = _origin
	_build_visual()
	CombatSfx.play("explosion", _origin, self)


func _physics_process(_delta: float) -> void:
	# Applied on the first physics frame (not in _ready) so it is never run while the
	# parent is busy adding children.
	if _applied:
		return
	_applied = true
	_apply_effects()


func _apply_effects() -> void:
	var center := global_position
	var src: Node3D = source if is_instance_valid(source) else null
	for k in CombatUtil.living_karts(get_tree()):
		if k == src:
			continue  # no self-damage
		var offset := CombatUtil.kart_center(k) - center
		var d := offset.length()
		if d > radius:
			continue
		var f := 1.0 - d / radius
		if knockback_force > 0.0:
			var flat := Vector3(offset.x, 0.0, offset.z)
			flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var scale_k := 0.5 + 0.5 * f
			CombatUtil.knockback(k, flat * knockback_force * scale_k + Vector3.UP * knockback_force * 0.55 * scale_k)
		if damage > 0.0:
			CombatUtil.deal_damage(k, damage * lerpf(edge_damage, 1.0, f), src, weapon_id)

	for m in get_tree().get_nodes_in_group("mines"):
		if m is Node3D and m.has_method("trigger_chain") and (m as Node3D).global_position.distance_to(center) <= radius:
			m.call("trigger_chain")

	Events.explosion_happened.emit(center, radius)
	CombatUtil.request_shake(get_tree(), center, shake)


# --- Visuals -------------------------------------------------------------------

func _build_visual() -> void:
	_fire_mat = CombatFx.emissive_material(color, 3.0, 0.85)
	_fireball = MeshInstance3D.new()
	_fireball.mesh = CombatFx.shared_sphere(1.0, 10, 5)
	_fireball.material_override = _fire_mat
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireball.scale = Vector3.ONE * 0.2
	add_child(_fireball)

	_core_mat = CombatFx.emissive_material(Color(1.0, 0.95, 0.6), 6.0, 0.99)
	_core = MeshInstance3D.new()
	_core.mesh = CombatFx.shared_sphere(1.0, 8, 4)
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.scale = Vector3.ONE * 0.1
	add_child(_core)

	var s := clampf(radius / 4.0, 0.5, 2.5)
	CombatFx.burst(self, _origin, color, int(26 * s), 13.0 * s, 0.28, 1.1, -22.0, true)
	CombatFx.burst(self, _origin + Vector3.UP * 0.3, Color(0.35, 0.33, 0.32, 0.8), int(14 * s), 3.5 * s, 0.9, 1.3, 2.0, false)
	CombatFx.flash_light(self, _origin + Vector3.UP, color, 6.0, radius * 3.0, 0.35)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / 0.45, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - t, 3.0)
	if _fireball != null:
		_fireball.scale = Vector3.ONE * lerpf(0.2, radius * 0.85, ease_out)
		_fire_mat.albedo_color.a = 0.85 * (1.0 - t)
		_fire_mat.emission_energy_multiplier = 3.0 * (1.0 - t) + 0.2
		if t >= 1.0:
			_fireball.visible = false
	if _core != null:
		var tc := clampf(_age / 0.2, 0.0, 1.0)
		_core.scale = Vector3.ONE * lerpf(0.1, radius * 0.45, tc)
		_core_mat.albedo_color.a = 1.0 - tc
		if tc >= 1.0:
			_core.visible = false
	if _age >= DURATION:
		queue_free()
