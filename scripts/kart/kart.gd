## Arcade kart: driving physics, drifting, bumping, knockback and respawn hooks.
## A controller child (PlayerController / AIDriver) writes throttle / steer / drift_held.
class_name Kart
extends CharacterBody3D

signal fire_requested
## Emitted when this kart bumps into another kart or hits a wall hard (for audio / fx).
signal bumped(other: Node, strength: float)
## Emitted when a drift boost fires.
signal drift_boosted
## Emitted when knockback hits a kart that another peer simulates (network forwards it).
signal remote_knockback(impulse: Vector3)

const BOX_SIZE := Vector3(1.6, 0.8, 2.4)
const FALL_LIMIT_Y := -20.0

@export var max_speed: float = 22.0
@export var acceleration: float = 20.0
@export var brake_decel: float = 38.0
@export var max_reverse_speed: float = 9.0
@export var reverse_accel: float = 14.0
@export var coast_drag: float = 5.0
@export var turn_rate: float = 2.5          ## rad/s at the best steering speed
@export var grip: float = 9.0               ## how fast sideways slip is removed
@export var drift_grip: float = 3.5
@export var drift_turn_mult: float = 1.3
@export var drift_charge_time: float = 0.6  ## drift this long to earn a boost
@export var boost_duration: float = 0.9
@export var boost_speed_mult: float = 1.22
@export var gravity: float = 28.0
@export var wall_bounce: float = 0.35
@export var bump_restitution: float = 0.7

var kart_name: String = "Kart"
var kart_color: Color = Color(0.9, 0.3, 0.2)
var is_player: bool = false
## Team index (>= 0) in Team Deathmatch, -1 in free-for-all.
var team: int = -1
## Stable id shared by every peer in a networked match (slot index).
var net_id: int = -1
## Networked: true when another peer simulates this kart; we only show its synced state.
var remote: bool = false
## Networked: set when the local controller pulled the trigger since the last state send.
var net_trigger: bool = false

var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_yaw := 0.0
var _net_age := 0.0
var _net_has_state := false
var _net_steer := 0.0
var _net_drift := false
var alive: bool = true
var controls_enabled: bool = true

var throttle: float = 0.0
var steer: float = 0.0
var drift_held: bool = false

var drifting: bool = false
var drift_time: float = 0.0
var drift_dir: float = 0.0
var boost_time: float = 0.0

var _model: KartModel
var _knock_time: float = 0.0
var _no_snap_time: float = 0.0
var _was_on_floor: bool = true
var _default_snap: float = 0.6
var _rng := RandomNumberGenerator.new()


func setup(p_name: String, p_color: Color, p_is_player: bool) -> void:
	kart_name = p_name
	kart_color = p_color
	is_player = p_is_player
	if _model:
		_model.set_color(kart_color)


func _ready() -> void:
	_rng.randomize()
	add_to_group("karts")
	collision_layer = 2
	collision_mask = 1 | 2
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(45.0)
	floor_snap_length = _default_snap
	floor_stop_on_slope = true
	floor_block_on_wall = false
	max_slides = 6
	safe_margin = 0.03

	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
		elif c is KartModel:
			_model = c
	if not has_shape:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = BOX_SIZE
		cs.shape = box
		cs.position = Vector3(0, BOX_SIZE.y * 0.5, 0)
		add_child(cs)
	if _model == null:
		_model = KartModel.new()
		_model.name = "Model"
		_model.kart_color = kart_color
		add_child(_model)
	var holder := get_weapon_holder()
	if holder:
		holder.weapon_changed.connect(_model.set_weapon)
		holder.weapon_fired.connect(_model.on_weapon_fired)


# --- Public API -------------------------------------------------------------

func is_ally(other: Node) -> bool:
	return other != self and team >= 0 and other != null and other.get("team") == team


func request_fire() -> void:
	if alive and controls_enabled:
		fire_requested.emit()


func get_health() -> Health:
	return get_node_or_null("Health") as Health


func get_weapon_holder() -> WeaponHolder:
	return get_node_or_null("WeaponHolder") as WeaponHolder


func get_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()


func get_muzzle_transform() -> Transform3D:
	var fwd := get_forward()
	var pos := global_position + fwd * (BOX_SIZE.z * 0.5 + 0.4) + Vector3.UP * 0.65
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)


func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Signed speed along the kart's forward direction.
func get_forward_speed() -> float:
	return velocity.dot(get_forward())


func is_boosting() -> bool:
	return boost_time > 0.0


func apply_knockback(impulse: Vector3) -> void:
	if not alive:
		return
	if remote:
		remote_knockback.emit(impulse)
		return
	velocity += impulse
	_knock_time = 0.45
	if impulse.y > 0.5:
		_no_snap_time = 0.3
		floor_snap_length = 0.0


func set_alive(value: bool) -> void:
	alive = value
	visible = value
	controls_enabled = value
	collision_layer = 2 if value else 0
	collision_mask = (1 | 2) if value else 0
	velocity = Vector3.ZERO
	throttle = 0.0
	steer = 0.0
	drift_held = false
	_end_drift(false)
	boost_time = 0.0


