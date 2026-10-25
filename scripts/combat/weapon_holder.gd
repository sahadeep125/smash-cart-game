## Holds the kart's current weapon and fires it. Child of a kart, node name "WeaponHolder".
## Listens to the kart's `fire_requested`. Auto-fire weapons keep firing while the
## trigger is held (requests on consecutive frames, or the player's "fire" action held);
## other weapons fire once per press (a request after a frame without one), limited by
## their cooldown; holding the trigger re-fires them only every HOLD_REFIRE_DELAY s.
class_name WeaponHolder
extends Node

signal weapon_changed(weapon_id: String, ammo: int)
signal weapon_fired(weapon_id: String)

const HOLD_REFIRE_DELAY := 0.9

var current_weapon_id: String = ""
var ammo: int = 0

var _cooldown := 0.0
var _trigger_frame := -100
var _since_shot := 100.0
var _kart: Node3D


func _ready() -> void:
	_kart = get_parent() as Node3D
	if _kart != null and _kart.has_signal("fire_requested"):
		_kart.connect("fire_requested", _on_fire_requested)


func has_weapon() -> bool:
	return current_weapon_id != "" and ammo > 0


func give_weapon(id: String) -> void:
	if not WeaponDB.has_weapon(id):
		push_warning("WeaponHolder: unknown weapon '%s'" % id)
		return
	current_weapon_id = id
	ammo = WeaponDB.get_ammo(id)
	_cooldown = 0.1
	weapon_changed.emit(current_weapon_id, ammo)


func give_random_weapon() -> String:
	var id := WeaponDB.random_id()
	give_weapon(id)
	return id


func clear() -> void:
	var had := current_weapon_id != ""
	current_weapon_id = ""
	ammo = 0
	if had:
		weapon_changed.emit("", 0)


## Fires once if possible. Returns true when a shot went out.
func fire() -> bool:
	if not has_weapon() or _cooldown > 0.0 or not CombatUtil.is_kart_alive(_kart):
		return false
	var id := current_weapon_id
	_cooldown = WeaponDB.get_cooldown(id)
	_since_shot = 0.0
	match id:
		"rocket":
			_fire_rocket()
		"machine_gun":
			_fire_bullet()
		"mine":
			_drop_mine()
		"shield":
			_activate_shield()
	ammo -= 1
	weapon_fired.emit(id)
	if ammo <= 0:
		clear()
	else:
		weapon_changed.emit(current_weapon_id, ammo)
	return true


func _on_fire_requested() -> void:
	var frame := Engine.get_physics_frames()
	var new_press := frame - _trigger_frame > 1
	_trigger_frame = frame
	if not has_weapon():
		return
	if WeaponDB.is_auto_fire(current_weapon_id) or new_press or _since_shot >= HOLD_REFIRE_DELAY:
		fire()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	if has_weapon() and WeaponDB.is_auto_fire(current_weapon_id) and _is_trigger_held():
		fire()


func _is_trigger_held() -> bool:
	if Engine.get_physics_frames() - _trigger_frame <= 2:
		return true
	if _kart == null or _kart.get("is_player") != true or _kart.get("controls_enabled") == false:
		return false
	return InputMap.has_action("fire") and Input.is_action_pressed("fire")


# --- Weapon behaviours -------------------------------------------------------

func _forward_speed(dir: Vector3) -> float:
	return maxf(CombatUtil.get_velocity(_kart).dot(dir), 0.0)


func _fire_rocket() -> void:
	var root := CombatUtil.get_projectile_root(self)
	var muzzle := CombatUtil.get_muzzle(_kart)
	var dir := -muzzle.basis.z.normalized()
	var r := RocketProjectile.new()
	r.setup(_kart, muzzle.origin, dir, WeaponDB.get_data("rocket"), _forward_speed(dir))
	root.add_child(r)
	CombatSfx.play("rocket", muzzle.origin, self)


func _fire_bullet() -> void:
	var root := CombatUtil.get_projectile_root(self)
	var muzzle := CombatUtil.get_muzzle(_kart)
	var data := WeaponDB.get_data("machine_gun")
	var spread := deg_to_rad(float(data.get("spread", 2.0)))
	var b := muzzle.basis.orthonormalized()
	var dir := -b.z
	dir = dir.rotated(b.y, randf_range(-spread, spread))
	dir = dir.rotated(b.x, randf_range(-spread, spread) * 0.4)
	# Alternate barrels slightly left/right for a twin-gun look.
	var side := 0.22 if ammo % 2 == 0 else -0.22
	var origin := muzzle.origin + b.x * side
	var bullet := BulletProjectile.new()
	bullet.setup(_kart, origin, dir, data, _forward_speed(dir))
	root.add_child(bullet)
	CombatSfx.play("shot", origin, self)


func _drop_mine() -> void:
	var root := CombatUtil.get_projectile_root(self)
	var fwd := CombatUtil.get_forward(_kart)
	var pos := _kart.global_position - fwd * 2.2
	var m := Mine.new()
	m.setup(_kart, pos, WeaponDB.get_data("mine"))
	root.add_child(m)
	CombatSfx.play("drop", pos, self)


func _activate_shield() -> void:
	var h := CombatUtil.get_health(_kart)
	if h != null:
		h.set_invulnerable(float(WeaponDB.get_stat("shield", "duration", 5.0)))
	CombatSfx.play("pickup", _kart.global_position, self)
