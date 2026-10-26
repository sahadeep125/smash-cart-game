## Simple AI controller: grabs weapon crates when unarmed, hunts karts when armed,
## steers around walls with raycasts and backs out when stuck.
## Works without crates / WeaponHolder present (falls back to wandering / bumping).
class_name AIDriver
extends Node

enum Mode { WANDER, CRATE, CHASE, MINE_RUN }

@export_range(0.0, 1.0) var difficulty: float = 0.5

var kart: Kart
var mode: Mode = Mode.WANDER

var _rng := RandomNumberGenerator.new()
var _think_left: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_kart: Kart
var _target_crate: Node3D
var _target_age: float = 0.0
var _blacklist: Dictionary = {}   # crate instance id -> seconds left
var _stuck_time: float = 0.0
var _recover_left: float = 0.0
var _recover_steer: float = 1.0
var _detour_left: float = 0.0
var _aim_time: float = 0.0
var _mine_hold: float = 0.0
var _lane_offset: float = 0.0
var _personal_bias: float = 1.0
var _last_steer: float = 0.0


func _ready() -> void:
	_rng.randomize()
	kart = get_parent() as Kart
	process_physics_priority = -1
	_think_left = _rng.randf_range(0.0, 0.3)
	_lane_offset = _rng.randf_range(-3.0, 3.0)
	_personal_bias = _rng.randf_range(0.75, 1.3)


func _physics_process(delta: float) -> void:
	if kart == null:
		return
	if not kart.alive or not kart.controls_enabled:
		kart.throttle = 0.0
		kart.steer = 0.0
		kart.drift_held = false
		_stuck_time = 0.0
		_recover_left = 0.0
		_detour_left = 0.0
		return

	_tick_blacklist(delta)

	if _recover_left > 0.0:
		_recover_left -= delta
		kart.throttle = -1.0
		kart.steer = _recover_steer
		kart.drift_held = false
		if _recover_left <= 0.0:
			_detour_left = 0.7
		return

	if _detour_left > 0.0:
		# Keep turning away from the obstacle for a moment before seeking again.
		_detour_left -= delta
		kart.throttle = 1.0
		kart.steer = -_recover_steer
		kart.drift_held = false
		_check_stuck(delta)
		return

	_think_left -= delta
	_target_age += delta
	if _think_left <= 0.0:
		_think_left = _rng.randf_range(0.25, 0.45)
		_think()

	if _target_kart and is_instance_valid(_target_kart) and _target_kart.alive:
		var lead := lerpf(0.0, 0.35, difficulty)
		_target_pos = _target_kart.global_position + _target_kart.velocity * lead

	_drive(delta)
	_handle_fire(delta)
	_check_stuck(delta)


# --- Decisions -------------------------------------------------------------------

func _think() -> void:
	var holder := _get_holder()
	var armed := holder != null and holder.has_method("has_weapon") and holder.has_weapon()
	var weapon_id: String = holder.current_weapon_id if holder != null else ""

	if armed and weapon_id == "mine":
		mode = Mode.MINE_RUN
		_target_kart = null
		_target_crate = null
		if _target_age > 5.0 or _reached(_target_pos, 4.0):
			_pick_wander_target()
		return

	if armed or holder == null:
		# No combat module: still chase karts sometimes so there is bumping action.
		var enemy := _pick_enemy()
		if enemy and (armed or _rng.randf() < 0.5 or _target_kart == enemy):
			mode = Mode.CHASE
			_target_kart = enemy
			_target_crate = null
			return

	if not armed:
		var crate := _pick_crate()
		if crate:
			if crate != _target_crate:
				_target_age = 0.0
			mode = Mode.CRATE
			_target_crate = crate
			_target_kart = null
			_target_pos = crate.global_position
			if _target_age > 7.0:
				# Couldn't reach it in time (e.g. on the platform): try another.
				_blacklist[crate.get_instance_id()] = 8.0
				_target_crate = null
				_pick_wander_target()
			return

	_target_kart = null
	_target_crate = null
	if mode != Mode.WANDER or _target_age > 6.0 or _reached(_target_pos, 5.0):
		_pick_wander_target()


