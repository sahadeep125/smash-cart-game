## Shared helpers for the combat module: kart lookup, damage, sweeps, shake.
## Karts are accessed duck-typed (has_method / get) so this module does not depend
## on the Kart class at parse time.
class_name CombatUtil
extends RefCounted

const LAYER_WORLD := 1
const LAYER_KARTS := 2
const LAYER_PROJECTILES := 4
const LAYER_PICKUPS := 8

## Height of a kart's "centre of mass" above its origin (kart origins sit on the ground).
const KART_CENTER_OFFSET := Vector3(0, 0.5, 0)


## Node new projectiles / effects are parented to.
static func get_projectile_root(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	var root := tree.get_first_node_in_group("projectile_root")
	if root != null:
		return root
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


static func get_health(kart: Node) -> Health:
	if kart == null or not is_instance_valid(kart):
		return null
	if kart.has_method("get_health"):
		return kart.call("get_health") as Health
	return kart.get_node_or_null("Health") as Health


static func get_weapon_holder(kart: Node) -> WeaponHolder:
	if kart == null or not is_instance_valid(kart):
		return null
	if kart.has_method("get_weapon_holder"):
		return kart.call("get_weapon_holder") as WeaponHolder
	return kart.get_node_or_null("WeaponHolder") as WeaponHolder


static func is_kart_alive(kart: Node) -> bool:
	if kart == null or not is_instance_valid(kart) or not kart.is_inside_tree():
		return false
	var a: Variant = kart.get("alive")
	if a != null and not bool(a):
		return false
	var h := get_health(kart)
	if h != null and h.is_dead():
		return false
	return true


## Walks up from a collider to the kart that owns it (or null).
static func find_kart(node: Node) -> Node3D:
	var n := node
	for i in 4:
		if n == null:
			return null
		if n.is_in_group("karts"):
			return n as Node3D
		n = n.get_parent()
	return null


static func kart_center(kart: Node3D) -> Vector3:
	return kart.global_position + KART_CENTER_OFFSET


static func get_forward(kart: Node3D) -> Vector3:
	if kart.has_method("get_forward"):
		return kart.call("get_forward")
	var f := -kart.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


static func get_muzzle(kart: Node3D) -> Transform3D:
	if kart.has_method("get_muzzle_transform"):
		return kart.call("get_muzzle_transform")
	var fwd := get_forward(kart)
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), kart.global_position + fwd * 1.6 + Vector3.UP * 0.6)


static func get_velocity(kart: Node) -> Vector3:
	var v: Variant = kart.get("velocity")
	return v if v is Vector3 else Vector3.ZERO


static func find_player_kart(tree: SceneTree) -> Node3D:
	for k in tree.get_nodes_in_group("karts"):
		if k.get("is_player") == true:
			return k as Node3D
	return null


static func living_karts(tree: SceneTree, exclude: Node = null) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for k in tree.get_nodes_in_group("karts"):
		if k != exclude and k is Node3D and is_kart_alive(k):
			out.append(k as Node3D)
	return out


static func deal_damage(kart: Node, amount: float, source: Node, weapon_id: String) -> void:
	var h := get_health(kart)
	if h != null:
		var src: Node = source if source != null and is_instance_valid(source) else null
		h.take_damage(amount, src, weapon_id)


static func knockback(kart: Node, impulse: Vector3) -> void:
	if kart != null and is_instance_valid(kart) and kart.has_method("apply_knockback"):
		kart.call("apply_knockback", impulse)


## Asks the camera to shake, scaled by distance to the player kart.
static func request_shake(tree: SceneTree, at: Vector3, strength: float, falloff_distance := 40.0) -> void:
	var player := find_player_kart(tree)
	var s := strength
	if player != null:
		var d := player.global_position.distance_to(at)
		s = strength * clampf(1.0 - d / falloff_distance, 0.0, 1.0)
	if s > 0.02:
		Events.camera_shake_requested.emit(clampf(s, 0.0, 1.0))


## Sweeps a segment against the world (ray) and karts (capsule-ish proximity).
## Returns {} when nothing was hit, else {position, normal, kart (Node3D or null)}.
static func sweep(from_node: Node3D, a: Vector3, b: Vector3, kart_radius: float, exclude: Node) -> Dictionary:
	var best_t := INF
	var result := {}
	var seg := b - a
	var seg_len := seg.length()
	if seg_len < 0.00001:
		return result

	var space := from_node.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(a, b, LAYER_WORLD | LAYER_KARTS)
	if exclude is CollisionObject3D and is_instance_valid(exclude):
		params.exclude = [(exclude as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		var kart := find_kart(hit.collider as Node)
		if kart == null or (kart != exclude and is_kart_alive(kart)):
			best_t = a.distance_to(hit.position) / seg_len
			result = {"position": hit.position, "normal": hit.normal, "kart": kart}

	# Proximity test so fast projectiles don't slip past karts between frames.
	for k in living_karts(from_node.get_tree(), exclude):
		var c := kart_center(k)
		var p := Geometry3D.get_closest_point_to_segment(c, a, b)
		var d := p - c
		d.y *= 0.7
		if d.length() <= kart_radius:
			var t := a.distance_to(p) / seg_len
			if t < best_t:
				best_t = t
				result = {"position": p, "normal": -seg / seg_len, "kart": k}
	return result


static func free_after(node: Node, seconds: float) -> void:
	if node != null and node.is_inside_tree():
		node.get_tree().create_timer(seconds, false).timeout.connect(node.queue_free)