func respawn_at(xform: Transform3D) -> void:
	var fwd := -xform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xform.origin)
	_knock_time = 0.0
	_net_has_state = false
	set_alive(true)
	if _model:
		_model.reset_pose()


## Called by another kart when it bumps into this one.
func receive_bump(delta_v: Vector3) -> void:
	if remote:
		return  # its owner resolves its own collisions
	velocity += delta_v
	_knock_time = maxf(_knock_time, 0.2)


# --- Network state ----------------------------------------------------------------

## Packs what other peers need to show this kart: [pos, yaw, vel, steer, flags].
func net_get_state() -> Array:
	var flags := (1 if drifting else 0) | (2 if boost_time > 0.0 else 0)
	return [global_position, rotation.y, velocity, snappedf(steer, 0.01), flags]


## Applies a state packed by net_get_state() on the owning peer.
func net_apply_state(state: Array) -> void:
	if state.size() < 5:
		return
	_net_pos = state[0]
	_net_yaw = state[1]
	_net_vel = state[2]
	_net_steer = state[3]
	_net_drift = (int(state[4]) & 1) != 0
	boost_time = 0.3 if (int(state[4]) & 2) != 0 else 0.0
	_net_age = 0.0
	if not _net_has_state or global_position.distance_to(_net_pos) > 8.0:
		global_position = _net_pos
		rotation.y = _net_yaw
	_net_has_state = true


func _remote_process(delta: float) -> void:
	if not _net_has_state:
		return
	# Dead reckoning from the last state, eased towards it so corrections stay smooth.
	_net_age = minf(_net_age + delta, 0.35)
	var predicted := _net_pos + _net_vel * _net_age
	global_position = global_position.lerp(predicted, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 14.0, 0.0, 1.0))
	velocity = _net_vel
	if _model:
		_model.update_visual(delta, get_forward_speed(), _net_steer, _net_drift, false, Vector3.UP, true, global_transform.basis)


# --- Physics ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if remote:
		_remote_process(delta)
		return
	if global_position.y < FALL_LIMIT_Y:
		_rescue_from_fall()
		return

	_knock_time = maxf(_knock_time - delta, 0.0)
	boost_time = maxf(boost_time - delta, 0.0)
	if _no_snap_time > 0.0:
		_no_snap_time -= delta
		if _no_snap_time <= 0.0:
			floor_snap_length = _default_snap

	var in_throttle := clampf(throttle, -1.0, 1.0) if controls_enabled else 0.0
	var in_steer := clampf(steer, -1.0, 1.0) if controls_enabled else 0.0
	var on_floor := is_on_floor()
	if _was_on_floor and not on_floor and velocity.y > 1.5 and not _ground_below(1.2):
		velocity.y *= 1.4  # launch pop when leaving a kicker lip
	_was_on_floor = on_floor
	var fwd := get_forward()
	_update_drift(delta, on_floor, in_steer, velocity.dot(fwd))
	var right := Vector3(-fwd.z, 0.0, fwd.x)  # fwd rotated -90 deg about Y
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var fs := flat.dot(fwd)
	var ls := flat.dot(right)

	# Steering: weak at standstill, strongest at mid speed, a bit softer at top speed.
	var spd := absf(fs)
	var steer_factor := clampf(spd / 7.0, 0.0, 1.0) * lerpf(1.0, 0.7, clampf(spd / max_speed, 0.0, 1.0))
	var yaw_input := in_steer
	if drifting:
		# Drift direction is locked; steering only widens/tightens the arc.
		yaw_input = clampf(drift_dir * 0.8 + in_steer * 0.4, -1.0, 1.2) * drift_turn_mult
	if not on_floor:
		steer_factor *= 0.35
	var dir_sign := 1.0 if fs >= -0.5 else -1.0
	rotate_y(-yaw_input * turn_rate * steer_factor * dir_sign * delta)

	# Re-project velocity onto the new heading.
	fwd = get_forward()
	right = Vector3(-fwd.z, 0.0, fwd.x)
	fs = flat.dot(fwd)
	ls = flat.dot(right)

	if on_floor:
		var top := max_speed * (boost_speed_mult if boost_time > 0.0 else 1.0)
		if in_throttle > 0.05:
			if fs < -0.5:
				fs = move_toward(fs, 0.0, brake_decel * delta)
			elif fs < top:
				var a := acceleration * lerpf(1.0, 0.45, clampf(fs / top, 0.0, 1.0))
				if boost_time > 0.0:
					a *= 1.8
				fs = minf(fs + a * in_throttle * delta, top)
			else:
				fs = move_toward(fs, top, coast_drag * delta)
		elif in_throttle < -0.05:
			if fs > 0.5:
				fs = move_toward(fs, 0.0, brake_decel * -in_throttle * delta)
			else:
				fs = maxf(fs - reverse_accel * -in_throttle * delta, -max_reverse_speed)
		else:
			var drag := coast_drag if controls_enabled else coast_drag * 2.0
			fs = move_toward(fs, 0.0, drag * delta)
			if boost_time > 0.0 and fs > 0.0:
				fs = minf(fs + acceleration * delta, top)

		# Grip removes sideways slip; drifting and knockback keep more of it.
		var g := grip
		if drifting:
			g = drift_grip
		if _knock_time > 0.0:
			g = 1.2
		var new_ls := ls * exp(-g * delta)
		if drifting and fs > 0.0:
			# Some of the slide is converted back into forward motion.
			fs = minf(fs + absf(ls - new_ls) * 0.6, top)
		ls = new_ls
	else:
		# Air: tiny drag only.
		fs = move_toward(fs, 0.0, 0.5 * delta)

	var vy := velocity.y - gravity * delta
	if on_floor and _no_snap_time <= 0.0:
		# Follow the slope we're on, so ramp lips launch the kart upward.
		var n := get_floor_normal()
		var hv := fwd * fs + right * ls
		vy = -(n.x * hv.x + n.z * hv.z) / maxf(n.y, 0.3) - 0.2
	var pre := fwd * fs + right * ls
	if on_floor:
		# Slides never add speed beyond the current cap; excess (knockback, boost end) bleeds off.
		var cap := max_speed * (boost_speed_mult if boost_time > 0.0 else 1.0)
		pre = pre.limit_length(maxf(cap, flat.length() - coast_drag * delta))
	velocity = Vector3(pre.x, vy, pre.z)

	var pre_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_velocity)

	if _model:
		var floor_n := get_floor_normal() if is_on_floor() else Vector3.UP
		_model.update_visual(delta, get_forward_speed(), in_steer, drifting, drift_time >= drift_charge_time, floor_n, is_on_floor(), global_transform.basis)