func _get_holder() -> WeaponHolder:
	if kart.has_method("get_weapon_holder"):
		return kart.get_weapon_holder()
	return null


func _pick_enemy() -> Kart:
	var best: Kart = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == null or k == kart or not k.alive or kart.is_ally(k):
			continue
		var d := kart.global_position.distance_to(k.global_position)
		# Slight randomness and stickiness so AIs spread over different targets.
		var score := d * _rng.randf_range(0.8, 1.2) * _personal_bias
		if k == _target_kart:
			score *= 0.7
		if score < best_score:
			best_score = score
			best = k
	return best


func _pick_crate() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("weapon_crates"):
		var c := n as Node3D
		if c == null:
			continue
		if c.has_method("is_available") and not c.is_available():
			continue
		if _blacklist.has(c.get_instance_id()):
			continue
		var d := kart.global_position.distance_to(c.global_position)
		if absf(c.global_position.y - kart.global_position.y) > 1.5:
			d *= 1.8  # on another level: harder to reach
		var score := d * _rng.randf_range(0.85, 1.15)
		if c == _target_crate:
			score *= 0.75
		if score < best_score:
			best_score = score
			best = c
	return best


func _pick_wander_target() -> void:
	mode = Mode.WANDER
	_target_age = 0.0
	var pool: Array[Node] = get_tree().get_nodes_in_group("spawn_points")
	pool.append_array(get_tree().get_nodes_in_group("crate_spawns"))
	if pool.size() > 0:
		var m := pool[_rng.randi() % pool.size()] as Node3D
		if m:
			_target_pos = m.global_position + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
			return
	_target_pos = Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))


func _reached(p: Vector3, radius: float) -> bool:
	var d := p - kart.global_position
	d.y = 0.0
	return d.length() < radius


func _tick_blacklist(delta: float) -> void:
	for key in _blacklist.keys():
		var t: float = _blacklist[key] - delta
		if t <= 0.0:
			_blacklist.erase(key)
		else:
			_blacklist[key] = t


# --- Driving -------------------------------------------------------------------

func _drive(_delta: float) -> void:
	var pos := kart.global_position
	var fwd := kart.get_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var goal := _target_pos
	var arena := get_tree().get_first_node_in_group("arena")
	if arena and arena.has_method("get_waypoint"):
		goal = arena.call("get_waypoint", pos, _target_pos)
	var to := goal - pos
	to.y = 0.0
	var dist := to.length()
	var routed := goal.distance_squared_to(_target_pos) > 0.01
	if dist > 12.0 and mode != Mode.CHASE and not routed:
		# Personal lane offset when far away, so AIs don't clump on one line.
		to += right * _lane_offset
	var angle := atan2(to.dot(right), to.dot(fwd)) if dist > 0.01 else 0.0
	if mode == Mode.WANDER:
		angle += sin(Time.get_ticks_msec() * 0.001 * _personal_bias) * 0.1 * (1.0 - difficulty)

	var seek := clampf(angle * 2.2, -1.0, 1.0)
	var speed := kart.get_speed()
	var avoid := _avoidance(fwd, speed)
	var steer_out := clampf(seek + avoid.x, -1.0, 1.0)

	var max_throttle := lerpf(0.82, 1.0, difficulty)
	var throttle_out := max_throttle
	if absf(angle) > 1.2 and speed > 12.0:
		throttle_out = 0.4
	if dist < 14.0 and absf(angle) > 0.8 and speed > 11.0:
		throttle_out = -0.3  # slow down for a tight turn onto a close goal
	if avoid.y > 0.75 and speed > 10.0:
		throttle_out = -0.4  # wall right ahead: brake
	if absf(angle) > 2.4 and dist < 10.0:
		# Target right behind and close: reverse and swing around.
		throttle_out = -0.8
		steer_out = -signf(angle)
	if routed and speed > 15.0:
		throttle_out = minf(throttle_out, 0.5)  # take ramps at a controllable speed
	if mode == Mode.CHASE and dist < 4.0:
		throttle_out = 1.0  # ram it

	kart.steer = steer_out
	kart.throttle = throttle_out
	kart.drift_held = absf(angle) > 0.7 and speed > 12.0 and avoid.y < 0.3 and _rng.randf() < 0.5 + difficulty * 0.5
	_last_steer = steer_out


