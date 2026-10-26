## Headless combat test. Run:
##   godot --headless --fixed-fps 60 --path . res://scripts/combat/combat_test.tscn
## Builds a floor, three karts (real Kart class when it loads, else an inner stub),
## a crate and spawn points, then exercises every weapon, death, respawn and pickup.
## Prints PASS/FAIL per check and quits with the number of failures as exit code.
extends Node3D

const KART_PATH := "res://scripts/kart/kart.gd"


## Minimal stand-in that follows the Kart contract (used only if Kart can't load).
class StubKart extends CharacterBody3D:
	signal fire_requested
	var kart_name := "Stub"
	var kart_color := Color.WHITE
	var is_player := false
	var alive := true
	var controls_enabled := true
	var throttle := 0.0
	var steer := 0.0
	var drift_held := false
	var knockback_total := Vector3.ZERO

	func _init() -> void:
		collision_layer = 2
		collision_mask = 3
		add_to_group("karts")
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var b := BoxShape3D.new()
		b.size = Vector3(1.6, 0.8, 2.4)
		cs.shape = b
		cs.position = Vector3(0, 0.45, 0)
		add_child(cs)

	func setup(p_name: String, p_color: Color, p_is_player: bool) -> void:
		kart_name = p_name
		kart_color = p_color
		is_player = p_is_player

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
		return f.normalized()

	func get_muzzle_transform() -> Transform3D:
		var fwd := get_forward()
		return Transform3D(Basis.looking_at(fwd, Vector3.UP), global_position + fwd * 1.6 + Vector3.UP * 0.65)

	func apply_knockback(impulse: Vector3) -> void:
		knockback_total += impulse

	func set_alive(value: bool) -> void:
		alive = value
		visible = value
		controls_enabled = value
		collision_layer = 2 if value else 0

	func respawn_at(xform: Transform3D) -> void:
		global_transform = xform
		velocity = Vector3.ZERO
		set_alive(true)

	func get_speed() -> float:
		return velocity.length()


var passes := 0
var fails := 0
var using_real_kart := false

var kills: Array = []
var respawns: Array = []
var pickups: Array = []
var explosions := 0
var shakes := 0
var died_count := 0
var knock_seen := {}

var a: Node3D  # shooter (player)
var b: Node3D  # target
var c: Node3D  # second target
var crate: WeaponCrate
var respawner: RespawnManager


func _ready() -> void:
	Engine.max_fps = 0
	Events.kart_killed.connect(func(v, k, w): kills.append([v, k, w]))
	Events.kart_respawned.connect(func(k): respawns.append(k))
	Events.weapon_picked_up.connect(func(k, w): pickups.append([k, w]))
	Events.explosion_happened.connect(func(_p, _r): explosions += 1)
	Events.camera_shake_requested.connect(func(_s): shakes += 1)
	_run.call_deferred()


func check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("PASS  ", label, ("  (" + detail + ")") if detail != "" else "")
	else:
		fails += 1
		print("FAIL  ", label, ("  (" + detail + ")") if detail != "" else "")


func wait(seconds: float) -> void:
	var frames := int(ceil(seconds * Engine.physics_ticks_per_second))
	for i in frames:
		await get_tree().physics_frame


func _make_kart(kart_name: String, color: Color, player: bool, pos: Vector3) -> Node3D:
	var kart: Node3D
	var script: Script = load(KART_PATH) if ResourceLoader.exists(KART_PATH) else null
	if script != null and script.can_instantiate():
		kart = script.new()
		using_real_kart = true
	else:
		kart = StubKart.new()
	kart.call("setup", kart_name, color, player)
	var h := Health.new()
	h.name = "Health"
	kart.add_child(h)
	var w := WeaponHolder.new()
	w.name = "WeaponHolder"
	kart.add_child(w)
	h.died.connect(func(_k): died_count += 1)
	add_child(kart)
	place(kart, pos)
	return kart


func place(kart: Node3D, pos: Vector3, face := Vector3.FORWARD) -> void:
	kart.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP), pos)
	if "velocity" in kart:
		kart.set("velocity", Vector3.ZERO)


func hp(kart: Node3D) -> float:
	return CombatUtil.get_health(kart).current_health


func holder(kart: Node3D) -> WeaponHolder:
	return CombatUtil.get_weapon_holder(kart)


func vuln(kart: Node3D) -> void:
	CombatUtil.get_health(kart).set_invulnerable(0.0)


func _build_world() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(10, 4, 1)
	wcs.shape = wbox
	wall.add_child(wcs)
	wall.position = Vector3(-40, 2, -15)
	add_child(wall)

	var proj := Node3D.new()
	proj.name = "Projectiles"
	proj.add_to_group("projectile_root")
	add_child(proj)

	for p in [Vector3(-30, 0.1, -30), Vector3(30, 0.1, 30), Vector3(-30, 0.1, 30), Vector3(60, 0.1, -60)]:
		var m := Marker3D.new()
		m.add_to_group("spawn_points")
		add_child(m)
		m.global_position = p


