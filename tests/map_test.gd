## Maps and loadouts test: every map's layout (spawns and crates clear of solid
## geometry, previews, floor zones), a short bot match on each map, and the weapon
## loadout rules (start and respawn with the picked weapon, random, crates only).
## Run: godot --headless --fixed-fps 60 --path . res://tests/map_test.tscn
extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = (get_script() as GDScript).new()
		driver.name = "MapTestDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	_run()


func _run() -> void:
	_check("4 maps listed", Maps.ids().size() == 4)
	_check("random resolves to a real map", Maps.has_map(Maps.resolve(Maps.RANDOM)))
	_check("unknown map falls back", Maps.resolve("nope") == Maps.DEFAULT)

	for id in Maps.ids():
		await _check_layout(id)

	for id in Maps.ids():
		await _check_match(id)

	await _check_loadouts()
	await _check_boost_pad()

	print("MAP TEST RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check_layout(id: String) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var arena := Maps.create(id)
	holder.add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var spawns := arena.get_spawn_points()
	var crates := arena.get_crate_spawn_points()
	_check("%s: 8+ spawns" % id, spawns.size() >= 8)
	_check("%s: 8+ crate spots" % id, crates.size() >= 8)
	var space := arena.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Kart.BOX_SIZE
	var blocked := []
	for m in spawns:
		if _overlaps(space, box, m.global_position + Vector3(0, Kart.BOX_SIZE.y * 0.5 + 0.2, 0)):
			blocked.append(m.name)
	_check("%s: spawns clear of walls and props %s" % [id, blocked], blocked.is_empty())
	var min_gap := INF
	for i in spawns.size():
		for j in range(i + 1, spawns.size()):
			min_gap = minf(min_gap, spawns[i].global_position.distance_to(spawns[j].global_position))
	_check("%s: spawns at least 8 m apart (%.1f)" % [id, min_gap], min_gap >= 8.0)
	var small := SphereShape3D.new()
	small.radius = 0.6
	blocked = []
	for m in crates:
		if _overlaps(space, small, m.global_position):
			blocked.append(m.name)
	_check("%s: crate spots clear %s" % [id, blocked], blocked.is_empty())
	var preview := MapPreview.layout(id)
	_check("%s: preview has footprints" % id, (preview["footprints"] as Array).size() > 5)
	match id:
		"harbor":
			_check("harbor: pond is ice", arena.surface_at(Vector3(0, 0.1, 0)) == "ice")
		"rooftop":
			_check("rooftop: boost pad", arena.surface_at(Vector3(0, 0.1, 16)) == "boost")
	_check("%s: normal floor elsewhere" % id, arena.surface_at(Vector3(40, 0.1, 40)) == "")
	holder.queue_free()
	await get_tree().process_frame


func _overlaps(space: PhysicsDirectSpaceState3D, shape: Shape3D, pos: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos)
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()


## 7 bots on the map for 20 s: they drive, pick up crates and wreck each other.
func _check_match(id: String) -> void:
	GameState.reset()
	GameState.match_duration = 60.0
	var setup := MatchSetup.build("ffa", [{"peer": 1, "name": "You"}], 7, 2, 4, 60.0, 0.8)
	setup["map"] = id
	GameState.set_setup(setup)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _seconds(0.5)
	var game := get_tree().current_scene
	_check("%s: game loaded the map" % id, game.get("arena") != null and (game.get("arena") as ArenaBase).get_display_name() == Maps.display_name(id))
	var me: Kart = game.get("player")
	game.call("give_kart_to_ai", me)
	var start := {}
	for k: Kart in game.get("karts"):
		start[k] = k.global_position
	await _seconds(23.5)
	var moved := 0
	var low := 0
	for k: Kart in game.get("karts"):
		if k.global_position.distance_to(start[k]) > 5.0 or not k.alive:
			moved += 1
		if k.global_position.y < -1.0:
			low += 1
	var kills := 0
	for r in GameState.get_results():
		kills += int(r["kills"])
	var hurt := 0
	for k: Kart in game.get("karts"):
		if k.get_health().current_health < k.get_health().max_health:
			hurt += 1
	print("[map_test] %s: moved=%d/8 kills=%d damaged=%d" % [id, moved, kills, hurt])
	_check("%s: bots drive around" % id, moved >= 6)
	_check("%s: nobody under the floor" % id, low == 0)
	_check("%s: bots fight (kills=%d, damaged=%d)" % [id, kills, hurt], kills + hurt >= 1)


func _check_loadouts() -> void:
	_check("loadout ids", Loadout.choices().size() == 6 and Loadout.sanitize("bogus") == "")
	var setup := MatchSetup.build("ffa", [{"peer": 1, "name": "You", "weapon": "rocket"}], 3, 2, 4, 60.0, 0.6)
	var slots: Array = setup["slots"]
	_check("human slot keeps the pick", slots[0]["weapon"] == "rocket")
	_check("bots get random loadouts when a human picked one", slots[1]["weapon"] == Loadout.RANDOM)
	var plain := MatchSetup.build("ffa", [{"peer": 1, "name": "You"}], 3, 2, 4, 60.0, 0.6)
	_check("no pick: crates only for everyone", (plain["slots"] as Array).all(func(s: Dictionary) -> bool: return s["weapon"] == ""))
	_check("loadout survives the wire", MatchSetup.from_wire(MatchSetup.to_wire(setup))["slots"][0]["weapon"] == "rocket")

	GameState.reset()
	GameState.match_duration = 60.0
	setup["map"] = "scrapyard"
	GameState.set_setup(setup)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _seconds(4.0)  # countdown
	var game := get_tree().current_scene
	var me: Kart = game.get("player")
	var holder := me.get_weapon_holder()
	_check("starts the match with the picked weapon", holder.current_weapon_id == "rocket" and holder.ammo == WeaponDB.get_ammo("rocket"))
	game.call("request_loadout", me, "mine")
	me.get_health().take_damage(1000.0, null)
	await _seconds(0.2)
	_check("dead kart holds nothing", holder.current_weapon_id == "")
	await _seconds(3.4)
	_check("respawns with the new pick", me.alive and holder.current_weapon_id == "mine")
	game.call("request_loadout", me, Loadout.RANDOM)
	me.get_health().take_damage(1000.0, null)
	await _seconds(3.6)
	_check("random pick gives some weapon", me.alive and WeaponDB.has_weapon(holder.current_weapon_id))
	game.call("request_loadout", me, Loadout.NONE)
	me.get_health().take_damage(1000.0, null)
	await _seconds(3.6)
	_check("crates-only respawns empty", me.alive and holder.current_weapon_id == "")
	var bot: Kart = (game.get("karts") as Array)[1]
	_check("bot armed from its loadout", bot.loadout == Loadout.RANDOM)


func _check_boost_pad() -> void:
	GameState.reset()
	var setup := MatchSetup.build("ffa", [{"peer": 1, "name": "You"}], 1, 2, 4, 60.0, 0.6)
	setup["map"] = "rooftop"
	GameState.set_setup(setup)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _seconds(0.5)
	var game := get_tree().current_scene
	var me: Kart = game.get("player")
	while not me.controls_enabled:
		await get_tree().physics_frame
	for c in me.get_children():
		if c is PlayerController:
			c.queue_free()
	me.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 26)))  # facing -Z, towards the pad at z=16
	me.throttle = 1.0
	var boosted := false
	for i in 150:
		await get_tree().physics_frame
		me.throttle = 1.0
		if me.boost_time > 0.0:
			boosted = true
			break
	_check("driving over a boost pad boosts (at z=%.1f)" % me.global_position.z, boosted)


func _seconds(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("PASS ", name)
	else:
		_failed += 1
		print("FAIL ", name)