func _update_drift(delta: float, on_floor: bool, in_steer: float, fs: float) -> void:
	var want := controls_enabled and drift_held
	if not drifting:
		if want and on_floor and fs > 7.0 and absf(in_steer) > 0.3:
			drifting = true
			drift_time = 0.0
			drift_dir = signf(in_steer)
		return
	if not want or fs < 4.0:
		_end_drift(want == false and fs >= 4.0)
		return
	if on_floor:
		drift_time += delta


func _end_drift(allow_boost: bool) -> void:
	if drifting and allow_boost and drift_time >= drift_charge_time:
		boost_time = boost_duration * clampf(drift_time / (drift_charge_time * 2.0), 0.6, 1.4)
		velocity += get_forward() * 3.0
		drift_boosted.emit()
	drifting = false
	drift_time = 0.0
	drift_dir = 0.0


func _handle_collisions(pre_velocity: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		var other := col.get_collider()
		if other is Kart:
			_bump_kart(other as Kart, n, pre_velocity)
		elif absf(n.y) < 0.6:
			var nf := Vector3(n.x, 0.0, n.z).normalized()
			var into := -pre_velocity.dot(nf)
			if into > 3.0:
				# Bounce off a wall and lose some speed, so we never grind along it.
				velocity += nf * into * wall_bounce
				velocity.x *= 0.85
				velocity.z *= 0.85
				if into > 9.0:
					bumped.emit(other, into)
					if is_player:
						_request_shake(clampf(into / 40.0, 0.1, 0.4))


func _bump_kart(other: Kart, n: Vector3, pre_velocity: Vector3) -> void:
	var nf := Vector3(n.x, 0.0, n.z)
	if nf.length_squared() < 0.0001:
		return
	nf = nf.normalized()
	var a := pre_velocity.dot(nf)          # our speed along the normal (negative = closing)
	var b := other.velocity.dot(nf)
	if a - b > -0.5:
		return  # already separating
	# Equal-mass collision with restitution along the contact normal.
	# A minimum separation speed keeps karts from staying glued together.
	var mean := (a + b) * 0.5
	var sep := maxf(bump_restitution * (b - a), 2.5)
	var a2 := mean + sep * 0.5
	var b2 := mean - sep * 0.5
	velocity += nf * (a2 - velocity.dot(nf))
	other.receive_bump(nf * (b2 - b))
	_knock_time = maxf(_knock_time, 0.2)
	var strength := absf(a - b)
	bumped.emit(other, strength)
	other.bumped.emit(self, strength)
	if (is_player or other.is_player) and strength > 6.0:
		_request_shake(clampf(strength / 40.0, 0.1, 0.35))


func _ground_below(dist: float) -> bool:
	var from := global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (dist + 0.3), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _rescue_from_fall() -> void:
	var points := get_tree().get_nodes_in_group("spawn_points")
	var xform := Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
	if not points.is_empty():
		var p := points[_rng.randi() % points.size()] as Node3D
		if p:
			xform = p.global_transform
	var fwd := -xform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xform.origin + Vector3.UP * 0.5)
	velocity = Vector3.ZERO
	_end_drift(false)
	boost_time = 0.0


func _request_shake(strength: float) -> void:
	var events := get_node_or_null("/root/Events")
	if events:
		events.emit_signal("camera_shake_requested", strength)
