## Smoothed third-person chase camera with speed-based FOV and look-ahead,
## wall-clip avoidance (raycast on layer 1) and trauma-based screen shake.
class_name FollowCamera
extends Camera3D

@export var target: Node3D
@export var distance: float = 7.5
@export var height: float = 3.4
@export var look_height: float = 1.2
@export var look_ahead: float = 0.3      ## seconds of target velocity to look ahead
@export var follow_speed: float = 6.0
@export var yaw_speed: float = 4.0
@export var base_fov: float = 70.0
@export var max_fov_boost: float = 12.0
@export var max_shake_offset: float = 0.45
@export var shake_decay: float = 1.8

const WALL_MARGIN := 0.6

var _trauma: float = 0.0
var _yaw_dir: Vector3 = Vector3.FORWARD
var _last_target_pos: Vector3 = Vector3.ZERO
var _look_point: Vector3 = Vector3.ZERO
var _has_snapped: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	fov = base_fov
	near = 0.1
	far = 400.0
	var events := get_node_or_null("/root/Events")
	if events and events.has_signal("camera_shake_requested"):
		events.connect("camera_shake_requested", _on_shake_requested)
	current = true


func set_target(t: Node3D) -> void:
	target = t
	_has_snapped = false


## Jump straight to the chase position (e.g. at match start or respawn).
func snap_to_target() -> void:
	if not _target_usable():
		return
	_last_target_pos = target.global_position
	_yaw_dir = _target_forward()
	_look_point = _last_target_pos + Vector3.UP * look_height
	global_position = _desired_position(_last_target_pos)
	_safe_look_at(_look_point)
	_has_snapped = true


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _on_shake_requested(strength: float) -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings and "camera_shake" in settings and not bool(settings.get("camera_shake")):
		return
	add_trauma(strength)


func _physics_process(delta: float) -> void:
	var usable := _target_usable()
	if usable and not _has_snapped:
		snap_to_target()
	if usable:
		var tp := target.global_position
		if tp.distance_to(_last_target_pos) > 25.0:
			# Teleported (respawn / fall rescue): cut instead of a long swoop.
			_last_target_pos = tp
			_yaw_dir = _target_forward()
			global_position = _desired_position(tp)
		_last_target_pos = tp
		var tf := _target_forward()
		var reversing := false
		if target is CharacterBody3D:
			reversing = (target as CharacterBody3D).velocity.dot(tf) < -3.0
		if not reversing:
			_yaw_dir = _yaw_dir.slerp(tf, clampf(yaw_speed * delta, 0.0, 1.0)).normalized()

	var vel := _target_velocity() if usable else Vector3.ZERO
	var flat_vel := Vector3(vel.x, 0.0, vel.z)
	var speed := flat_vel.length()

	# Position: chase behind and above, pulled in before walls.
	var desired := _desired_position(_last_target_pos)
	desired = _avoid_walls(_last_target_pos + Vector3.UP * look_height, desired)
	if usable:
		global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))

	# Look slightly ahead of where the target is going.
	var look_target := _last_target_pos + Vector3.UP * look_height + flat_vel * look_ahead
	_look_point = _look_point.lerp(look_target, clampf(8.0 * delta, 0.0, 1.0))
	_safe_look_at(_look_point)

	var fov_target := base_fov + max_fov_boost * clampf(speed / 24.0, 0.0, 1.0)
	fov = lerpf(fov, fov_target, clampf(3.0 * delta, 0.0, 1.0))

	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	h_offset = 0.0
	v_offset = 0.0
	if _trauma <= 0.0:
		return
	var amount := _trauma * _trauma
	h_offset = _rng.randf_range(-1.0, 1.0) * max_shake_offset * amount
	v_offset = _rng.randf_range(-1.0, 1.0) * max_shake_offset * amount
	rotate_object_local(Vector3.FORWARD, _rng.randf_range(-1.0, 1.0) * 0.04 * amount)
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)


func _desired_position(tp: Vector3) -> Vector3:
	return tp - _yaw_dir * distance + Vector3.UP * height


func _avoid_walls(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return to
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return to
	dir /= length
	# Probe a little past the camera so it never sits right against a wall.
	var q := PhysicsRayQueryParameters3D.create(from, to + dir * WALL_MARGIN, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	var p: Vector3 = hit["position"]
	return p - dir * WALL_MARGIN + Vector3.UP * 0.3


func _safe_look_at(p: Vector3) -> void:
	var d := p - global_position
	if d.length_squared() < 0.01:
		return
	var up := Vector3.UP
	if absf(d.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(p, up)


func _target_usable() -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not target.is_visible_in_tree():
		return false
	if "alive" in target and not bool(target.get("alive")):
		return false
	return true


func _target_forward() -> Vector3:
	if target.has_method("get_forward"):
		var f: Vector3 = target.call("get_forward")
		return f
	var f := -target.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _target_velocity() -> Vector3:
	if target is CharacterBody3D:
		return (target as CharacterBody3D).velocity
	return Vector3.ZERO
