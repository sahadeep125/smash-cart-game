## End-to-end headless test: main menu -> Play -> full (shortened) match -> match end
## screen -> Play again -> second match starts.
## Run: godot --headless --fixed-fps 60 --path . res://scripts/game/integration_test.tscn
extends Node

const MATCH_SECONDS := 40.0
const TIMEOUT_SECONDS := 150.0

var _checks: Array[String] = []
var _failed := 0
var _kills := 0
var _respawns := 0
var _pickups := 0
var _explosions := 0
var _weapons_used := {}
var _match_ended := false
var _results: Array = []
var _match_starts := 0


func _ready() -> void:
	# Survive scene changes by living directly under the root.
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		var driver: Node = (get_script() as GDScript).new()
		driver.name = "IntegrationDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	_run()


func _run() -> void:
	GameState.match_duration = MATCH_SECONDS
	Settings.ai_count = 5
	Settings.game_mode = "ffa"
	Events.kart_killed.connect(func(_v: Node, _k: Node, w: String) -> void:
		_kills += 1
		_weapons_used[w] = int(_weapons_used.get(w, 0)) + 1)
	Events.kart_respawned.connect(func(_k: Node) -> void: _respawns += 1)
	Events.weapon_picked_up.connect(func(_k: Node, _w: String) -> void: _pickups += 1)
	Events.explosion_happened.connect(func(_p: Vector3, _r: float) -> void: _explosions += 1)
	Events.match_started.connect(func() -> void: _match_starts += 1)
	Events.match_ended.connect(func(r: Array) -> void:
		_match_ended = true
		_results = r)

	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(10)
	var menu := get_tree().current_scene
	_check("main menu loads", menu != null and menu.scene_file_path == "res://scenes/main_menu.tscn")
	var play: Button = menu.get("_play_button") if menu else null
	_check("play button exists", play != null)
	if play == null:
		return _finish()
	play.pressed.emit()
	await _frames(20)
	var lobby := get_tree().current_scene
	_check("play screen opens from Play", lobby != null and lobby.scene_file_path == "res://scenes/lobby.tscn")
	lobby.call("_on_solo_start")
	await _frames(20)

	var game := get_tree().current_scene
	_check("game scene loads from Solo start", game != null and game.scene_file_path == "res://scenes/game.tscn")
	var karts := get_tree().get_nodes_in_group("karts")
	_check("6 karts spawned (1 player + 5 AI)", karts.size() == 6)
	var player_count := karts.filter(func(k: Node) -> bool: return k.get("is_player") == true).size()
	_check("exactly one player kart", player_count == 1)
	_check("weapon crates spawned", get_tree().get_nodes_in_group("weapon_crates").size() >= 8)
	_check("HUD present", game.get_node_or_null("HUD") != null)
	_check("camera is current", get_viewport().get_camera_3d() is FollowCamera)
	_check("match started", _match_starts == 1 and GameState.is_running())

	# Drive the player with real input actions for part of the match.
	var player: Node = karts.filter(func(k: Node) -> bool: return k.get("is_player") == true)[0]
	var start_pos: Vector3 = player.global_position
	await _seconds(4.0) # countdown
	Input.action_press("accelerate")
	Input.action_press("steer_left", 0.4)
	await _seconds(2.5)
	_check("player kart moves with input actions", player.global_position.distance_to(start_pos) > 5.0)
	Input.action_release("steer_left")
	Input.action_press("fire")

	var waited := 0.0
	var min_y := 1000.0
	while not _match_ended and waited < TIMEOUT_SECONDS:
		await _seconds(0.5)
		waited += 0.5
		for k in get_tree().get_nodes_in_group("karts"):
			if k.get("alive"):
				min_y = minf(min_y, (k as Node3D).global_position.y)
	Input.action_release("accelerate")
	Input.action_release("fire")

	_check("match ended by timer", _match_ended)
	_check("results list all 6 karts", _results.size() == 6)
	_check("kills happened (%d)" % _kills, _kills > 0)
	_check("respawns happened (%d)" % _respawns, _respawns > 0)
	_check("crate pickups happened (%d)" % _pickups, _pickups > 0)
	_check("explosions happened (%d)" % _explosions, _explosions > 0)
	_check("no alive kart below the floor (min y %.2f)" % min_y, min_y > -2.0)
	var sorted_ok := true
	for i in range(1, _results.size()):
		if int(_results[i - 1]["kills"]) < int(_results[i]["kills"]):
			sorted_ok = false
	_check("results sorted by kills", sorted_ok)
	var all_disabled := true
	for k in get_tree().get_nodes_in_group("karts"):
		if k.get("controls_enabled"):
			all_disabled = false
	_check("kart controls disabled after match", all_disabled)

	await _seconds(1.5)
	var hud := get_tree().current_scene.get_node_or_null("HUD")
	var end_screen: Node = hud.get("match_end_screen") if hud else null
	var end_visible: bool = end_screen != null and end_screen.get("_root") != null and (end_screen.get("_root") as Control).visible
	_check("match end screen visible", end_visible)

	if end_screen:
		var starts_before := _match_starts
		(end_screen.get("_play_again") as Button).pressed.emit()
		await _frames(30)
		_check("play again reloads game", get_tree().current_scene.scene_file_path == "res://scenes/game.tscn")
		await _seconds(4.0)
		_check("second match starts and runs", _match_starts == starts_before + 1 and GameState.is_running())
		_check("second match has 6 karts", get_tree().get_nodes_in_group("karts").size() == 6)

	print("weapon kills: ", _weapons_used)
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed += 1
	print(("PASS " if ok else "FAIL ") + label)


func _finish() -> void:
	print("INTEGRATION RESULT: %d passed, %d failed" % [_checks.size() - _failed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
