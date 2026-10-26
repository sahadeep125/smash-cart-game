## Headless test harness: arena + 4 AI karts + follow camera, runs N physics frames,
## prints positions / speeds and a summary, then quits.
## Run: godot --headless res://scripts/kart/kart_test_scene.tscn [-- --frames=1200 --map=harbor]
extends Node3D

@export var frames: int = 1200

var arena: ArenaBase
var map_id := Maps.DEFAULT
var karts: Array[Kart] = []
var camera: FollowCamera
var _frame: int = 0
var _start_pos: Array[Vector3] = []
var _travelled: Array[float] = []
var _max_speed: Array[float] = []
var _min_y: Array[float] = []
var _max_y: Array[float] = []
var _last_pos: Array[Vector3] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
	arena = Maps.create(map_id)
	add_child(arena)
	var spawns := arena.get_spawn_points()
	var colors: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(0.2, 0.8, 0.3), Color(0.95, 0.8, 0.2)]
	for i in 4:
		var k := Kart.new()
		k.setup("Kart%d" % i, colors[i], i == 0)
		var ai := AIDriver.new()
		ai.name = "AIDriver"
		ai.difficulty = 0.3 + 0.2 * i
		k.add_child(ai)
		add_child(k)
		k.respawn_at(spawns[i * 2].global_transform)
		karts.append(k)
		_start_pos.append(k.global_position)
		_last_pos.append(k.global_position)
		_travelled.append(0.0)
		_max_speed.append(0.0)
		_min_y.append(k.global_position.y)
		_max_y.append(k.global_position.y)
	camera = FollowCamera.new()
	add_child(camera)
	camera.set_target(karts[0])
	print("[kart_test] arena=%s spawns=%d crate_spawns=%d frames=%d" % [arena.get_display_name(), spawns.size(), arena.get_crate_spawn_points().size(), frames])


func _physics_process(_delta: float) -> void:
	_frame += 1
	for i in karts.size():
		var k := karts[i]
		var p := k.global_position
		_travelled[i] += Vector2(p.x - _last_pos[i].x, p.z - _last_pos[i].z).length()
		_last_pos[i] = p
		_max_speed[i] = maxf(_max_speed[i], k.get_speed())
		_min_y[i] = minf(_min_y[i], p.y)
		_max_y[i] = maxf(_max_y[i], p.y)
	if _frame % 120 == 0:
		var line := "[kart_test] f=%d" % _frame
		for k in karts:
			line += " | %s pos=(%.1f,%.2f,%.1f) v=%.1f" % [k.kart_name, k.global_position.x, k.global_position.y, k.global_position.z, k.get_speed()]
		print(line)
	if _frame >= frames:
		var ok := true
		for i in karts.size():
			var fell := _min_y[i] < -1.0
			var lazy := _travelled[i] < 30.0
			if fell or lazy:
				ok = false
			print("[kart_test] %s travelled=%.0fm max_speed=%.1f min_y=%.2f max_y=%.2f%s%s" % [karts[i].kart_name, _travelled[i], _max_speed[i], _min_y[i], _max_y[i], " FELL" if fell else "", " BARELY_MOVED" if lazy else ""])
		print("[kart_test] camera at (%.1f,%.1f,%.1f) fov=%.1f" % [camera.global_position.x, camera.global_position.y, camera.global_position.z, camera.fov])
		print("[kart_test] RESULT: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