func _run() -> void:
	_build_world()
	a = _make_kart("Shooter", Color.ORANGE, true, Vector3(0, 0.05, 0))
	b = _make_kart("Target", Color.CYAN, false, Vector3(0, 0.05, -12))
	c = _make_kart("Bystander", Color.GREEN, false, Vector3(25, 0.05, 0))
	respawner = RespawnManager.new()
	add_child(respawner)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("start_match"):
		gs.call("start_match", [a, b, c])
	if not respawner._match_running():
		respawner.require_running_match = false
	print("Using ", "real Kart class" if using_real_kart else "StubKart", "; GameState running: ", respawner._match_running())
	await wait(0.1)

	# --- Health basics ---------------------------------------------------------
	check("health defaults to 100", hp(b) == 100.0, str(hp(b)))
	CombatUtil.get_health(b).take_damage(10, a, "test")
	check("spawn invulnerability blocks damage", hp(b) == 100.0, str(hp(b)))
	await wait(1.5)
	CombatUtil.get_health(b).take_damage(10, a, "test")
	check("damage lands after 1.5 s invulnerability", is_equal_approx(hp(b), 90.0), str(hp(b)))
	CombatUtil.get_health(b).heal(50)
	check("heal clamps to max", hp(b) == 100.0, str(hp(b)))
	for k in [a, b, c]:
		vuln(k)

	# --- Machine gun ------------------------------------------------------------
	place(a, Vector3(0, 0.05, 0))
	place(b, Vector3(0, 0.05, -12))
	holder(a).give_weapon("machine_gun")
	check("give_weapon machine_gun", holder(a).current_weapon_id == "machine_gun" and holder(a).ammo == 30)
	await wait(0.15)
	for i in 60:  # hold the trigger 1 s
		a.call("request_fire")
		place(b, Vector3(0, 0.05, -12))
		await get_tree().physics_frame
	var mg_dmg := 100.0 - hp(b)
	var mg_ammo := holder(a).ammo
	check("machine gun auto-fires while held", mg_ammo <= 30 - 9, "ammo left %d" % mg_ammo)
	check("machine gun damages target", mg_dmg >= 20.0, "damage %.0f" % mg_dmg)
	place(b, Vector3(50, 0.05, 50))  # out of the line of fire so it survives
	for i in 240:
		a.call("request_fire")
		await get_tree().physics_frame
	check("machine gun lost at 0 ammo", not holder(a).has_weapon() and holder(a).current_weapon_id == "")

	# --- Rocket -------------------------------------------------------------------
	CombatUtil.get_health(b).reset(); vuln(b)
	place(b, Vector3(0, 0.05, -14))
	place(a, Vector3(0, 0.05, 0))
	var expl_before := explosions
	var shakes_before := shakes
	var vel_before := CombatUtil.get_velocity(b).length()
	holder(a).give_weapon("rocket")
	await wait(0.15)
	a.call("request_fire")
	a.call("request_fire")  # same frame: cooldown must stop a double shot
	check("rocket cooldown prevents double fire", holder(a).ammo == 1, "ammo %d" % holder(a).ammo)
	var hit_kb := false
	for i in 60:
		await get_tree().physics_frame
		if CombatUtil.get_velocity(b).length() > vel_before + 1.0:
			hit_kb = true
		if b is StubKart and (b as StubKart).knockback_total.length() > 1.0:
			hit_kb = true
	var r_dmg := 100.0 - hp(b)
	check("rocket explosion damages target", r_dmg >= 15.0 and r_dmg <= 45.0, "damage %.1f" % r_dmg)
	check("rocket knockback applied", hit_kb)
	check("explosion_happened emitted", explosions > expl_before, str(explosions - expl_before))
	check("camera_shake_requested emitted", shakes > shakes_before, str(shakes - shakes_before))
	check("shooter not hurt by own weapons", hp(a) == 100.0, str(hp(a)))

	# Rocket into a wall (no karts nearby) explodes on world collision.
	place(a, Vector3(-40, 0.05, -2))
	place(b, Vector3(0, 0.05, -12))
	await wait(0.7)
	expl_before = explosions
	a.call("request_fire")
	await wait(0.8)
	check("rocket explodes on world collision", explosions > expl_before)
	check("rocket weapon lost at 0 ammo", not holder(a).has_weapon())

	# --- Kill + respawn -------------------------------------------------------------
	place(a, Vector3(0, 0.05, 0))
	place(b, Vector3(0, 0.05, -12))
	CombatUtil.get_health(b).current_health = 20.0
	var kills_before := kills.size()
	holder(a).give_weapon("rocket")
	await wait(0.15)
	a.call("request_fire")
	await wait(1.0)
	var kill_ok: bool = kills.size() == kills_before + 1 and kills.back()[0] == b and kills.back()[1] == a and kills.back()[2] == "rocket"
	check("kart_killed emitted once with killer + weapon", kill_ok, "kills %d" % (kills.size() - kills_before))
	check("Health.died emitted", died_count == 1, str(died_count))
	check("dead kart hidden (alive == false)", b.get("alive") == false)
	CombatUtil.get_health(b).take_damage(50, a, "rocket")
	check("no double kill on dead kart", kills.size() == kills_before + 1)
	var resp_before := respawns.size()
	await wait(2.0)
	check("no respawn before 3 s", respawns.size() == resp_before and b.get("alive") == false)
	await wait(1.3)
	check("kart respawned after 3 s", respawns.size() == resp_before + 1 and b.get("alive") == true)
	check("respawn resets health", hp(b) == 100.0, str(hp(b)))
	check("respawn grants invulnerability", CombatUtil.get_health(b).is_invulnerable())
	var far := b.global_position.distance_to(a.global_position)
	check("respawn at spawn point away from karts", far > 40.0, "dist to shooter %.1f, pos %s" % [far, b.global_position])
	holder(a).clear()

	# --- Mines -------------------------------------------------------------------
	place(b, Vector3(-60, 0.05, 60))
	place(a, Vector3(20, 0.05, 0))
	vuln(c)
	place(c, Vector3(40, 0.05, 40))
	await wait(0.2)
	holder(a).give_weapon("mine")
	await wait(0.15)
	a.call("request_fire")
	await get_tree().physics_frame
	var mines := get_tree().get_nodes_in_group("mines")
	check("mine dropped", mines.size() == 1)
	var mine_pos: Vector3 = (mines[0] as Node3D).global_position if mines.size() > 0 else Vector3.ZERO
	check("mine dropped behind kart", mine_pos.z > 1.5, str(mine_pos))
	place(a, Vector3(-10, 0.05, 30))  # drive away
	place(c, mine_pos)
	await wait(0.3)
	check("mine not triggered before arming", hp(c) == 100.0 and get_tree().get_nodes_in_group("mines").size() == 1)
	await wait(0.6)
	var mine_dmg := 100.0 - hp(c)
	check("armed mine explodes on kart proximity", mine_dmg >= 40.0, "damage %.1f" % mine_dmg)
	place(c, Vector3(40, 0.05, 40))
	place(a, Vector3(20, 0.05, 0))
	await wait(0.4)
	a.call("request_fire")
	await wait(1.5)  # owner parked right next to own mine
	check("mine ignores its owner", get_tree().get_nodes_in_group("mines").size() == 1 and hp(a) == 100.0)
	await wait(24.0)
	check("mine despawns after 25 s", get_tree().get_nodes_in_group("mines").size() == 0)
	check("mine weapon keeps last charge", holder(a).current_weapon_id == "mine" and holder(a).ammo == 1)

	# --- Shield --------------------------------------------------------------------
	holder(a).give_weapon("shield")
	await wait(0.15)
	a.call("request_fire")
	await get_tree().physics_frame
	CombatUtil.get_health(a).take_damage(30, c, "test")
	check("shield blocks damage", hp(a) == 100.0 and CombatUtil.get_health(a).is_invulnerable())
	await wait(5.2)
	check("shield expires", not CombatUtil.get_health(a).is_invulnerable())

	# --- Crate --------------------------------------------------------------------------
	crate = WeaponCrate.new()
	add_child(crate)
	crate.global_position = Vector3(-20, 0, -20)
	await wait(0.2)
	check("crate in group and available", crate.is_in_group("weapon_crates") and crate.is_available())
	holder(a).clear()
	place(a, Vector3(-20, 0.05, -20))
	await wait(0.3)
	check("crate gives weapon on enter", holder(a).has_weapon() and pickups.size() == 1, "got '%s'" % holder(a).current_weapon_id)
	check("weapon_picked_up emitted", pickups.size() == 1 and pickups[0][0] == a)
	check("crate hidden after pickup", not crate.is_available())
	await wait(6.2)
	check("crate respawns after 6 s", crate.is_available())
	await wait(0.5)
	check("crate ignores armed kart", pickups.size() == 1)
	holder(a).clear()
	await wait(0.6)
	check("crate re-gives to a kart that emptied its weapon inside", pickups.size() == 2 and holder(a).has_weapon())
	var dead_kart := c
	place(dead_kart, Vector3(-80, 0.05, 80))
	await wait(6.5)
	holder(a).clear()
	place(a, Vector3(30, 0.05, -30))
	await wait(0.1)
	dead_kart.call("set_alive", false)
	place(dead_kart, Vector3(-20, 0.05, -20))
	await wait(0.5)
	check("crate ignores dead kart", pickups.size() == 2)

	print("WeaponDB ids: ", WeaponDB.all_ids(), " names: ", WeaponDB.all_ids().map(func(i): return WeaponDB.get_display_name(i)))
	print("SUMMARY: damage MG %.0f, rocket %.1f, mine %.1f; kills %d; respawns %d; pickups %d; explosions %d" % [mg_dmg, r_dmg, mine_dmg, kills.size(), respawns.size(), pickups.size(), explosions])
	print("RESULT: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
