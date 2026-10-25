## Handles kart death and respawn: death explosion, hide the kart, then after
## `respawn_delay` bring it back at the spawn point farthest from living karts.
class_name RespawnManager
extends Node

@export var respawn_delay: float = 3.0
## When true (default) no respawns happen while GameState reports the match isn't running.
@export var require_running_match: bool = true

var _pending := {}


func _ready() -> void:
	Events.kart_killed.connect(_on_kart_killed)


func is_pending(kart: Node) -> bool:
	return _pending.has(kart)


func _on_kart_killed(victim: Node, _killer: Node, _weapon_id: String) -> void:
	if victim == null or not is_instance_valid(victim) or _pending.has(victim):
		return
	_pending[victim] = true
	if victim is Node3D:
		_spawn_death_fx.call_deferred((victim as Node3D).global_position)
	if victim.has_method("set_alive"):
		victim.call("set_alive", false)
	var holder := CombatUtil.get_weapon_holder(victim)
	if holder != null:
		holder.clear()
	get_tree().create_timer(respawn_delay, false).timeout.connect(_respawn.bind(victim))


func _respawn(kart: Node) -> void:
	_pending.erase(kart)
	if not is_instance_valid(kart) or not kart.is_inside_tree():
		return
	if not _match_running():
		return
	var xform := pick_spawn_transform(kart)
	if kart.has_method("respawn_at"):
		kart.call("respawn_at", xform)
	elif kart is Node3D:
		(kart as Node3D).global_transform = xform
		if kart.has_method("set_alive"):
			kart.call("set_alive", true)
	var health := CombatUtil.get_health(kart)
	if health != null:
		health.reset()
	var holder := CombatUtil.get_weapon_holder(kart)
	if holder != null:
		holder.clear()
	var root := CombatUtil.get_projectile_root(self)
	CombatFx.burst(root, xform.origin + Vector3.UP * 0.6, Color(0.4, 0.9, 1.0), 24, 6.0, 0.14, 0.6, 2.0)
	CombatFx.flash_light(root, xform.origin + Vector3.UP, Color(0.4, 0.9, 1.0), 3.0, 6.0, 0.4)
	Events.kart_respawned.emit(kart)


## Spawn point (group "spawn_points") with the largest distance to the nearest living kart.
func pick_spawn_transform(kart: Node) -> Transform3D:
	var points := get_tree().get_nodes_in_group("spawn_points")
	var others := CombatUtil.living_karts(get_tree(), kart)
	var best: Node3D = null
	var best_score := -INF
	for p in points:
		if not (p is Node3D):
			continue
		var pos := (p as Node3D).global_position
		var nearest := 1000.0
		for o in others:
			nearest = minf(nearest, pos.distance_to(o.global_position))
		var score := nearest + randf() * 0.5  # tiny jitter breaks ties
		if score > best_score:
			best_score = score
			best = p
	if best == null:
		return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	return best.global_transform


func _match_running() -> bool:
	if not require_running_match:
		return true
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("is_running"):
		return bool(gs.call("is_running"))
	return true


func _spawn_death_fx(at: Vector3) -> void:
	var root := CombatUtil.get_projectile_root(self)
	if root == null:
		return
	# Big visual-only blast (no damage) with a little knockback for drama.
	Explosion.spawn(root, at + Vector3.UP * 0.5, 5.0, 0.0, null, "death", 6.0, 0.8, Color(1.0, 0.35, 0.1))
