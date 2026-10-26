## Weapon pickup: a hovering, spinning, colour-cycling gem-box on a hexagonal pad.
## Gives a random weapon to an unarmed living kart, then hides and respawns.
class_name WeaponCrate
extends Area3D

@export var respawn_time: float = 6.0

const POLL_INTERVAL := 0.25
const HOVER_HEIGHT := 1.15

var _available := true
var _time := 0.0
var _poll := 0.0
var _gem: Node3D
var _shell_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _pad_mat: StandardMaterial3D
var _light: OmniLight3D
var _orbiters: Node3D


func _init() -> void:
	collision_layer = CombatUtil.LAYER_PICKUPS
	collision_mask = CombatUtil.LAYER_KARTS
	monitoring = true
	monitorable = true


func _ready() -> void:
	add_to_group("weapon_crates")
	_time = randf() * 10.0
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	cs.shape = box
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)
	_build_visual()
	body_entered.connect(_on_body_entered)


func is_available() -> bool:
	return _available


func _on_body_entered(body: Node) -> void:
	_try_give(body)


## Networked clients: show the host's crate state (no pickups happen locally).
func net_set_available(value: bool) -> void:
	if value == _available:
		return
	if value:
		_respawn()
	else:
		CombatFx.burst(get_parent(), global_position + Vector3.UP * HOVER_HEIGHT, Color(1, 1, 1), 14, 6.0, 0.14, 0.4, -6.0)
		CombatSfx.play("pickup", global_position, self)
		_set_available(false)


func _try_give(body: Node) -> bool:
	if not _available or not CombatUtil.is_authority(self):
		return false
	var kart := CombatUtil.find_kart(body)
	if kart == null or not CombatUtil.is_kart_alive(kart):
		return false
	var holder := CombatUtil.get_weapon_holder(kart)
	if holder == null or holder.has_weapon():
		return false
	var id := holder.give_random_weapon()
	Events.weapon_picked_up.emit(kart, id)
	CombatFx.burst(get_parent(), global_position + Vector3.UP * HOVER_HEIGHT, WeaponDB.get_color(id), 18, 7.0, 0.16, 0.5, -6.0)
	CombatSfx.play("pickup", global_position, self)
	_set_available(false)
	get_tree().create_timer(respawn_time, false).timeout.connect(_respawn)
	return true


func _respawn() -> void:
	_set_available(true)
	if _gem != null:
		_gem.scale = Vector3.ONE * 0.05
		var tw := create_tween()
		tw.tween_property(_gem, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_available(value: bool) -> void:
	_available = value
	set_deferred("monitoring", value)
	if _gem != null:
		_gem.visible = value
	if _light != null:
		_light.visible = value
	if _pad_mat != null:
		_pad_mat.emission_energy_multiplier = 1.2 if value else 0.2


func _physics_process(delta: float) -> void:
	# Karts parked inside the crate (e.g. that just ran out of ammo) still get one.
	if not _available or not monitoring:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL
	for b in get_overlapping_bodies():
		if _try_give(b):
			break


func _process(delta: float) -> void:
	_time += delta
	if _gem == null or not _gem.visible:
		return
	_gem.position.y = HOVER_HEIGHT + sin(_time * 2.2) * 0.15
	_gem.rotation.y = _time * 1.6
	var hue := fmod(_time * 0.12, 1.0)
	var c := Color.from_hsv(hue, 0.75, 1.0)
	_shell_mat.emission = c
	_shell_mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
	_core_mat.emission = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 1.0)
	_light.light_color = c
	_orbiters.rotation.y = -_time * 3.0


func _build_visual() -> void:
	# Hexagonal glowing pad on the ground.
	var pad := MeshInstance3D.new()
	pad.mesh = CombatFx.shared_cylinder(0.95, 1.05, 0.08, 6)
	pad.position = Vector3(0, 0.04, 0)
	_pad_mat = CombatFx.emissive_material(Color(0.25, 0.9, 1.0), 1.2)
	_pad_mat.albedo_color = Color(0.1, 0.2, 0.3)
	pad.material_override = _pad_mat
	add_child(pad)

	_gem = Node3D.new()
	_gem.name = "Gem"
	_gem.position = Vector3(0, HOVER_HEIGHT, 0)
	add_child(_gem)

	# Outer translucent cube balanced on a corner.
	var shell := MeshInstance3D.new()
	shell.mesh = CombatFx.shared_box(Vector3.ONE * 0.85)
	shell.basis = Basis.from_euler(Vector3(deg_to_rad(45.0), 0.0, deg_to_rad(35.26)))
	_shell_mat = CombatFx.emissive_material(Color(1.0, 0.3, 0.8), 1.4, 0.8)
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gem.add_child(shell)

	# Bright octahedron core.
	var core := MeshInstance3D.new()
	core.mesh = CombatFx.shared_sphere(0.32, 4, 2)
	_core_mat = CombatFx.emissive_material(Color(1.0, 0.95, 0.3), 3.0)
	core.material_override = _core_mat
	_gem.add_child(core)

	# Three small orbiting cubes.
	_orbiters = Node3D.new()
	_gem.add_child(_orbiters)
	for i in 3:
		var o := MeshInstance3D.new()
		o.mesh = CombatFx.shared_box(Vector3.ONE * 0.14)
		var a := TAU * i / 3.0
		o.position = Vector3(cos(a) * 0.8, 0.1 * (i - 1), sin(a) * 0.8)
		o.rotation = Vector3(a, a, 0)
		o.material_override = CombatFx.emissive_material(Color(0.4, 1.0, 0.6), 2.0)
		_orbiters.add_child(o)

	_light = OmniLight3D.new()
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.position = Vector3(0, HOVER_HEIGHT, 0)
	add_child(_light)
