## Kart health with brief spawn invulnerability. Child of a kart, node name "Health".
class_name Health
extends Node

signal health_changed(current: float, max_value: float)
signal died(killer: Node)
## Extra (not in the contract): fired for every hit that lands.
signal damaged(amount: float, source: Node)

const BUBBLE_COLOR := Color(0.35, 0.85, 1.0)

@export var max_health: float = 100.0
@export var spawn_invulnerability: float = 1.5

var current_health: float = 100.0
var last_attacker: Node = null

var _invulnerable_time := 0.0
var _dead := false
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _pulse := 0.0


func _ready() -> void:
	current_health = max_health
	set_invulnerable(spawn_invulnerability)


func get_kart() -> Node3D:
	return get_parent() as Node3D


func take_damage(amount: float, source: Node, weapon_id := "") -> void:
	if _dead or amount <= 0.0 or _invulnerable_time > 0.0:
		return
	var kart := get_kart()
	if kart != null and kart.get("alive") == false:
		return
	current_health = maxf(current_health - amount, 0.0)
	if source != null and is_instance_valid(source) and source != kart:
		last_attacker = source
	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die(source, weapon_id)


func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


## Full health, alive again, with spawn invulnerability.
func reset() -> void:
	_dead = false
	last_attacker = null
	current_health = max_health
	health_changed.emit(current_health, max_health)
	set_invulnerable(spawn_invulnerability)


## Networked clients: mirror the host's health and invulnerability.
func net_set(current: float, invulnerable_time: float) -> void:
	if _dead:
		return
	if not is_equal_approx(current, current_health):
		var lost := current_health - current
		current_health = current
		if lost > 0.0:
			damaged.emit(lost, null)
		health_changed.emit(current_health, max_health)
	if invulnerable_time > 0.05 and _invulnerable_time <= 0.0:
		set_invulnerable(invulnerable_time)
	elif invulnerable_time <= 0.0 and _invulnerable_time > 0.0:
		set_invulnerable(0.0)


## Networked clients: the host says this kart died. Emits the same signals as a local death.
func net_kill(killer: Node, weapon_id: String) -> void:
	if _dead:
		return
	current_health = 0.0
	health_changed.emit(current_health, max_health)
	_die(killer, weapon_id)


func is_dead() -> bool:
	return _dead


func get_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


## Blocks all damage for `seconds` (never shortens a longer running window, except 0 clears it).
func set_invulnerable(seconds: float) -> void:
	if seconds <= 0.0:
		_invulnerable_time = 0.0
	else:
		_invulnerable_time = maxf(_invulnerable_time, seconds)
	_update_bubble()


func is_invulnerable() -> bool:
	return _invulnerable_time > 0.0


func get_invulnerable_time() -> float:
	return _invulnerable_time


func _die(source: Node, weapon_id: String) -> void:
	_dead = true
	_invulnerable_time = 0.0
	_update_bubble()
	var kart := get_kart()
	var killer: Node = null
	if source != null and is_instance_valid(source) and source != kart:
		killer = source
	died.emit(killer)
	Events.kart_killed.emit(kart, killer, weapon_id)


func _physics_process(delta: float) -> void:
	if _invulnerable_time > 0.0:
		_invulnerable_time = maxf(_invulnerable_time - delta, 0.0)
		if _invulnerable_time == 0.0:
			_update_bubble()


func _process(delta: float) -> void:
	if _bubble != null and _bubble.visible:
		_pulse += delta * 6.0
		var fade := clampf(_invulnerable_time / 0.5, 0.0, 1.0)  # fade out at the end
		_bubble_mat.albedo_color.a = (0.18 + 0.08 * sin(_pulse)) * fade
		_bubble.rotate_y(delta * 1.5)


# --- Shield bubble shown while invulnerable --------------------------------

func _update_bubble() -> void:
	var kart := get_kart()
	if kart == null:
		return
	var want := _invulnerable_time > 0.0 and not _dead
	if want and _bubble == null:
		_bubble = MeshInstance3D.new()
		_bubble.name = "ShieldBubble"
		_bubble.mesh = CombatFx.shared_sphere(1.6, 10, 5)
		_bubble_mat = CombatFx.emissive_material(BUBBLE_COLOR, 1.2, 0.22)
		_bubble.material_override = _bubble_mat
		_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bubble.position = Vector3(0, 0.55, 0)
		kart.add_child.call_deferred(_bubble)
	if _bubble != null:
		_bubble.visible = want