## Returns Vector2(steer correction, front blockage 0..1).
func _avoidance(fwd: Vector3, speed: float) -> Vector2:
	var space := kart.get_world_3d().direct_space_state
	var origin := kart.global_position + Vector3.UP * 0.6
	var length := 5.0 + speed * 0.45
	var front := _ray(space, origin, fwd, length)
	var left := _ray(space, origin, fwd.rotated(Vector3.UP, 0.55), length * 0.8)
	var right := _ray(space, origin, fwd.rotated(Vector3.UP, -0.55), length * 0.8)
	var correction := 0.0
	correction += left * 1.3    # obstacle on the left: steer right
	correction -= right * 1.3
	if front > 0.0:
		var side := 1.0 if left <= right else -1.0
		if left == right:
			side = 1.0 if _last_steer >= 0.0 else -1.0
		correction += side * front * 1.6
	return Vector2(correction, front)


## 0 = no hit, approaching 1 = obstacle right in front. Ignores walkable slopes.
func _ray(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, length: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length, 1)
	q.exclude = [kart.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	var n: Vector3 = hit["normal"]
	if n.y > 0.55:
		return 0.0
	var p: Vector3 = hit["position"]
	return clampf(1.0 - origin.distance_to(p) / length, 0.0, 1.0)


func _check_stuck(delta: float) -> void:
	if kart.throttle > 0.3 and kart.get_speed() < 1.0:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time > 1.0:
		_stuck_time = 0.0
		_detour_left = 0.0
		_recover_left = _rng.randf_range(0.7, 1.2)
		_recover_steer = -signf(_last_steer) if absf(_last_steer) > 0.1 else (1.0 if _rng.randf() < 0.5 else -1.0)


# --- Combat ----------------------------------------------------------------------

func _handle_fire(delta: float) -> void:
	var holder := _get_holder()
	if holder == null or not holder.has_method("has_weapon") or not holder.has_weapon():
		_aim_time = 0.0
		_mine_hold = 0.0
		return
	var fwd := kart.get_forward()
	if holder.current_weapon_id == "mine":
		_mine_hold += delta
		var behind := _enemy_in_cone(-fwd, 20.0, 0.75)
		if behind or _mine_hold > 12.0:
			kart.request_fire()
			_mine_hold = 9.0 if not behind else _mine_hold
		return
	_mine_hold = 0.0
	var range_m := 26.0 if holder.current_weapon_id == "machine_gun" else 38.0
	var tol := lerpf(0.95, 0.985, difficulty)  # cos of the allowed aim error
	if _enemy_in_cone(fwd, range_m, tol):
		_aim_time += delta
		if _aim_time >= lerpf(0.55, 0.08, difficulty):
			kart.request_fire()
	else:
		_aim_time = maxf(_aim_time - delta, 0.0)


func _enemy_in_cone(dir: Vector3, range_m: float, min_dot: float) -> bool:
	var origin := kart.global_position + Vector3.UP * 0.7
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == null or k == kart or not k.alive or kart.is_ally(k):
			continue
		var to := k.global_position + Vector3.UP * 0.7 - origin
		var d := to.length()
		if d > range_m or d < 0.5:
			continue
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		if flat.dot(dir) < min_dot:
			continue
		if _line_of_sight(origin, origin + to):
			return true
	return false


func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return kart.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
