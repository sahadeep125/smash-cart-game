## Composes one match: arena, karts from the match setup, crates, camera and HUD.
## Works offline (one local player + bots) and networked (one kart per peer; the host
## simulates bots, combat and the clock, see scripts/net/match_sync.gd).
extends Node3D

const SPAWN_SPACING := 3.2

var setup: Dictionary
var arena: Arena
var player: Kart
var karts: Array[Kart] = []
var karts_by_id: Dictionary = {}
var crates: Array[WeaponCrate] = []
var camera: FollowCamera
var hud: HUD
var respawner: RespawnManager
## True offline and on the network host.
var authority := true
var my_peer := 1


func _ready() -> void:
	var networked := Net.is_active()
	authority = not Net.is_client()
	my_peer = Net.get_my_peer_id() if networked else 1
	setup = GameState.take_setup()
	if setup.is_empty():
		setup = MatchSetup.offline_from_settings()
	GameState.mode = str(setup.get("mode", "ffa"))
	if float(setup.get("duration", 0.0)) > 0.0:
		GameState.match_duration = float(setup["duration"])
	GameState.authority = authority

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	projectiles.add_to_group("projectile_root")
	add_child(projectiles)

	_spawn_crates()

	var slots: Array = setup["slots"]
	var spawn_xforms := _initial_spawns(slots)
	for i in slots.size():
		var kart := _create_kart(slots[i], spawn_xforms[i])
		if kart.is_player:
			player = kart

	respawner = RespawnManager.new()
	respawner.name = "RespawnManager"
	respawner.passive = not authority
	add_child(respawner)

	camera = FollowCamera.new()
	camera.name = "FollowCamera"
	camera.target = player if player else karts[0]
	add_child(camera)
	camera.make_current()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind_player(player)

	for kart in karts:
		kart.controls_enabled = false
	if networked:
		var sync := MatchSync.new()
		sync.name = "MatchSync"
		add_child(sync)
		sync.setup_match(self)
	else:
		start_match()


## Runs the countdown and starts the clock. Networked matches call this on every
## peer when the host says go.
func start_match() -> void:
	GameState.start_match(karts)
	# Hold the karts during the 3-2-1 countdown; the clock starts on "GO".
	GameState.set_paused_clock(true)
	await hud.play_countdown()
	if not is_inside_tree():
		return
	GameState.set_paused_clock(false)
	for kart in karts:
		kart.controls_enabled = true


func get_kart(id: int) -> Kart:
	return karts_by_id.get(id) as Kart


## Hands a kart to a bot (used when its player leaves a networked match).
func give_kart_to_ai(kart: Kart) -> void:
	for c in kart.get_children():
		if c is PlayerController or c is AIDriver:
			c.queue_free()
	kart.remote = false
	var ai := AIDriver.new()
	ai.name = "AIDriver"
	ai.difficulty = float(setup.get("ai_difficulty", 0.6))
	kart.add_child(ai)


func _create_kart(slot: Dictionary, xform: Transform3D) -> Kart:
	var kart := Kart.new()
	var peer := int(slot.get("peer", 0))
	var local := peer == my_peer
	kart.name = "Kart%d" % int(slot["id"])
	kart.setup(str(slot["name"]), slot["color"], local)
	kart.team = int(slot.get("team", -1))
	kart.net_id = int(slot["id"])
	# Bots run on the authority; human karts run on their own peer.
	kart.remote = not local and not (peer == 0 and authority)

	var health := Health.new()
	health.name = "Health"
	kart.add_child(health)
	var holder := WeaponHolder.new()
	holder.name = "WeaponHolder"
	holder.proxy = not authority
	kart.add_child(holder)

	if local:
		var pc := PlayerController.new()
		pc.name = "PlayerController"
		kart.add_child(pc)
	elif peer == 0 and authority:
		var ai := AIDriver.new()
		ai.name = "AIDriver"
		ai.difficulty = float(setup.get("ai_difficulty", Settings.ai_difficulty))
		kart.add_child(ai)

	add_child(kart)
	kart.global_transform = xform
	if not local:
		_add_name_tag(kart)
	karts.append(kart)
	karts_by_id[kart.net_id] = kart
	return kart


func _add_name_tag(kart: Kart) -> void:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = kart.kart_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	# Constant on-screen size so names stay readable at a distance.
	tag.fixed_size = true
	tag.pixel_size = 0.0016
	tag.position = Vector3(0, 2.35, 0)
	tag.modulate = Teams.team_color(kart.team) if kart.team >= 0 else Color(1, 1, 1, 0.9)
	tag.outline_modulate = Color(0.05, 0.07, 0.15, 0.85)
	tag.no_depth_test = false
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kart.add_child(tag)


func _spawn_crates() -> void:
	var points := arena.get_crate_spawn_points()
	for i in points.size():
		var crate := WeaponCrate.new()
		crate.name = "Crate%d" % i
		add_child(crate)
		crate.global_position = points[i].global_position
		crates.append(crate)


## Deterministic start positions (every peer computes the same ones).
## FFA: one kart per arena spawn point, extra karts beside them.
## TDM: each team starts grouped around its own base point.
func _initial_spawns(slots: Array) -> Array[Transform3D]:
	var points := arena.get_spawn_points()
	var out: Array[Transform3D] = []
	var n := points.size()
	if str(setup.get("mode", "ffa")) == "tdm":
		var team_count := maxi(int(setup.get("team_count", 2)), 1)
		var counts := {}
		for s in slots:
			var t := int(s["team"])
			var member := int(counts.get(t, 0))
			counts[t] = member + 1
			var base: Transform3D = points[int(round(float(t) * n / team_count)) % n].global_transform
			out.append(_offset_xform(base, member))
	else:
		for i in slots.size():
			var base: Transform3D = points[(i * 3) % n].global_transform if n == 8 else points[i % n].global_transform
			out.append(_offset_xform(base, i / n))
	return out


## Shifts a spawn sideways: 0, +1, -1, +2 … steps of SPAWN_SPACING.
func _offset_xform(base: Transform3D, k: int) -> Transform3D:
	if k == 0:
		return base
	var step := (k + 1) / 2
	var side := 1.0 if k % 2 == 1 else -1.0
	var right := base.basis.x.normalized()
	return Transform3D(base.basis, base.origin + right * side * step * SPAWN_SPACING)
